package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/lbrines/nerderla2026/scenario/services/logging"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	defaultBackendURLs = "http://checkout-1:8080,http://checkout-2:8080,http://checkout-3:8080"
	gatewayLogPath     = "/logs/gateway.jsonl"
)

var errInvalidGatewayConfiguration = errors.New("invalid gateway configuration")

type gateway struct {
	backends []string
	client   *http.Client
	next     atomic.Uint64
	metrics  *gatewayMetrics
	logger   *slog.Logger
}

func main() {
	backends, err := backendURLsFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	logger, closeLog, err := logging.New(gatewayLogPath, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "gateway: cannot initialize logging")
		return
	}
	defer closeLog()

	_ = http.ListenAndServe(":8080", newGatewayWithLogger(backends, gatewayClient(), logger).handler())
}

func backendURLsFromEnv() ([]string, error) {
	value := os.Getenv("CHECKOUT_BACKEND_URLS")
	if value == "" {
		value = defaultBackendURLs
	}
	backends := strings.Split(value, ",")
	if len(backends) != 3 {
		return nil, errInvalidGatewayConfiguration
	}
	for _, backend := range backends {
		parsed, err := url.ParseRequestURI(backend)
		if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
			return nil, errInvalidGatewayConfiguration
		}
	}
	return backends, nil
}

func gatewayClient() *http.Client {
	return &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
}

func newHandler(backends []string, client *http.Client) http.Handler {
	return newGatewayWithLogger(backends, client, slog.New(slog.NewJSONHandler(io.Discard, nil))).handler()
}

func newGatewayWithLogger(backends []string, client *http.Client, logger *slog.Logger) *gateway {
	return &gateway{backends: backends, client: client, metrics: newGatewayMetrics(), logger: logger}
}

func (g *gateway) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", g.health)
	mux.HandleFunc("/checkout", g.checkout)
	mux.Handle("/metrics", promhttp.HandlerFor(g.metrics.registry, promhttp.HandlerOpts{}))
	return mux
}

func (g *gateway) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (g *gateway) checkout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	started := time.Now()
	status := http.StatusBadGateway
	transportError := false
	defer func() {
		g.metrics.record(status)
		outcome := "success"
		level := slog.LevelInfo
		if status < http.StatusOK || status >= http.StatusMultipleChoices {
			outcome = "error"
			level = slog.LevelError
		}
		attributes := []slog.Attr{
			slog.String("service", "gateway"),
			slog.String("request_id", r.Header.Get("X-Request-ID")),
			slog.String("event", "checkout_request"),
			slog.Int64("duration_ms", time.Since(started).Milliseconds()),
			slog.Int("status", status),
			slog.String("outcome", outcome),
		}
		if transportError {
			attributes = append(attributes, slog.String("error", "gateway transport error"))
		}
		g.logger.LogAttrs(r.Context(), level, "", attributes...)
	}()

	backend := g.backends[(g.next.Add(1)-1)%uint64(len(g.backends))]
	request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, strings.TrimRight(backend, "/")+"/checkout", nil)
	if err != nil {
		http.Error(w, "bad gateway", status)
		return
	}
	request.Header.Set("X-Request-ID", r.Header.Get("X-Request-ID"))
	response, err := g.client.Do(request)
	if response != nil {
		response.Body.Close()
	}
	if err != nil {
		transportError = true
		http.Error(w, "bad gateway", status)
		return
	}
	status = response.StatusCode
	w.WriteHeader(status)
}
