package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"time"
)

const (
	defaultPricingTimeout = 500 * time.Millisecond
	defaultUpstreamURL    = "http://pricing-api:8080"
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
}

type upstreamResult struct {
	outcome   string
	elapsedMS int64
}

func main() {
	cfg := configFromEnv()
	server := checkoutServer{
		instance:    cfg.instance,
		upstreamURL: cfg.upstreamURL,
		client:      http.DefaultClient,
		timeout:     defaultPricingTimeout,
	}
	_ = http.ListenAndServe(":8080", server.handler())
}

func configFromEnv() config {
	upstreamURL := os.Getenv("PRICING_UPSTREAM_URL")
	if upstreamURL == "" {
		upstreamURL = defaultUpstreamURL
	}
	return config{instance: os.Getenv("CHECKOUT_INSTANCE"), upstreamURL: upstreamURL}
}

func newHandler(upstreamURL string, client *http.Client, timeout time.Duration) http.Handler {
	return checkoutServer{upstreamURL: upstreamURL, client: client, timeout: timeout}.handler()
}

func (s checkoutServer) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.health)
	mux.HandleFunc("/checkout", s.checkout)
	mux.HandleFunc("/debug/upstream", s.debugUpstream)
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
	result := s.callPricing(r.Context(), r.Header.Get("X-Request-ID"))
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
	return upstreamResult{outcome: outcome, elapsedMS: time.Since(started).Milliseconds()}
}
