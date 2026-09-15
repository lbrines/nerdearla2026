package logging

import (
	"io"
	"log/slog"
	"os"
)

// New creates a JSONL logger that writes each record to stdout and a file.
func New(path string, stdout io.Writer) (*slog.Logger, func() error, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, nil, err
	}

	handler := slog.NewJSONHandler(io.MultiWriter(stdout, file), &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
			if attr.Key == slog.TimeKey {
				attr.Key = "timestamp"
			}
			return attr
		},
	})
	return slog.New(handler), file.Close, nil
}
