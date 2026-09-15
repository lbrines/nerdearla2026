package main

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const defaultPriceDelay = 40 * time.Millisecond

type pricingServer struct {
	priceDelay time.Duration
	metrics    *pricingMetrics
}

func main() {
	_ = http.ListenAndServe(":8080", newHandler(defaultPriceDelay))
}

func newHandler(priceDelay time.Duration) http.Handler {
	return newPricingServer(priceDelay).handler()
}

func newPricingServer(priceDelay time.Duration) pricingServer {
	return pricingServer{priceDelay: priceDelay, metrics: newPricingMetrics()}
}

func (s pricingServer) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.health)
	mux.HandleFunc("/price", s.price)
	mux.Handle("/metrics", promhttp.HandlerFor(s.metrics.registry, promhttp.HandlerOpts{}))
	return mux
}

func (s pricingServer) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s pricingServer) price(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	started := time.Now()
	time.Sleep(s.priceDelay)
	s.metrics.requests.WithLabelValues("success").Inc()
	s.metrics.requestDuration.Observe(time.Since(started).Seconds())
	w.WriteHeader(http.StatusOK)
}
