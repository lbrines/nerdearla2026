package main

import (
	"net/http"
	"time"
)

const defaultPriceDelay = 40 * time.Millisecond

func main() {
	_ = http.ListenAndServe(":8080", newHandler(defaultPriceDelay))
}

func newHandler(priceDelay time.Duration) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/price", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		time.Sleep(priceDelay)
		w.WriteHeader(http.StatusOK)
	})
	return mux
}
