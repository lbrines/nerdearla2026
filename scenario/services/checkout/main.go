package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/lbrines/nerderla2026/scenario/services/logging"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	defaultPricingTimeout = 500 * time.Millisecond
	defaultUpstreamURL    = "http://pricing-api:8080"
	logDirectory          = "/logs"
)

// CHECKOUT_INSTANCE identifies a replica; PRICING_UPSTREAM_URL selects its pricing path.
type config struct {
	instance    string
	upstreamURL string
}

type checkoutServer struct {
	instance    string
	upstreamURL string
	client      *http.Client
	timeout     time.Duration
	metrics     *checkoutMetrics
	logger      *slog.Logger
}

type upstreamResult struct {
	outcome   string
	elapsedMS int64
}

func main() {
	cfg := configFromEnv()
	path, err := checkoutLogPath(cfg.instance)
	if err != nil {
		fmt.Fprintln(os.Stderr, "checkout: logging configuration is invalid")
		return
	}
	logger, closeLog, err := logging.New(path, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "checkout: cannot initialize logging")
		return
	}
	defer closeLog()

	server := newCheckoutServerWithLogger(cfg.instance, cfg.upstreamURL, http.DefaultClient, defaultPricingTimeout, logger)
	_ = http.ListenAndServe(":8080", server.handler())
}

func configFromEnv() config {
	upstreamURL := os.Getenv("PRICING_UPSTREAM_URL")
	if upstreamURL == "" {
		upstreamURL = defaultUpstreamURL
	}
	return config{instance: os.Getenv("CHECKOUT_INSTANCE"), upstreamURL: upstreamURL}
}

func checkoutLogPath(instance string) (string, error) {
	switch instance {
	case "checkout-1", "checkout-2", "checkout-3":
		return filepath.Join(logDirectory, instance+".jsonl"), nil
	default:
		return "", errors.New("invalid checkout instance")
	}
}

func newCheckoutServer(instance, upstreamURL string, client *http.Client, timeout time.Duration) checkoutServer {
	return newCheckoutServerWithLogger(instance, upstreamURL, client, timeout, slog.New(slog.NewJSONHandler(io.Discard, nil)))
}

func newCheckoutServerWithLogger(instance, upstreamURL string, client *http.Client, timeout time.Duration, logger *slog.Logger) checkoutServer {
	return checkoutServer{
		instance:    instance,
		upstreamURL: upstreamURL,
		client:      client,
		timeout:     timeout,
		metrics:     newCheckoutMetrics(instance),
		logger:      logger,
	}
}

func newHandler(upstreamURL string, client *http.Client, timeout time.Duration) http.Handler {
	return newCheckoutServer("", upstreamURL, client, timeout).handler()
}

func (s checkoutServer) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.health)
	mux.HandleFunc("/checkout", s.checkout)
	mux.HandleFunc("/debug/upstream", s.debugUpstream)
	mux.Handle("/metrics", promhttp.HandlerFor(s.metrics.registry, promhttp.HandlerOpts{}))
	return mux
}

func (s checkoutServer) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s checkoutServer) checkout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	started := time.Now()
	result := s.callPricing(r.Context(), r.Header.Get("X-Request-ID"))
	outcome := "success"
	if result.outcome == "timeout" {
		outcome = "error"
	}
	s.metrics.requests.WithLabelValues(s.instance, outcome).Inc()
	s.metrics.requestDuration.WithLabelValues(s.instance).Observe(time.Since(started).Seconds())

	if result.outcome == "timeout" {
		http.Error(w, "gateway timeout", http.StatusGatewayTimeout)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s checkoutServer) debugUpstream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	result := s.callPricing(r.Context(), r.Header.Get("X-Request-ID"))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(struct {
		LogicalUpstream string `json:"logical_upstream"`
		Outcome         string `json:"outcome"`
		ElapsedMS       int64  `json:"elapsed_ms"`
	}{"pricing-api", result.outcome, result.elapsedMS})
}

func (s checkoutServer) callPricing(parent context.Context, requestID string) upstreamResult {
	started := time.Now()
	ctx, cancel := context.WithTimeout(parent, s.timeout)
	defer cancel()

	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, s.upstreamURL+"/price", nil)
	request.Header.Set("X-Request-ID", requestID)
	response, err := s.client.Do(request)
	if err == nil {
		response.Body.Close()
	}

	outcome := "success"
	if err != nil || response.StatusCode != http.StatusOK {
		outcome = "timeout"
	}
	elapsed := time.Since(started)
	deadlineExceeded := errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded)
	attributes := []slog.Attr{
		slog.String("service", "checkout"),
		slog.String("instance", s.instance),
		slog.String("request_id", requestID),
		slog.String("event", "pricing_call"),
		slog.String("upstream", "pricing-api"),
		slog.Int64("duration_ms", elapsed.Milliseconds()),
		slog.String("outcome", outcome),
	}
	if deadlineExceeded {
		attributes = append(attributes, slog.String("error", "context deadline exceeded"))
		s.logger.LogAttrs(ctx, slog.LevelError, "", attributes...)
	} else {
		s.logger.LogAttrs(ctx, slog.LevelInfo, "", attributes...)
	}
	s.metrics.pricingRequests.WithLabelValues(s.instance, outcome).Inc()
	s.metrics.pricingRequestDuration.WithLabelValues(s.instance).Observe(elapsed.Seconds())
	return upstreamResult{outcome: outcome, elapsedMS: elapsed.Milliseconds()}
}
