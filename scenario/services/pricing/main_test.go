package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHandler(t *testing.T) {
	h := newHandler(defaultPriceDelay)

	for _, tt := range []struct {
		name   string
		method string
		path   string
		status int
	}{
		{name: "health is healthy", method: http.MethodGet, path: "/healthz", status: http.StatusOK},
		{name: "price is available", method: http.MethodGet, path: "/price", status: http.StatusOK},
		{name: "price rejects post", method: http.MethodPost, path: "/price", status: http.StatusMethodNotAllowed},
	} {
		t.Run(tt.name, func(t *testing.T) {
			request := httptest.NewRequest(tt.method, tt.path, nil)
			response := httptest.NewRecorder()
			started := time.Now()

			h.ServeHTTP(response, request)

			if response.Code != tt.status {
				t.Fatalf("status = %d, want %d", response.Code, tt.status)
			}
			if tt.path == "/price" && tt.method == http.MethodGet && time.Since(started) < 40*time.Millisecond {
				t.Fatal("price returned before its configured processing delay")
			}
		})
	}
}
