// Package logger provides structured JSON logging that is written
// simultaneously to stdout (for `docker logs`) and to a persistent,
// daily-rotated log file (for the mounted app-logs volume).
package logger

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Entry is a single structured, JSON-formatted log line.
type Entry struct {
	Timestamp  time.Time         `json:"timestamp"`
	Level      string            `json:"level"`
	Service    string            `json:"service"`
	Message    string            `json:"message"`
	RequestID  string            `json:"request_id,omitempty"`
	Method     string            `json:"method,omitempty"`
	Path       string            `json:"path,omitempty"`
	StatusCode int               `json:"status_code,omitempty"`
	Duration   float64           `json:"duration_ms,omitempty"`
	Hostname   string            `json:"hostname,omitempty"`
	RemoteAddr string            `json:"remote_addr,omitempty"`
	Metadata   map[string]string `json:"metadata,omitempty"`
}

// Logger writes structured log entries to stdout and a persistent file.
// It is safe for concurrent use.
type Logger struct {
	mu       sync.Mutex
	file     *os.File
	hostname string
}

const serviceName = "go-app"

// New creates a Logger that persists daily log files under logDir
// (e.g. app-2026-10-26.log) in addition to writing to stdout.
func New(logDir string) (*Logger, error) {
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, fmt.Errorf("failed to create log directory: %w", err)
	}

	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "unknown"
	}

	today := time.Now().Format("2006-01-02")
	logFile := filepath.Join(logDir, fmt.Sprintf("app-%s.log", today))

	file, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file: %w", err)
	}

	return &Logger{file: file, hostname: hostname}, nil
}

// Log writes a general structured log entry.
func (l *Logger) Log(level, message string, metadata map[string]string) {
	l.write(Entry{
		Timestamp: time.Now().UTC(),
		Level:     level,
		Service:   serviceName,
		Message:   message,
		Hostname:  l.hostname,
		Metadata:  metadata,
	})
}

// LogRequest writes a structured entry describing a completed HTTP request.
func (l *Logger) LogRequest(r *http.Request, statusCode int, duration time.Duration, requestID string, responseSize int64) {
	l.write(Entry{
		Timestamp:  time.Now().UTC(),
		Level:      "INFO",
		Service:    serviceName,
		Message:    "HTTP Request",
		RequestID:  requestID,
		Method:     r.Method,
		Path:       r.RequestURI,
		StatusCode: statusCode,
		Duration:   duration.Seconds() * 1000,
		Hostname:   l.hostname,
		RemoteAddr: r.RemoteAddr,
	})
}

// write marshals an entry to JSON and sends it to stdout and the log file.
func (l *Logger) write(entry Entry) {
	l.mu.Lock()
	defer l.mu.Unlock()

	jsonData, _ := json.Marshal(entry)
	logLine := string(jsonData) + "\n"

	fmt.Fprint(os.Stdout, logLine)

	if l.file != nil {
		l.file.WriteString(logLine)
		l.file.Sync()
	}
}

// Close flushes and closes the underlying log file.
func (l *Logger) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		return l.file.Close()
	}
	return nil
}
