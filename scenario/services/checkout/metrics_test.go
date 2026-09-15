package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestCheckoutMetricsAreInitialized(t *testing.T) {
	server := newCheckoutServer("checkout-1", "http://invalid.example", http.DefaultClient, time.Second)
	metrics := metricsText(t, server.handler())

	for _, line := range []string{
		`checkout_requests_total{checkout_instance="checkout-1",outcome="success"} 0`,
		`checkout_requests_total{checkout_instance="checkout-1",outcome="error"} 0`,
		`checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="success"} 0`,
		`checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="timeout"} 0`,
	} {
		expectMetric(t, metrics, line)
	}

	for _, name := range []string{"checkout_request_duration_seconds", "checkout_pricing_request_duration_seconds"} {
		for _, bucket := range []string{"0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1"} {
			expectMetric(t, metrics, fmt.Sprintf(`%s_bucket{checkout_instance="checkout-1",le="%s"} 0`, name, bucket))
		}
	}
}

func TestCheckoutMetricsRecordCheckoutAndPricingOutcomes(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Request-ID") == "timeout" {
			<-r.Context().Done()
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	server := newCheckoutServer("checkout-1", upstream.URL, upstream.Client(), 5*time.Millisecond)
	h := server.handler()
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/checkout", nil),
		httptest.NewRequest(http.MethodGet, "/debug/upstream", nil),
		withRequestID(httptest.NewRequest(http.MethodGet, "/checkout", nil), "timeout"),
	} {
		response := httptest.NewRecorder()
		h.ServeHTTP(response, request)
	}

	metrics := metricsText(t, h)
	for _, line := range []string{
		`checkout_requests_total{checkout_instance="checkout-1",outcome="success"} 1`,
		`checkout_requests_total{checkout_instance="checkout-1",outcome="error"} 1`,
		`checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="success"} 2`,
		`checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="timeout"} 1`,
		`checkout_request_duration_seconds_count{checkout_instance="checkout-1"} 2`,
		`checkout_pricing_request_duration_seconds_count{checkout_instance="checkout-1"} 3`,
	} {
		expectMetric(t, metrics, line)
	}
}

func TestCheckoutMetricsExcludeLocalAndRejectedRequests(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	server := newCheckoutServer("checkout-1", upstream.URL, upstream.Client(), time.Second)
	h := server.handler()
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/healthz", nil),
		httptest.NewRequest(http.MethodGet, "/metrics", nil),
		httptest.NewRequest(http.MethodPost, "/checkout", nil),
		httptest.NewRequest(http.MethodPost, "/debug/upstream", nil),
	} {
		h.ServeHTTP(httptest.NewRecorder(), request)
	}

	metrics := metricsText(t, h)
	expectMetric(t, metrics, `checkout_requests_total{checkout_instance="checkout-1",outcome="success"} 0`)
	expectMetric(t, metrics, `checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="success"} 0`)

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/debug/upstream", nil))
	metrics = metricsText(t, h)
	expectMetric(t, metrics, `checkout_requests_total{checkout_instance="checkout-1",outcome="success"} 0`)
	expectMetric(t, metrics, `checkout_pricing_requests_total{checkout_instance="checkout-1",outcome="success"} 1`)
}

func TestCheckoutMetricsUseIndependentRegistries(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	first := newCheckoutServer("checkout-1", upstream.URL, upstream.Client(), time.Second)
	second := newCheckoutServer("checkout-2", upstream.URL, upstream.Client(), time.Second)
	first.handler().ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/checkout", nil))

	expectMetric(t, metricsText(t, first.handler()), `checkout_requests_total{checkout_instance="checkout-1",outcome="success"} 1`)
	expectMetric(t, metricsText(t, second.handler()), `checkout_requests_total{checkout_instance="checkout-2",outcome="success"} 0`)
}

func metricsText(t *testing.T, h http.Handler) string {
	t.Helper()
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("metrics status = %d, want %d", response.Code, http.StatusOK)
	}
	return response.Body.String()
}

func expectMetric(t *testing.T, metrics, line string) {
	t.Helper()
	if !strings.Contains(metrics, line) {
		t.Errorf("metrics do not contain %q:\n%s", line, metrics)
	}
}

func withRequestID(request *http.Request, requestID string) *http.Request {
	request.Header.Set("X-Request-ID", requestID)
	return request
}
