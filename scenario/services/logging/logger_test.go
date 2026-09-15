package logging

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestNewWritesIdenticalJSONLines(t *testing.T) {
	var stdout bytes.Buffer
	path := filepath.Join(t.TempDir(), "service.jsonl")
	logger, closeFile, err := New(path, &stdout)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	logger.Info("", "service", "checkout", "request_id", "request-123", "event", "pricing_call")
	if err := closeFile(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}

	file, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	if !bytes.Equal(stdout.Bytes(), file) {
		t.Fatalf("stdout = %q, file = %q; want identical JSONL", stdout.String(), string(file))
	}

	var record map[string]any
	if err := json.Unmarshal(file, &record); err != nil {
		t.Fatalf("JSONL record is invalid: %v", err)
	}
	for key, want := range map[string]string{
		"level":      "INFO",
		"service":    "checkout",
		"request_id": "request-123",
		"event":      "pricing_call",
	} {
		if record[key] != want {
			t.Errorf("record[%q] = %#v, want %q", key, record[key], want)
		}
	}
	if _, ok := record["timestamp"].(string); !ok {
		t.Errorf("record timestamp = %#v, want string", record["timestamp"])
	}
}

func TestNewReturnsOpenError(t *testing.T) {
	_, _, err := New(filepath.Join(t.TempDir(), "missing", "service.jsonl"), &bytes.Buffer{})
	if err == nil {
		t.Fatal("New() error = nil, want file opening error")
	}
}
