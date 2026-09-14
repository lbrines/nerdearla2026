package main

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
)

func TestGatewayRoundRobinIsConcurrentAndHealthIsLocal(t *testing.T) {
	var calls [3]atomic.Int64
	backends := make([]string, 3)
	servers := make([]*httptest.Server, 3)
	for i := range servers {
		i := i
		servers[i] = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			calls[i].Add(1)
			w.WriteHeader(http.StatusNoContent)
		}))
		backends[i] = servers[i].URL
		defer servers[i].Close()
	}

	h := newHandler(backends, http.DefaultClient)
	health := httptest.NewRecorder()
	h.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if health.Code != http.StatusOK {
		t.Fatalf("health status = %d, want %d", health.Code, http.StatusOK)
	}
	for _, path := range []string{"/healthz", "/checkout"} {
		response := httptest.NewRecorder()
		h.ServeHTTP(response, httptest.NewRequest(http.MethodPost, path, nil))
		if response.Code != http.StatusMethodNotAllowed {
			t.Errorf("POST %s = %d, want %d", path, response.Code, http.StatusMethodNotAllowed)
		}
	}
	probe := httptest.NewRecorder()
	h.ServeHTTP(probe, httptest.NewRequest(http.MethodGet, "/checkout", nil))
	if calls[0].Load() != 1 {
		t.Fatal("health check changed the first backend selection")
	}

	const requests = 90
	var group sync.WaitGroup
	for range requests {
		group.Add(1)
		go func() {
			defer group.Done()
			response := httptest.NewRecorder()
			h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/checkout", nil))
			if response.Code != http.StatusNoContent {
				t.Errorf("checkout status = %d, want %d", response.Code, http.StatusNoContent)
			}
		}()
	}
	group.Wait()
	for i := range calls {
		want := int64(requests / len(calls))
		if i == 0 {
			want++
		}
		if got := calls[i].Load(); got != want {
			t.Errorf("backend %d calls = %d, want %d", i, got, want)
		}
	}
}

func TestGatewayPassesStatusAndRequestIDWithoutBackendIdentity(t *testing.T) {
	var requestID string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID = r.Header.Get("X-Request-ID")
		w.Header().Set("X-Backend", "hidden")
		w.WriteHeader(http.StatusTeapot)
	}))
	defer backend.Close()

	h := newHandler([]string{backend.URL}, backend.Client())
	request := httptest.NewRequest(http.MethodGet, "/checkout", nil)
	request.Header.Set("X-Request-ID", "request-123")
	response := httptest.NewRecorder()
	h.ServeHTTP(response, request)

	if response.Code != http.StatusTeapot {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusTeapot)
	}
	if requestID != "request-123" {
		t.Errorf("request ID = %q, want %q", requestID, "request-123")
	}
	if response.Header().Get("X-Backend") != "" || response.Body.Len() != 0 {
		t.Fatal("gateway response exposed backend identity")
	}
}

func TestGatewayMakesOneAttemptAndReturnsGenericBadGateway(t *testing.T) {
	var calls atomic.Int64
	client := &http.Client{Transport: roundTripper(func(*http.Request) (*http.Response, error) {
		calls.Add(1)
		return nil, assertError("unavailable")
	})}
	h := newHandler([]string{"http://physical-backend"}, client)
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/checkout", nil))

	if response.Code != http.StatusBadGateway || calls.Load() != 1 {
		t.Fatalf("status = %d, calls = %d; want 502 and 1", response.Code, calls.Load())
	}
	if response.Body.String() != "bad gateway\n" {
		t.Fatal("bad gateway response was not generic")
	}
}

type roundTripper func(*http.Request) (*http.Response, error)

func (f roundTripper) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

type assertError string

func (e assertError) Error() string { return string(e) }

func TestGatewayReturnsRedirectWithoutFollowingIt(t *testing.T) {
	var redirectedTo atomic.Int64
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		redirectedTo.Add(1)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer target.Close()
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer backend.Close()

	response := httptest.NewRecorder()
	newHandler([]string{backend.URL}, gatewayClient()).ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/checkout", nil))
	if response.Code != http.StatusTemporaryRedirect || redirectedTo.Load() != 0 {
		t.Fatalf("status = %d, redirected calls = %d; want 307 and 0", response.Code, redirectedTo.Load())
	}
}

func TestGatewayRejectsInvalidBackendConfiguration(t *testing.T) {
	for _, test := range []struct {
		name  string
		value string
	}{
		{"too few", "http://one,http://two"},
		{"too many", "http://one,http://two,http://three,http://four"},
		{"empty", "http://one,,http://three"},
		{"relative", "http://one,/checkout,http://three"},
		{"unsupported scheme", "http://one,ftp://two,http://three"},
		{"missing host", "http://one,http:///checkout,http://three"},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("CHECKOUT_BACKEND_URLS", test.value)
			if _, err := backendURLsFromEnv(); err == nil {
				t.Fatal("backendURLsFromEnv succeeded for invalid configuration")
			}
		})
	}
}
