.PHONY: help build up down logs clean test health test-endpoints test-persistent-logs volume-stats metrics logs-loki dashboard-urls test-observability

# Detect OS - use a more reliable method
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
ifeq ($(UNAME_S),Windows)
	DETECTED_OS := Windows
else ifeq ($(UNAME_S),Darwin)
	DETECTED_OS := Darwin
else ifneq (,$(findstring MINGW,$(UNAME_S)))
	DETECTED_OS := Windows
else ifneq (,$(findstring MSYS,$(UNAME_S)))
	DETECTED_OS := Windows
else
	DETECTED_OS := Linux
endif

help:
	@echo "Docker Observability Go - Available Commands"
	@echo ""
	@echo "  make build              Build Docker images"
	@echo "  make up                 Start all services"
	@echo "  make down               Stop all services"
	@echo "  make restart            Restart all services"
	@echo "  make logs               View service logs"
	@echo "  make logs-app           View app logs"
	@echo "  make logs-nginx         View Nginx logs"
	@echo "  make logs-db            View Database logs"
	@echo "  make volume-stats       Show volume usage statistics"
	@echo "  make clean              Remove containers and volumes"
	@echo "  make test               Run all tests"
	@echo "  make health             Check service health"
	@echo "  make test-endpoints     Test API endpoints"
	@echo "  make test-persistent-logs  Test persistent logging (Milestone 2)"
	@echo "  make shell-app          Open shell in app container"
	@echo "  make shell-db           Open shell in database container"
	@echo "  make ps                 Show running containers"
	@echo ""
	@echo "  Observability (Milestone 3):"
	@echo "  make metrics            View Prometheus metrics endpoint"
	@echo "  make logs-loki          View logs from Loki"
	@echo "  make dashboard-urls     Show all dashboard URLs"
	@echo "  make logs-fluent-bit    View Fluent Bit logs"
	@echo "  make test-observability Test observability stack"

build:
	docker-compose build

up:
	docker-compose up -d
	@echo ""
	@echo "Services are starting..."
	@sleep 3
	@make health

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

logs-app:
	docker-compose logs -f app

logs-nginx:
	docker-compose logs -f nginx

logs-db:
	docker-compose logs -f postgres

clean:
	docker-compose down -v
	@echo "Containers and volumes removed"

test: test-endpoints
	@echo ""
	@echo "All tests completed"

test-persistent-logs:
	@echo "Testing persistent logging (Milestone 2)..."
ifeq ($(DETECTED_OS),Windows)
	@powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-persistent-logs.ps1
else
	@bash scripts/test-persistent-logs.sh
endif

volume-stats:
ifeq ($(DETECTED_OS),Windows)
	@powershell -NoProfile -ExecutionPolicy Bypass -File scripts\volume-stats.ps1
else
	@echo "Volume Statistics:"
	@echo ""
	@echo "App Logs Volume:"
	@docker volume inspect docker-observability-go_app-logs | grep -A1 '"Mountpoint"' | tail -1 | cut -d'"' -f4 | xargs -I {} du -sh {}
	@echo ""
	@docker volume inspect docker-observability-go_app-logs | grep -A1 '"Mountpoint"' | tail -1 | cut -d'"' -f4 | xargs -I {} find {} -name "app-*.log" -exec sh -c 'echo "  {}:"; wc -l {} | awk "{print \"    Lines: \" \$$1}"; du -h {} | awk "{print \"    Size: \" \$$1}"' \;
	@echo ""
	@echo "All Volumes:"
	@docker volume ls --format "{{.Name}}\t({{.Driver}})"
endif

health:
	@echo "Checking service health..."
	@echo ""
	@echo "Nginx:"
	@curl -s http://localhost:9080/health | jq . || echo "Not yet ready..."
	@echo ""
	@echo "App:"
	@docker exec docker-observability-app curl -s http://localhost:8080/health | jq . || echo "Not yet ready..."
	@echo ""

test-endpoints:
	@echo "Testing API endpoints..."
	@echo ""
	@echo "GET / (Root):"
	@curl -s http://localhost:9080/ || echo "Not ready"
	@echo ""
	@echo "GET /health:"
	@curl -s http://localhost:9080/health | jq . || echo "Not ready"
	@echo ""
	@echo "GET /api:"
	@curl -s http://localhost:9080/api | jq . || echo "Not ready"
	@echo ""
	@echo "GET /frontend:"
	@curl -s http://localhost:9080/frontend | jq . || echo "Not ready"
	@echo ""
	@echo "GET /backend:"
	@curl -s http://localhost:9080/backend | jq . || echo "Not ready"
	@echo ""

shell-app:
	docker exec -it docker-observability-app sh

shell-db:
	docker exec -it docker-observability-db psql -U ${DB_USER:-observability} -d ${DB_NAME:-observability_db}

ps:
	docker-compose ps

metrics:
	@echo "Fetching Prometheus metrics from app..."
	@curl -s http://localhost:8080/metrics | head -20
	@echo ""
	@echo "Full metrics available at: http://localhost:8080/metrics"

logs-loki:
	@echo "Querying Loki for recent logs..."
	@curl -s 'http://localhost:3100/loki/api/v1/query_range?query=%7Bservice%3D%22go-app%22%7D&limit=50' | jq . || echo "Loki not ready"

logs-fluent-bit:
	docker-compose logs -f fluent-bit

dashboard-urls:
	@echo ""
	@echo "=== Docker Observability Dashboards ==="
	@echo ""
	@echo "Grafana:"
	@echo "  URL: http://localhost:3000"
	@echo "  User: admin"
	@echo "  Password: admin"
	@echo ""
	@echo "Dashboards:"
	@echo "  HTTP Metrics:    http://localhost:3000/d/http-metrics"
	@echo "  Logs:            http://localhost:3000/d/logs-dashboard"
	@echo "  Request Tracing: http://localhost:3000/d/request-tracing"
	@echo ""
	@echo "Prometheus:"
	@echo "  URL: http://localhost:9090"
	@echo "  Targets: http://localhost:9090/targets"
	@echo ""
	@echo "Loki:"
	@echo "  URL: http://localhost:3100"
	@echo "  Status: http://localhost:3100/loki/api/v1/status/buildinfo"
	@echo ""
	@echo "Application:"
	@echo "  App API: http://localhost:9080"
	@echo "  Metrics: http://localhost:8080/metrics"
	@echo ""

test-observability:
	@echo "Testing observability stack..."
ifeq ($(DETECTED_OS),Windows)
	@powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-observability.ps1
else
	@bash scripts/test-observability.sh
endif

.DEFAULT_GOAL := help

