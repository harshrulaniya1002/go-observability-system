// Package handlers implements the application's HTTP endpoint handlers.
package handlers

import (
	"encoding/json"
	"net/http"
	"os"
)

const serviceVersion = "1.0.0"

// HealthResponse is returned by the /health endpoint.
type HealthResponse struct {
	Status   string `json:"status"`
	Service  string `json:"service"`
	Version  string `json:"version"`
	Hostname string `json:"hostname"`
}

// BridgeResponse is returned by the /frontend and /backend bridge endpoints
// used to demonstrate network connectivity between Docker networks.
type BridgeResponse struct {
	Service string `json:"service"`
	Message string `json:"message"`
	Path    string `json:"path"`
}

// writeJSON encodes v as JSON, copies the request ID onto the response, and
// writes it to w.
func writeJSON(w http.ResponseWriter, r *http.Request, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Request-ID", r.Header.Get("X-Request-ID"))
	json.NewEncoder(w).Encode(v)
}

// Root handles GET / with a simple plain-text service banner.
func Root(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Request-ID", r.Header.Get("X-Request-ID"))
	w.Write([]byte("Go HTTP Service - Docker Observability"))
}

// Health handles GET /health and reports basic service liveness metadata.
func Health(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	writeJSON(w, r, HealthResponse{
		Status:   "healthy",
		Service:  "go-app",
		Version:  serviceVersion,
		Hostname: hostname,
	})
}

// API handles GET /api, a representative backend endpoint.
func API(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, map[string]string{
		"service":    "backend-api",
		"message":    "API endpoint is working",
		"request_id": r.Header.Get("X-Request-ID"),
	})
}

// FrontendBridge handles GET /frontend, used to prove connectivity from the
// frontend Docker network.
func FrontendBridge(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, BridgeResponse{
		Service: "frontend-bridge",
		Message: "Frontend service bridge is active",
		Path:    r.RequestURI,
	})
}

// BackendBridge handles GET /backend, used to prove connectivity from the
// backend Docker network.
func BackendBridge(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, BridgeResponse{
		Service: "backend-bridge",
		Message: "Backend service bridge is active",
		Path:    r.RequestURI,
	})
}
