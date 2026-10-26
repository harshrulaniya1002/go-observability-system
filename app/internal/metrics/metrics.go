// Package metrics defines the Prometheus metrics collected for every
// HTTP request handled by the application.
package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Metrics bundles the Prometheus collectors used by the HTTP middleware.
type Metrics struct {
	requestsTotal   *prometheus.CounterVec
	requestDuration *prometheus.HistogramVec
	requestSize     *prometheus.HistogramVec
	responseSize    *prometheus.HistogramVec
}

// New creates and registers the application's Prometheus metrics with the
// default registry. Call it once during application startup.
func New() *Metrics {
	m := &Metrics{
		requestsTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "http_requests_total",
				Help: "Total number of HTTP requests processed",
			},
			[]string{"method", "path", "status"},
		),
		requestDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_request_duration_seconds",
				Help:    "HTTP request duration in seconds",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "path"},
		),
		requestSize: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_request_size_bytes",
				Help:    "HTTP request size in bytes",
				Buckets: []float64{100, 1000, 10000},
			},
			[]string{"method", "path"},
		),
		responseSize: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_response_size_bytes",
				Help:    "HTTP response size in bytes",
				Buckets: []float64{100, 1000, 10000},
			},
			[]string{"method", "path"},
		),
	}

	prometheus.MustRegister(
		m.requestsTotal,
		m.requestDuration,
		m.requestSize,
		m.responseSize,
	)

	return m
}

// Observe records the outcome of a single HTTP request across all collectors.
func (m *Metrics) Observe(method, path, status string, duration time.Duration, requestSize, responseSize int64) {
	m.requestsTotal.WithLabelValues(method, path, status).Inc()
	m.requestDuration.WithLabelValues(method, path).Observe(duration.Seconds())
	m.requestSize.WithLabelValues(method, path).Observe(float64(requestSize))
	m.responseSize.WithLabelValues(method, path).Observe(float64(responseSize))
}
