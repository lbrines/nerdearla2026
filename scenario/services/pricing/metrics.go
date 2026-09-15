package main

import "github.com/prometheus/client_golang/prometheus"

var pricingDurationBuckets = []float64{0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5}

type pricingMetrics struct {
	registry        *prometheus.Registry
	requests        *prometheus.CounterVec
	requestDuration prometheus.Histogram
}

func newPricingMetrics() *pricingMetrics {
	metrics := &pricingMetrics{
		registry: prometheus.NewRegistry(),
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "pricing_requests_total",
			Help: "Completed pricing requests.",
		}, []string{"outcome"}),
		requestDuration: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name:    "pricing_request_duration_seconds",
			Help:    "Pricing request duration in seconds.",
			Buckets: pricingDurationBuckets,
		}),
	}
	metrics.registry.MustRegister(metrics.requests, metrics.requestDuration)
	for _, outcome := range []string{"success", "error"} {
		metrics.requests.WithLabelValues(outcome).Add(0)
	}

	return metrics
}
