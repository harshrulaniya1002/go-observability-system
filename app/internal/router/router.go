// Package router wires together the HTTP handlers, middleware, and metrics
// endpoint into a single http.Handler for the application.
package router

import (
	"net/http"

	"github.com/go-chi/chi"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"dockerGo-monitoring/internal/handlers"
	"dockerGo-monitoring/internal/httpmiddleware"
	"dockerGo-monitoring/internal/logger"
	"dockerGo-monitoring/internal/metrics"
)

// New builds the application's chi router, wiring request logging/metrics
// middleware and all HTTP endpoints.
func New(log *logger.Logger, m *metrics.Metrics) http.Handler {
	r := chi.NewRouter()
	r.Use(httpmiddleware.Logging(log, m))

	r.Get("/", handlers.Root)
	r.Get("/health", handlers.Health)
	r.Get("/api", handlers.API)
	r.Get("/frontend", handlers.FrontendBridge)
	r.Get("/backend", handlers.BackendBridge)
	r.Handle("/metrics", promhttp.Handler())

	return r
}
