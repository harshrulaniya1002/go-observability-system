# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-10-26

### Feature Added: Persistent Logging

#### Structured JSON Logging
- Implemented comprehensive JSON logging for all application events
- Each log entry includes: timestamp, level, service, message, method, path, status_code, duration_ms, hostname, remote_addr, metadata
- RFC3339 UTC timestamps for global consistency
- Thread-safe logging with mutex protection
- Graceful file handling with sync after each write

#### Persistent Volume Storage
- Named volume: `app-logs` mounted at `/var/log/app`
- Daily log rotation with YYYY-MM-DD naming scheme
- Log entries survive container restart and recreation
- 16KB initial volume for 50+ log entries

#### HTTP Request Logging Middleware
- Automatic logging of all HTTP requests with:
  - Request method and path
  - Response status code
  - Request duration in milliseconds
  - Client IP and port
  - Timestamp and hostname
- Middleware wraps response writer to capture status codes

#### Dual Output System
- Simultaneous output to stdout and persistent file
- Real-time log visibility via `docker logs`
- Long-term retention in named volume
- No data loss on container recreation

#### Test Suite for Persistent Logging
- Comprehensive test script: `scripts/test-persistent-logs.sh`
- Verifies:
  - App container is running
  - Traffic generates log entries
  - JSON format validation
  - Log entry counting
  - Volume size measurement
  - Persistence across container recreation
  - Volume information display

#### Makefile Enhancements
- `make test-persistent-logs` - Run persistence test suite
- `make logs-persistent` - View persistent logs from volume
- `make volume-stats` - Show volume usage statistics

#### Documentation
- New file: MILESTONE2.md with comprehensive guide
- Usage examples and troubleshooting
- Log analysis examples (filtering, searching)
- Volume management best practices
- Performance considerations
- Security considerations

#### Code Changes
- Enhanced main.go with Logger struct
- Structured log entry types
- Logging middleware for HTTP requests
- Response writer wrapper for status capture
- Daily log file initialization
- Graceful shutdown handling

### Technical Details

**Log Entry Structure:**
```json
{
  "timestamp": "2026-10-26T10:10:13.51420528Z",
  "level": "INFO",
  "service": "go-app",
  "message": "HTTP Request",
  "method": "GET",
  "path": "/health",
  "status_code": 200,
  "duration_ms": 0.056,
  "hostname": "f61566da5ee1",
  "remote_addr": "10.0.1.3:54592",
  "metadata": {}
}
```

**Volume Configuration:**
```yaml
volumes:
  app-logs:
    driver: local
services:
  app:
    volumes:
      - app-logs:/var/log/app
```

### Verification

✓ Continuous JSON logs written to volume
✓ Named volume persists across container recreation
✓ Volume usage measurable (16KB for 50+ entries)
✓ Dual output working (stdout + file)
✓ Test suite validates all components
✓ Production-ready logging system

### Performance

- Average log entry size: ~300-500 bytes
- Volume growth: ~5-50 MB per day (depending on traffic)
- File sync after each entry ensures data persistence
- Thread-safe logging prevents concurrent write issues

### Backward Compatibility

✓ No breaking changes from Milestone 1
✓ Existing endpoints work identically
✓ Network isolation maintained
✓ Service health checks operational
✓ Stdout logs still visible via docker logs

## [1.0.0] - 2026-10-26

### Added - Milestone 1: Networking

#### Go HTTP Service
- Created comprehensive Go HTTP service with chi router
- Added health check endpoint with service metadata
- Added API endpoint with JSON response
- Added frontend and backend bridge endpoints
- Implemented graceful error handling
- Added detailed startup logging

#### Docker Configuration
- Multi-stage build for optimized Go container (Alpine-based)
- Alpine runtime stage (~10MB image size)
- Health checks with curl for app container
- Health checks with wget for Nginx container
- Proper signal handling and graceful shutdown

#### Nginx Reverse Proxy
- Configured Nginx as reverse proxy in front of Go app
- Setup routing for health, API, frontend, and backend endpoints
- Added proper headers (X-Real-IP, X-Forwarded-For, X-Forwarded-Proto)
- Configured timeouts and buffer sizes
- Health check endpoint for orchestration
- Error page handling

#### Network Architecture
- Three-layer network isolation:
  - **Frontend Network** (172.20.0.0/16): Public-facing, contains Nginx
  - **Backend Network** (172.21.0.0/16): Isolated, contains App and Database
  - **Monitoring Network** (172.22.0.0/16): Observability stack (Prometheus, Grafana)

#### Database Setup
- PostgreSQL 16 Alpine image (minimal footprint)
- Isolated on backend network only
- Environment-based configuration
- Health checks for container orchestration
- Persistent volume for data

#### Monitoring Stack
- Prometheus for metrics collection
- Grafana for visualization and dashboards
- Separate monitoring network
- Prometheus configuration for scrape targets

#### Project Documentation
- Comprehensive README.md with setup, usage, and troubleshooting
- .env.example with default configuration
- Architecture overview
- Network isolation documentation
- Security considerations
- Development workflow guide
- Production deployment recommendations

#### Development Tools
- Makefile with common commands:
  - Build, up/down, logs, clean
  - Health checks
  - Endpoint testing
  - Database isolation testing
  - Container access (shell)

#### Testing & Validation
- test-db-isolation.sh script for network validation
- Network connectivity tests
- Service health verification
- Endpoint accessibility testing
- Database isolation proof

#### Project Management
- .gitignore for Go, Docker, and IDE files
- Proper .dockerignore for build optimization
- CHANGELOG for version tracking

### Technical Specifications

- **Go Version**: 1.25.1
- **Framework**: chi/v1.5.5 (lightweight router)
- **Database**: PostgreSQL 16
- **Reverse Proxy**: Nginx (Alpine)
- **Container Runtime**: Docker with Compose v3.8
- **Monitoring**: Prometheus + Grafana

### Network Benefits

1. **Security**: Database isolated from frontend network
2. **Scalability**: Multiple app instances can share database
3. **Debugging**: Clear network segmentation
4. **Compliance**: Separate data and monitoring networks
5. **Performance**: No unnecessary cross-network traffic

### API Surface

#### Public Endpoints (via Nginx)
- `GET /` - Root service indicator
- `GET /health` - Service health with metadata
- `GET /api` - API endpoint
- `GET /frontend` - Frontend bridge
- `GET /backend` - Backend bridge

#### Internal Endpoints
- App directly accessible on port 8080 (container network)
- Database on port 5432 (backend network only)
- Prometheus on port 9090 (monitoring network)
- Grafana on port 3000 (monitoring network)

### Docker Image Sizes

- App: ~10MB (Go binary + Alpine)
- Nginx: ~20MB (Alpine base)
- PostgreSQL: ~50MB (Alpine base)
- Prometheus: ~50MB
- Grafana: ~200MB

Total footprint: ~330MB (compressed)

### Known Limitations

- Single app instance (scaling to be implemented in future milestone)
- No authentication/authorization yet
- No TLS/SSL (HTTP only)
- Monitoring stack is optional
- No auto-scaling or orchestration

### Future Enhancements

- Database connection pooling
- Metrics endpoints for Prometheus scraping
- Structured logging with JSON output
- Distributed tracing integration
- Database migrations and seeding
- Authentication middleware
- Rate limiting and throttling
- Multi-app deployment orchestration
- CI/CD pipeline integration
