package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/lbrines/nerderla2026/scenario/services/logging"
)

const (
	defaultTargetURL   = "http://checkout-gateway:8080/checkout"
	defaultInterval    = time.Second / 6
	defaultConcurrency = 4
	loadgenLogPath     = "/logs/loadgen.jsonl"
	bootPrefixBytes    = 4
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
	bootPrefix  string
	logger      *slog.Logger
	next        atomic.Uint64
}

func main() {
	cfg, err := configFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	logger, closeLog, err := logging.New(loadgenLogPath, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "loadgen: cannot initialize logging")
		return
	}
	defer closeLog()
	loadgen, err := newGenerator(cfg.targetURL, http.DefaultClient, cfg.concurrency, logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, "loadgen: cannot generate boot prefix")
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ticker := time.NewTicker(cfg.interval)
	defer ticker.Stop()
	loadgen.run(ctx, ticker.C)
}

func newGenerator(targetURL string, client *http.Client, concurrency int, logger *slog.Logger) (*generator, error) {
	bytes := make([]byte, bootPrefixBytes)
	if _, err := rand.Read(bytes); err != nil {
		return nil, err
	}
	return newGeneratorWithPrefix(targetURL, client, concurrency, hex.EncodeToString(bytes), logger), nil
}

func newGeneratorWithPrefix(targetURL string, client *http.Client, concurrency int, bootPrefix string, logger *slog.Logger) *generator {
	return &generator{targetURL: targetURL, client: client, concurrency: concurrency, bootPrefix: bootPrefix, logger: logger}
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

	started := time.Now()
	requestID := fmt.Sprintf("loadgen-%s-%d", g.bootPrefix, id)
	status := 0
	transportError := false
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, g.targetURL, nil)
	if err == nil {
		request.Header.Set("X-Request-ID", requestID)
		response, err := g.client.Do(request)
		if response != nil {
			status = response.StatusCode
			response.Body.Close()
		}
		transportError = err != nil
	} else {
		transportError = true
	}

	outcome := "success"
	level := slog.LevelInfo
	if status < http.StatusOK || status >= http.StatusMultipleChoices {
		outcome = "error"
		level = slog.LevelError
	}
	attributes := []slog.Attr{
		slog.String("service", "loadgen"),
		slog.String("request_id", requestID),
		slog.String("event", "checkout_request"),
		slog.Int64("duration_ms", time.Since(started).Milliseconds()),
		slog.Int("status", status),
		slog.String("outcome", outcome),
	}
	if transportError {
		attributes = append(attributes, slog.String("error", "loadgen transport error"))
	}
	g.logger.LogAttrs(ctx, level, "", attributes...)
}
