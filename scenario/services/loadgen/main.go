package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

const (
	defaultTargetURL   = "http://checkout-gateway:8080/checkout"
	defaultInterval    = time.Second / 6
	defaultConcurrency = 4
)

type config struct {
	targetURL   string
	interval    time.Duration
	concurrency int
}

type generator struct {
	targetURL   string
	client      *http.Client
	concurrency int
	next        atomic.Uint64
}

func main() {
	cfg, err := configFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ticker := time.NewTicker(cfg.interval)
	defer ticker.Stop()
	loadgen := generator{targetURL: cfg.targetURL, client: http.DefaultClient, concurrency: cfg.concurrency}
	loadgen.run(ctx, ticker.C)
}

func configFromEnv() (config, error) {
	cfg := config{targetURL: os.Getenv("LOADGEN_TARGET_URL"), interval: defaultInterval, concurrency: defaultConcurrency}
	if cfg.targetURL == "" {
		cfg.targetURL = defaultTargetURL
	}
	target, err := url.ParseRequestURI(cfg.targetURL)
	if err != nil || target.Scheme == "" || target.Host == "" {
		return config{}, fmt.Errorf("invalid LOADGEN_TARGET_URL")
	}
	if value := os.Getenv("LOADGEN_INTERVAL"); value != "" {
		if cfg.interval, err = time.ParseDuration(value); err != nil || cfg.interval <= 0 {
			return config{}, fmt.Errorf("invalid LOADGEN_INTERVAL")
		}
	}
	if value := os.Getenv("LOADGEN_CONCURRENCY"); value != "" {
		if cfg.concurrency, err = strconv.Atoi(value); err != nil || cfg.concurrency <= 0 {
			return config{}, fmt.Errorf("invalid LOADGEN_CONCURRENCY")
		}
	}
	return cfg, nil
}

func (g *generator) run(ctx context.Context, ticks <-chan time.Time) {
	semaphore := make(chan struct{}, g.concurrency)
	var workers sync.WaitGroup
	for {
		select {
		case <-ctx.Done():
			workers.Wait()
			return
		case _, ok := <-ticks:
			if !ok {
				workers.Wait()
				return
			}
			select {
			case semaphore <- struct{}{}:
				id := g.next.Add(1)
				workers.Add(1)
				go g.request(ctx, id, semaphore, &workers)
			default:
			}
		}
	}
}

func (g *generator) request(ctx context.Context, id uint64, semaphore chan struct{}, workers *sync.WaitGroup) {
	defer workers.Done()
	defer func() { <-semaphore }()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, g.targetURL, nil)
	if err != nil {
		return
	}
	request.Header.Set("X-Request-ID", fmt.Sprintf("loadgen-%d", id))
	response, _ := g.client.Do(request)
	if response != nil {
		response.Body.Close()
	}
}
