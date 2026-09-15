package main

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestPricingLogsCorrelatedPriceRequest(t *testing.T) {
	var output bytes.Buffer
	server := newPricingServerWithLogger(time.Millisecond, slog.New(slog.NewJSONHandler(&output, nil)))
	request := httptest.NewRequest(http.MethodGet, "/price", nil)
	request.Header.Set("X-Request-ID", "pricing-healthy")
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var record map[string]any
	if err := json.Unmarshal(output.Bytes(), &record); err != nil {
		t.Fatalf("log record is invalid JSON: %v", err)
	}
	for key, want := range map[string]string{
		"level":      "INFO",
		"service":    "pricing",
		"request_id": "pricing-healthy",
		"event":      "price_request",
	} {
		if record[key] != want {
			t.Errorf("record[%q] = %#v, want %q", key, record[key], want)
		}
	}
	if record["status"] != float64(http.StatusOK) {
		t.Errorf("status = %#v, want %d", record["status"], http.StatusOK)
	}
	if duration, ok := record["duration_ms"].(float64); !ok || duration < 0 {
		t.Errorf("duration_ms = %#v, want non-negative number", record["duration_ms"])
	}
}
