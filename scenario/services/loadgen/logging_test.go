package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
)

func TestLoadgenLogsCompletedResponses(t *testing.T) {
	statuses := []int{http.StatusNoContent, http.StatusGatewayTimeout}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(statuses[0])
		statuses = statuses[1:]
	}))
	defer server.Close()

	var output bytes.Buffer
	loadgen := newGeneratorWithPrefix(server.URL, server.Client(), 1, "fixed", slog.New(slog.NewJSONHandler(&output, nil)))
	loadgenRequest(loadgen, 1)
	loadgenRequest(loadgen, 2)

	records := loadgenLogRecords(t, output.Bytes())
	if len(records) != 2 {
		t.Fatalf("log records = %d, want 2", len(records))
	}
	for index, want := range []struct {
		status  int
		outcome string
	}{
		{http.StatusNoContent, "success"},
		{http.StatusGatewayTimeout, "error"},
	} {
		record := records[index]
		for key, value := range map[string]string{
			"service": "loadgen",
			"event":   "checkout_request",
			"outcome": want.outcome,
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

func TestLoadgenLogsSafeTransportError(t *testing.T) {
	var output bytes.Buffer
	client := &http.Client{Transport: loadgenRoundTripper(func(*http.Request) (*http.Response, error) {
		return nil, errors.New("dial http://private.example/toxiproxy")
	})}
	loadgen := newGeneratorWithPrefix("http://private.example/checkout", client, 1, "fixed", slog.New(slog.NewJSONHandler(&output, nil)))
	loadgenRequest(loadgen, 1)

	records := loadgenLogRecords(t, output.Bytes())
	if len(records) != 1 {
		t.Fatalf("log records = %d, want 1", len(records))
	}
	record := records[0]
	if record["status"] != float64(0) || record["outcome"] != "error" || record["error"] != "loadgen transport error" {
		t.Fatalf("record = %#v, want safe loadgen transport failure", record)
	}
	if strings.Contains(output.String(), "private.example") || strings.Contains(output.String(), "toxiproxy") {
		t.Fatalf("log leaked transport detail: %s", output.String())
	}
}

func TestNewGeneratorUsesDistinctBootPrefixesAndCounters(t *testing.T) {
	requestIDs := make(chan string, 2)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestIDs <- r.Header.Get("X-Request-ID")
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	var firstOutput, secondOutput bytes.Buffer
	first, err := newGenerator(server.URL, server.Client(), 1, slog.New(slog.NewJSONHandler(&firstOutput, nil)))
	if err != nil {
		t.Fatalf("newGenerator() error = %v", err)
	}
	second, err := newGenerator(server.URL, server.Client(), 1, slog.New(slog.NewJSONHandler(&secondOutput, nil)))
	if err != nil {
		t.Fatalf("newGenerator() error = %v", err)
	}
	loadgenRequest(first, first.next.Add(1))
	loadgenRequest(second, second.next.Add(1))

	firstID, secondID := <-requestIDs, <-requestIDs
	firstPrefix, firstCounter := loadgenIDParts(t, firstID)
	secondPrefix, secondCounter := loadgenIDParts(t, secondID)
	if firstPrefix == secondPrefix {
		t.Fatalf("boot prefixes are the same: %q", firstPrefix)
	}
	if firstCounter != 1 || secondCounter != 1 {
		t.Fatalf("first counters = %d and %d, want 1", firstCounter, secondCounter)
	}
	if loadgenLogRecords(t, firstOutput.Bytes())[0]["request_id"] != firstID || loadgenLogRecords(t, secondOutput.Bytes())[0]["request_id"] != secondID {
		t.Fatal("logged request IDs do not match forwarded request IDs")
	}
}

func loadgenRequest(loadgen *generator, id uint64) {
	semaphore := make(chan struct{}, 1)
	semaphore <- struct{}{}
	var workers sync.WaitGroup
	workers.Add(1)
	loadgen.request(context.Background(), id, semaphore, &workers)
	workers.Wait()
}

func loadgenLogRecords(t *testing.T, output []byte) []map[string]any {
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

func loadgenIDParts(t *testing.T, id string) (string, uint64) {
	t.Helper()
	parts := strings.Split(id, "-")
	if len(parts) != 3 || parts[0] != "loadgen" || len(parts[1]) != 8 {
		t.Fatalf("request ID = %q, want loadgen boot-prefix counter", id)
	}
	if _, err := strconv.ParseUint(parts[1], 16, 32); err != nil {
		t.Fatalf("boot prefix = %q, want hexadecimal: %v", parts[1], err)
	}
	counter, err := strconv.ParseUint(parts[2], 10, 64)
	if err != nil || counter == 0 {
		t.Fatalf("counter = %q, want positive integer", parts[2])
	}
	return parts[1], counter
}
