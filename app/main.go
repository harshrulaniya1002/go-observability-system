// Command app is the entrypoint for the Docker Observability Go service.
//
// It wires together the pieces defined under internal/ (structured logging,
// Prometheus metrics, HTTP middleware, and route handlers) and starts the
// HTTP server. See internal/ for the actual implementation of each concern.
package main

import (
	"fmt"
	"net/http"
	"os"

	"dockerGo-monitoring/internal/logger"
	"dockerGo-monitoring/internal/metrics"
	"dockerGo-monitoring/internal/router"
)

const (
	logDir     = "/var/log/app"
	listenAddr = ":8080"
)

func main() {
	appLogger, err := logger.New(logDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to initialize logger: %v\n", err)
		os.Exit(1)
	}
	defer appLogger.Close()

	appLogger.Log("INFO", "Application starting", map[string]string{"version": "1.0.0"})

	appMetrics := metrics.New()
	handler := router.New(appLogger, appMetrics)

	srv := &http.Server{
		Addr:    listenAddr,
		Handler: handler,
	}

	appLogger.Log("INFO", "Server starting on port 8080", map[string]string{
		"endpoints": "/, /health, /api, /frontend, /backend, /metrics",
	})
	printStartupBanner()

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		appLogger.Log("ERROR", fmt.Sprintf("Server error: %v", err), map[string]string{})
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}

// printStartupBanner prints a human-friendly summary of available endpoints
// to stdout, useful when watching `docker logs` on startup.
func printStartupBanner() {
	fmt.Println("Server is running on http://localhost:8080")
	fmt.Println("Available endpoints:")
	fmt.Println("  GET /              - Root endpoint")
	fmt.Println("  GET /health        - Health check")
	fmt.Println("  GET /api           - API endpoint")
	fmt.Println("  GET /frontend      - Frontend bridge")
	fmt.Println("  GET /backend       - Backend bridge")
	fmt.Println("  GET /metrics       - Prometheus metrics")
	fmt.Println("Logs are being written to /var/log/app/app-YYYY-MM-DD.log")
}
