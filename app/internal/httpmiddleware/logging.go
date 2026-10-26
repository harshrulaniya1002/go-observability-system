// Package httpmiddleware provides HTTP middleware shared across routes,
// such as request logging and metrics collection.
package httpmiddleware

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"dockerGo-monitoring/internal/logger"
	"dockerGo-monitoring/internal/metrics"
)

// responseWriter wraps http.ResponseWriter to capture the status code and
// number of bytes written, which are not otherwise exposed by net/http.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	written    int64
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	n, err := rw.ResponseWriter.Write(b)
	rw.written += int64(n)
	return n, err
}

// generateRequestID builds a unique, low-cost ID for correlating a request
// across logs and tracing headers.
func generateRequestID() string {
	return fmt.Sprintf("%d-%d", time.Now().UnixNano(), os.Getpid())
}

// Logging returns middleware that assigns a request ID, logs the completed
// request via log, and records its outcome in m.
func Logging(log *logger.Logger, m *metrics.Metrics) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			requestID := generateRequestID()
			r.Header.Set("X-Request-ID", requestID)

			wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

			next.ServeHTTP(wrapped, r)

			duration := time.Since(start)
			status := fmt.Sprintf("%d", wrapped.statusCode)

			log.LogRequest(r, wrapped.statusCode, duration, requestID, wrapped.written)
			m.Observe(r.Method, r.URL.Path, status, duration, r.ContentLength, wrapped.written)
		})
	}
}
