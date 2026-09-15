package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPricingMetricsAreInitializedAndMeasurePriceProcessing(t *testing.T) {
	server := newPricingServer(defaultPriceDelay)
	h := server.handler()
	metrics := pricingMetricsText(t, h)

	for _, line := range []string{
		`pricing_requests_total{outcome="success"} 0`,
		`pricing_requests_total{outcome="error"} 0`,
	} {
		pricingExpectMetric(t, metrics, line)
	}
	for _, bucket := range []string{"0.01", "0.025", "0.05", "0.075", "0.1", "0.25", "0.5"} {
		pricingExpectMetric(t, metrics, fmt.Sprintf(`pricing_request_duration_seconds_bucket{le="%s"} 0`, bucket))
	}

	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/price", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("price status = %d, want %d", response.Code, http.StatusOK)
	}

	metrics = pricingMetricsText(t, h)
	for _, line := range []string{
		`pricing_requests_total{outcome="success"} 1`,
		`pricing_requests_total{outcome="error"} 0`,
		`pricing_request_duration_seconds_count 1`,
		`pricing_request_duration_seconds_bucket{le="0.01"} 0`,
		`pricing_request_duration_seconds_bucket{le="0.5"} 1`,
	} {
		pricingExpectMetric(t, metrics, line)
	}
}

func TestPricingMetricsExcludeLocalAndRejectedRequests(t *testing.T) {
	h := newPricingServer(time.Millisecond).handler()
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/healthz", nil),
		httptest.NewRequest(http.MethodGet, "/metrics", nil),
		httptest.NewRequest(http.MethodPost, "/price", nil),
	} {
		h.ServeHTTP(httptest.NewRecorder(), request)
	}

	metrics := pricingMetricsText(t, h)
	pricingExpectMetric(t, metrics, `pricing_requests_total{outcome="success"} 0`)
	pricingExpectMetric(t, metrics, `pricing_request_duration_seconds_count 0`)
}

func TestPricingMetricsUseIndependentRegistries(t *testing.T) {
	first := newPricingServer(time.Millisecond)
	second := newPricingServer(time.Millisecond)
	first.handler().ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/price", nil))

	pricingExpectMetric(t, pricingMetricsText(t, first.handler()), `pricing_requests_total{outcome="success"} 1`)
	pricingExpectMetric(t, pricingMetricsText(t, second.handler()), `pricing_requests_total{outcome="success"} 0`)
}

func pricingMetricsText(t *testing.T, h http.Handler) string {
	t.Helper()
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("metrics status = %d, want %d", response.Code, http.StatusOK)
	}
	return response.Body.String()
}

func pricingExpectMetric(t *testing.T, metrics, line string) {
	t.Helper()
	if !strings.Contains(metrics, line) {
		t.Errorf("metrics do not contain %q:\n%s", line, metrics)
	}
}
