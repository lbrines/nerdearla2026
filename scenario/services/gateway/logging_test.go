package main

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGatewayLogsCompletedCheckoutResponses(t *testing.T) {
	statuses := []int{http.StatusNoContent, http.StatusGatewayTimeout}
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(statuses[0])
		statuses = statuses[1:]
	}))
	defer backend.Close()

	var output bytes.Buffer
	h := newGatewayWithLogger([]string{backend.URL}, backend.Client(), slog.New(slog.NewJSONHandler(&output, nil))).handler()
	for _, requestID := range []string{"gateway-success", "gateway-error"} {
		request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
		request.Header.Set("X-Request-ID", requestID)
		h.ServeHTTP(httptest.NewRecorder(), request)
	}

	records := gatewayLogRecords(t, output.Bytes())
	if len(records) != 2 {
		t.Fatalf("log records = %d, want 2", len(records))
	}
	for index, want := range []struct {
		requestID string
		status    int
		outcome   string
	}{
		{"gateway-success", http.StatusNoContent, "success"},
		{"gateway-error", http.StatusGatewayTimeout, "error"},
	} {
		record := records[index]
		for key, value := range map[string]string{
			"service":    "gateway",
			"request_id": want.requestID,
			"event":      "checkout_request",
			"outcome":    want.outcome,
		} {
			if record[key] != value {
				t.Errorf("record %d %s = %#v, want %q", index, key, record[key], value)
			}
		}
		if record["status"] != float64(want.status) {
			t.Errorf("record %d status = %#v, want %d", index, record["status"], want.status)
		}
		if duration, ok := record["duration_ms"].(float64); !ok || duration < 0 {
			t.Errorf("record %d duration_ms = %#v, want non-negative number", index, record["duration_ms"])
		}
		if _, hasError := record["error"]; hasError {
			t.Errorf("record %d unexpectedly contains transport error: %#v", index, record["error"])
		}
	}
}

func TestGatewayLogsSafeTransportError(t *testing.T) {
	var output bytes.Buffer
	client := &http.Client{Transport: roundTripper(func(*http.Request) (*http.Response, error) {
		return nil, assertError("dial http://private.example/toxiproxy")
	})}
	h := newGatewayWithLogger([]string{"http://private.example"}, client, slog.New(slog.NewJSONHandler(&output, nil))).handler()
	request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
	request.Header.Set("X-Request-ID", "gateway-transport")
	response := httptest.NewRecorder()
	h.ServeHTTP(response, request)

	if response.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadGateway)
	}
	records := gatewayLogRecords(t, output.Bytes())
	if len(records) != 1 {
		t.Fatalf("log records = %d, want 1", len(records))
	}
	record := records[0]
	if record["status"] != float64(http.StatusBadGateway) || record["outcome"] != "error" || record["error"] != "gateway transport error" {
		t.Fatalf("record = %#v, want safe gateway transport failure", record)
	}
	if strings.Contains(output.String(), "private.example") || strings.Contains(output.String(), "toxiproxy") {
		t.Fatalf("log leaked transport detail: %s", output.String())
	}
}

func TestGatewayDoesNotLogLocalOrRejectedTraffic(t *testing.T) {
	var output bytes.Buffer
	h := newGatewayWithLogger([]string{"http://backend"}, http.DefaultClient, slog.New(slog.NewJSONHandler(&output, nil))).handler()
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/healthz", nil),
		httptest.NewRequest(http.MethodGet, "/metrics", nil),
		httptest.NewRequest(http.MethodPost, "/checkout", nil),
	} {
		h.ServeHTTP(httptest.NewRecorder(), request)
	}
	if output.Len() != 0 {
		t.Fatalf("local or rejected traffic was logged as checkout traffic: %s", output.String())
	}
}

func gatewayLogRecords(t *testing.T, output []byte) []map[string]any {
	t.Helper()
	decoder := json.NewDecoder(bytes.NewReader(output))
	var records []map[string]any
	for decoder.More() {
		var record map[string]any
		if err := decoder.Decode(&record); err != nil {
			t.Fatalf("log record is invalid JSON: %v", err)
		}
		records = append(records, record)
	}
	return records
}
