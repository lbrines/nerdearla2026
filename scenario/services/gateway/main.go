package main

import (
	"errors"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync/atomic"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const defaultBackendURLs = "http://checkout-1:8080,http://checkout-2:8080,http://checkout-3:8080"

var errInvalidGatewayConfiguration = errors.New("invalid gateway configuration")

type gateway struct {
	backends []string
	client   *http.Client
	next     atomic.Uint64
	metrics  *gatewayMetrics
}

func main() {
	backends, err := backendURLsFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	_ = http.ListenAndServe(":8080", newHandler(backends, gatewayClient()))
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
	return (&gateway{backends: backends, client: client, metrics: newGatewayMetrics()}).handler()
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

	status := http.StatusBadGateway
	defer func() { g.metrics.record(status) }()
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
		http.Error(w, "bad gateway", status)
		return
	}
	status = response.StatusCode
	w.WriteHeader(status)
}
