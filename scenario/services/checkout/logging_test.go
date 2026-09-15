package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type failingTransport struct{}

func (failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errors.New("dial http://private.example/toxiproxy")
}

func TestCheckoutLogsCorrelatedPricingCall(t *testing.T) {
	var output bytes.Buffer
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	server := newCheckoutServerWithLogger("checkout-1", upstream.URL, upstream.Client(), time.Second, slog.New(slog.NewJSONHandler(&output, nil)))
	request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
	request.Header.Set("X-Request-ID", "checkout-healthy")
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	record := checkoutLogRecord(t, output.Bytes())
	for key, want := range map[string]string{
		"level":      "INFO",
		"service":    "checkout",
		"instance":   "checkout-1",
		"request_id": "checkout-healthy",
		"event":      "pricing_call",
		"upstream":   "pricing-api",
		"outcome":    "success",
	} {
		if record[key] != want {
			t.Errorf("record[%q] = %#v, want %q", key, record[key], want)
		}
	}
	if duration, ok := record["duration_ms"].(float64); !ok || duration < 0 {
		t.Errorf("duration_ms = %#v, want non-negative number", record["duration_ms"])
	}
}

func TestCheckoutLogsGenuineDeadline(t *testing.T) {
	var output bytes.Buffer
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer upstream.Close()

	server := newCheckoutServerWithLogger("checkout-3", upstream.URL, upstream.Client(), 5*time.Millisecond, slog.New(slog.NewJSONHandler(&output, nil)))
	request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
	request.Header.Set("X-Request-ID", "checkout-degraded")
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)

	if response.Code != http.StatusGatewayTimeout {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusGatewayTimeout)
	}
	record := checkoutLogRecord(t, output.Bytes())
	if record["outcome"] != "timeout" || record["error"] != "context deadline exceeded" {
		t.Fatalf("record = %#v, want timeout with genuine deadline", record)
	}
}

func TestCheckoutLogsNonDeadlineFailureWithoutURLLeak(t *testing.T) {
	var output bytes.Buffer
	server := newCheckoutServerWithLogger("checkout-3", "http://private.example", &http.Client{Transport: failingTransport{}}, time.Second, slog.New(slog.NewJSONHandler(&output, nil)))
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/checkout", nil))

	if response.Code != http.StatusGatewayTimeout {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusGatewayTimeout)
	}
	record := checkoutLogRecord(t, output.Bytes())
	if _, hasDeadline := record["error"]; hasDeadline || strings.Contains(output.String(), "context deadline exceeded") {
		t.Fatalf("nondeadline record claimed a deadline: %s", output.String())
	}
	if strings.Contains(output.String(), "http://private.example/toxiproxy") {
		t.Fatalf("log leaked physical error: %s", output.String())
	}
}

func checkoutLogRecord(t *testing.T, output []byte) map[string]any {
	t.Helper()
	decoder := json.NewDecoder(bytes.NewReader(output))
	var record map[string]any
	if err := decoder.Decode(&record); err != nil {
		t.Fatalf("log record is invalid JSON: %v", err)
	}
	return record
}
