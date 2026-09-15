package main

import (
	"github.com/prometheus/client_golang/prometheus"
)

var checkoutDurationBuckets = []float64{0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1}

type checkoutMetrics struct {
	registry               *prometheus.Registry
	requests               *prometheus.CounterVec
	pricingRequests        *prometheus.CounterVec
	requestDuration        *prometheus.HistogramVec
	pricingRequestDuration *prometheus.HistogramVec
}

func newCheckoutMetrics(instance string) *checkoutMetrics {
	metrics := &checkoutMetrics{
		registry: prometheus.NewRegistry(),
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "checkout_requests_total",
			Help: "Completed checkout requests.",
		}, []string{"checkout_instance", "outcome"}),
		pricingRequests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "checkout_pricing_requests_total",
			Help: "Pricing calls made by checkout.",
		}, []string{"checkout_instance", "outcome"}),
		requestDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "checkout_request_duration_seconds",
			Help:    "Checkout request duration in seconds.",
			Buckets: checkoutDurationBuckets,
		}, []string{"checkout_instance"}),
		pricingRequestDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "checkout_pricing_request_duration_seconds",
			Help:    "Checkout pricing call duration in seconds.",
			Buckets: checkoutDurationBuckets,
		}, []string{"checkout_instance"}),
	}
	metrics.registry.MustRegister(metrics.requests, metrics.pricingRequests, metrics.requestDuration, metrics.pricingRequestDuration)

	for _, outcome := range []string{"success", "error"} {
		metrics.requests.WithLabelValues(instance, outcome).Add(0)
	}
	for _, outcome := range []string{"success", "timeout"} {
		metrics.pricingRequests.WithLabelValues(instance, outcome).Add(0)
	}
	metrics.requestDuration.WithLabelValues(instance)
	metrics.pricingRequestDuration.WithLabelValues(instance)

	return metrics
}
