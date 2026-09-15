package main

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/lbrines/nerderla2026/scenario/services/logging"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	defaultPriceDelay = 40 * time.Millisecond
	pricingLogPath    = "/logs/pricing.jsonl"
)

type pricingServer struct {
	priceDelay time.Duration
	metrics    *pricingMetrics
	logger     *slog.Logger
}

func main() {
	logger, closeLog, err := logging.New(pricingLogPath, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "pricing: cannot initialize logging")
		return
	}
	defer closeLog()

	_ = http.ListenAndServe(":8080", newPricingServerWithLogger(defaultPriceDelay, logger).handler())
}

func newHandler(priceDelay time.Duration) http.Handler {
	return newPricingServer(priceDelay).handler()
}

func newPricingServer(priceDelay time.Duration) pricingServer {
	return newPricingServerWithLogger(priceDelay, slog.New(slog.NewJSONHandler(io.Discard, nil)))
}

func newPricingServerWithLogger(priceDelay time.Duration, logger *slog.Logger) pricingServer {
	return pricingServer{priceDelay: priceDelay, metrics: newPricingMetrics(), logger: logger}
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
	elapsed := time.Since(started)
	s.metrics.requests.WithLabelValues("success").Inc()
	s.metrics.requestDuration.Observe(elapsed.Seconds())
	s.logger.LogAttrs(r.Context(), slog.LevelInfo, "",
		slog.String("service", "pricing"),
		slog.String("request_id", r.Header.Get("X-Request-ID")),
		slog.String("event", "price_request"),
		slog.Int64("duration_ms", elapsed.Milliseconds()),
		slog.Int("status", http.StatusOK),
	)
	w.WriteHeader(http.StatusOK)
}
