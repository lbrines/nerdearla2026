package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestRunSendsOneRequestPerTickWithUniqueIDs(t *testing.T) {
	requestIDs := make(chan string, 3)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestIDs <- r.Header.Get("X-Request-ID")
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	ticks := make(chan time.Time, 3)
	for range 3 {
		ticks <- time.Time{}
	}
	close(ticks)
	(&generator{targetURL: server.URL, client: server.Client(), concurrency: 3}).run(context.Background(), ticks)

	unique := make(map[string]bool)
	for range 3 {
		unique[<-requestIDs] = true
	}
	if len(unique) != 3 {
		t.Fatalf("unique request IDs = %d, want 3", len(unique))
	}
}

func TestRunDispatchesWithoutWaitingAndBoundsConcurrency(t *testing.T) {
	var mutex sync.Mutex
	active, maxActive := 0, 0
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		active++
		if active > maxActive {
			maxActive = active
		}
		mutex.Unlock()
		started <- struct{}{}
		<-release
		mutex.Lock()
		active--
		mutex.Unlock()
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	ticks := make(chan time.Time, 3)
	for range 3 {
		ticks <- time.Time{}
	}
	done := make(chan struct{})
	go func() {
		(&generator{targetURL: server.URL, client: server.Client(), concurrency: 2}).run(ctx, ticks)
		close(done)
	}()
	<-started
	<-started
	close(release)
	cancel()
	<-done

	mutex.Lock()
	defer mutex.Unlock()
	if maxActive != 2 {
		t.Errorf("maximum concurrent requests = %d, want 2", maxActive)
	}
}

func TestConfigRejectsInvalidValues(t *testing.T) {
	for name, value := range map[string]string{
		"interval":    "0s",
		"concurrency": "0",
		"target URL":  "://invalid",
	} {
		t.Run(name, func(t *testing.T) {
			t.Setenv("LOADGEN_INTERVAL", "1s")
			t.Setenv("LOADGEN_CONCURRENCY", "1")
			t.Setenv("LOADGEN_TARGET_URL", "http://gateway/checkout")
			switch name {
			case "interval":
				t.Setenv("LOADGEN_INTERVAL", value)
			case "concurrency":
				t.Setenv("LOADGEN_CONCURRENCY", value)
			case "target URL":
				t.Setenv("LOADGEN_TARGET_URL", value)
			}
			if _, err := configFromEnv(); err == nil {
				t.Fatal("configFromEnv succeeded for invalid configuration")
			}
		})
	}
}

func TestRunClosesResponseBodies(t *testing.T) {
	body := &trackingBody{}
	client := &http.Client{Transport: loadgenRoundTripper(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: http.StatusNoContent, Body: body}, nil
	})}
	ticks := make(chan time.Time, 1)
	ticks <- time.Time{}
	close(ticks)

	(&generator{targetURL: "http://gateway/checkout", client: client, concurrency: 1}).run(context.Background(), ticks)
	if !body.closed {
		t.Fatal("response body was not closed")
	}
}

func TestRunCancelsInFlightRequest(t *testing.T) {
	started := make(chan struct{})
	canceled := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-r.Context().Done()
		close(canceled)
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	ticks := make(chan time.Time, 1)
	ticks <- time.Time{}
	close(ticks)
	done := make(chan struct{})
	go func() {
		(&generator{targetURL: server.URL, client: server.Client(), concurrency: 1}).run(ctx, ticks)
		close(done)
	}()
	<-started
	cancel()
	<-canceled
	<-done
}

type loadgenRoundTripper func(*http.Request) (*http.Response, error)

func (f loadgenRoundTripper) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

type trackingBody struct{ closed bool }

func (*trackingBody) Read([]byte) (int, error) { return 0, io.EOF }

func (b *trackingBody) Close() error {
	b.closed = true
	return nil
}
