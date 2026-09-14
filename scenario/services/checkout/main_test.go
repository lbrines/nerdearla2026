package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHealthIsLocal(t *testing.T) {
	calls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	h := newHandler(upstream.URL, upstream.Client(), time.Second)
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if calls != 0 {
		t.Fatalf("upstream calls = %d, want 0", calls)
	}
}

func TestCheckoutPropagatesRequestID(t *testing.T) {
	var requestID string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID = r.Header.Get("X-Request-ID")
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	h := newHandler(upstream.URL, upstream.Client(), time.Second)
	request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
	request.Header.Set("X-Request-ID", "request-123")
	response := httptest.NewRecorder()
	h.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if requestID != "request-123" {
		t.Fatalf("upstream request ID = %q, want %q", requestID, "request-123")
	}
}

func TestCheckoutTimeoutDoesNotLeakUpstream(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer upstream.Close()

	h := newHandler(upstream.URL, upstream.Client(), 5*time.Millisecond)
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/checkout", nil))

	if response.Code != http.StatusGatewayTimeout {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusGatewayTimeout)
	}
	if strings.Contains(response.Body.String(), upstream.URL) {
		t.Fatal("timeout response leaked the physical upstream URL")
	}
}

func TestDebugUpstreamReportsOnlyLogicalOutcome(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	h := newHandler(upstream.URL, upstream.Client(), time.Second)
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/debug/upstream", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var body map[string]any
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if len(body) != 3 || body["logical_upstream"] != "pricing-api" || body["outcome"] != "success" {
		t.Fatalf("debug response = %#v, want only logical success fields", body)
	}
}

func TestDebugUpstreamReportsTimeout(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer upstream.Close()

	h := newHandler(upstream.URL, upstream.Client(), 5*time.Millisecond)
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/debug/upstream", nil))

	var body struct {
		Outcome string `json:"outcome"`
	}
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if response.Code != http.StatusOK || body.Outcome != "timeout" {
		t.Fatalf("status = %d, outcome = %q, want 200 timeout", response.Code, body.Outcome)
	}
}

func TestUnsupportedMethods(t *testing.T) {
	h := newHandler("http://invalid.example", http.DefaultClient, time.Second)
	for _, path := range []string{"/healthz", "/checkout", "/debug/upstream"} {
		response := httptest.NewRecorder()
		h.ServeHTTP(response, httptest.NewRequest(http.MethodPost, path, nil))
		if response.Code != http.StatusMethodNotAllowed {
			t.Errorf("POST %s status = %d, want %d", path, response.Code, http.StatusMethodNotAllowed)
		}
	}
}
