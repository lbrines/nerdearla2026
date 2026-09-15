package main

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
)

type gatewayMetrics struct {
	registry *prometheus.Registry
	requests *prometheus.CounterVec
}

func newGatewayMetrics() *gatewayMetrics {
	metrics := &gatewayMetrics{
		registry: prometheus.NewRegistry(),
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "gateway_requests_total",
			Help: "Completed gateway checkout requests.",
		}, []string{"outcome"}),
	}
	metrics.registry.MustRegister(metrics.requests)
	for _, outcome := range []string{"success", "error"} {
		metrics.requests.WithLabelValues(outcome).Add(0)
	}

	return metrics
}

func (m *gatewayMetrics) record(status int) {
	outcome := "error"
	if status >= http.StatusOK && status < http.StatusMultipleChoices {
		outcome = "success"
	}
	m.requests.WithLabelValues(outcome).Inc()
}
