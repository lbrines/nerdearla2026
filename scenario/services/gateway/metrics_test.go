package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGatewayMetricsAreInitialized(t *testing.T) {
	metrics := gatewayMetricsText(t, newHandler([]string{"http://backend"}, http.DefaultClient))
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="success"} 0`)
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="error"} 0`)
}

func TestGatewayMetricsClassifyCompletedCheckoutResponses(t *testing.T) {
	statuses := []int{http.StatusOK, http.StatusGatewayTimeout, http.StatusTemporaryRedirect}
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(statuses[0])
		statuses = statuses[1:]
	}))
	defer backend.Close()

	h := newHandler([]string{backend.URL}, gatewayClient())
	for range 3 {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/checkout", nil))
	}
	metrics := gatewayMetricsText(t, h)
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="success"} 1`)
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="error"} 2`)

	failed := newHandler([]string{"http://backend"}, &http.Client{Transport: roundTripper(func(*http.Request) (*http.Response, error) {
		return nil, assertError("unavailable")
	})})
	failed.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/checkout", nil))
	gatewayExpectMetric(t, gatewayMetricsText(t, failed), `gateway_requests_total{outcome="error"} 1`)
}

func TestGatewayMetricsExcludeLocalAndRejectedRequests(t *testing.T) {
	h := newHandler([]string{"http://backend"}, http.DefaultClient)
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/healthz", nil),
		httptest.NewRequest(http.MethodGet, "/metrics", nil),
		httptest.NewRequest(http.MethodPost, "/checkout", nil),
	} {
		h.ServeHTTP(httptest.NewRecorder(), request)
	}

	metrics := gatewayMetricsText(t, h)
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="success"} 0`)
	gatewayExpectMetric(t, metrics, `gateway_requests_total{outcome="error"} 0`)
}

func TestGatewayMetricsUseIndependentRegistries(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	first := newHandler([]string{backend.URL}, backend.Client())
	second := newHandler([]string{backend.URL}, backend.Client())
	first.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/checkout", nil))

	gatewayExpectMetric(t, gatewayMetricsText(t, first), `gateway_requests_total{outcome="success"} 1`)
	gatewayExpectMetric(t, gatewayMetricsText(t, second), `gateway_requests_total{outcome="success"} 0`)
}

func gatewayMetricsText(t *testing.T, h http.Handler) string {
	t.Helper()
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("metrics status = %d, want %d", response.Code, http.StatusOK)
	}
	return response.Body.String()
}

func gatewayExpectMetric(t *testing.T, metrics, line string) {
	t.Helper()
	if !strings.Contains(metrics, line) {
		t.Errorf("metrics do not contain %q:\n%s", line, metrics)
	}
}
