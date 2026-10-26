#!/usr/bin/env pwsh

# Colors for output
$colors = @{
    'Green' = [System.ConsoleColor]::Green
    'Red' = [System.ConsoleColor]::Red
    'Yellow' = [System.ConsoleColor]::Yellow
    'Blue' = [System.ConsoleColor]::Blue
}

Write-Host "=== Docker Observability Stack - Test Suite ===" -ForegroundColor Blue
Write-Host ""

# Test 1: Check if all containers are running
Write-Host "Test 1: Checking if all containers are running..." -ForegroundColor Blue
$containers = @("docker-observability-app", "docker-observability-prometheus", "docker-observability-loki", "docker-observability-fluent-bit", "docker-observability-grafana")

foreach ($container in $containers) {
    $running = docker ps --format "{{.Names}}" | Select-String $container
    if ($running) {
        Write-Host "✓ $container is running" -ForegroundColor Green
    } else {
        Write-Host "✗ $container is NOT running" -ForegroundColor Red
    }
}

Write-Host ""

# Test 2: Test app metrics endpoint
Write-Host "Test 2: Testing app metrics endpoint..." -ForegroundColor Blue
try {
    $response = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/metrics
    if ($response -eq "200") {
        Write-Host "✓ Metrics endpoint is responding (HTTP $response)" -ForegroundColor Green
        Write-Host "   Sample metrics:"
        $metrics = curl.exe -s http://localhost:8080/metrics | Select-Object -First 5
        $metrics | ForEach-Object { Write-Host "   $_" }
    } else {
        Write-Host "✗ Metrics endpoint failed (HTTP $response)" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to reach metrics endpoint" -ForegroundColor Red
}

Write-Host ""

# Test 3: Test Prometheus
Write-Host "Test 3: Testing Prometheus..." -ForegroundColor Blue
try {
    $response = curl.exe -s -o NUL -w "%{http_code}" http://localhost:9090/api/v1/targets
    if ($response -eq "200") {
        Write-Host "✓ Prometheus is responding (HTTP $response)" -ForegroundColor Green
        
        $targets = curl.exe -s http://localhost:9090/api/v1/targets | Select-String "app:8080"
        if ($targets) {
            Write-Host "✓ App target is registered in Prometheus" -ForegroundColor Green
        } else {
            Write-Host "✗ App target is NOT registered in Prometheus" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Prometheus failed (HTTP $response)" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to reach Prometheus" -ForegroundColor Red
}

Write-Host ""

# Test 4: Test Loki
Write-Host "Test 4: Testing Loki..." -ForegroundColor Blue
try {
    $response = curl.exe -s -o NUL -w "%{http_code}" http://localhost:3100/loki/api/v1/status/buildinfo
    if ($response -eq "200") {
        Write-Host "✓ Loki is responding (HTTP $response)" -ForegroundColor Green
    } else {
        Write-Host "✗ Loki failed (HTTP $response)" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to reach Loki" -ForegroundColor Red
}

Write-Host ""

# Test 5: Test Grafana
Write-Host "Test 5: Testing Grafana..." -ForegroundColor Blue
try {
    $response = curl.exe -s -o NUL -w "%{http_code}" http://localhost:3000/api/health
    if ($response -eq "200") {
        Write-Host "✓ Grafana is responding (HTTP $response)" -ForegroundColor Green
        
        $datasources = curl.exe -s -u admin:admin http://localhost:3000/api/datasources
        
        if ($datasources -match "prometheus") {
            Write-Host "✓ Prometheus datasource is configured" -ForegroundColor Green
        } else {
            Write-Host "✗ Prometheus datasource is NOT configured" -ForegroundColor Red
        }
        
        if ($datasources -match "loki") {
            Write-Host "✓ Loki datasource is configured" -ForegroundColor Green
        } else {
            Write-Host "✗ Loki datasource is NOT configured" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Grafana failed (HTTP $response)" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to reach Grafana" -ForegroundColor Red
}

Write-Host ""

# Test 6: Test API endpoints and request IDs
Write-Host "Test 6: Testing API endpoints and request IDs..." -ForegroundColor Blue
try {
    $response = curl.exe -s -i http://localhost:9080/api 2>&1
    $requestIdLine = $response | Select-String "X-Request-ID"
    
    if ($requestIdLine) {
        $requestId = ($requestIdLine -split ": ")[1].Trim()
        Write-Host "✓ Request ID generated: $requestId" -ForegroundColor Green
    } else {
        Write-Host "✗ Request ID header not found in response" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to test API endpoint" -ForegroundColor Red
}

Write-Host ""

# Test 7: Check Fluent Bit log collection
Write-Host "Test 7: Checking Fluent Bit log collection..." -ForegroundColor Blue
try {
    $logs = docker logs docker-observability-fluent-bit 2>&1 | Select-String "error"
    if (-not $logs) {
        Write-Host "✓ Fluent Bit is running without errors" -ForegroundColor Green
    } else {
        Write-Host "⚠ Fluent Bit warnings:" -ForegroundColor Yellow
        $logs | ForEach-Object { Write-Host "   $_" }
    }
} catch {
    Write-Host "✗ Failed to check Fluent Bit logs" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Suite Complete ===" -ForegroundColor Blue
Write-Host ""

Write-Host "Access URLs:" -ForegroundColor Blue
Write-Host "  Grafana:     http://localhost:3000 (admin / admin)" -ForegroundColor Yellow
Write-Host "  Prometheus:  http://localhost:9090" -ForegroundColor Yellow
Write-Host "  Loki:        http://localhost:3100" -ForegroundColor Yellow
Write-Host "  App:         http://localhost:9080" -ForegroundColor Yellow
Write-Host "  Metrics:     http://localhost:8080/metrics" -ForegroundColor Yellow

Write-Host ""
Write-Host "Dashboards:" -ForegroundColor Blue
Write-Host "  HTTP Metrics:    http://localhost:3000/d/http-metrics" -ForegroundColor Yellow
Write-Host "  Logs:            http://localhost:3000/d/logs-dashboard" -ForegroundColor Yellow
Write-Host "  Request Tracing: http://localhost:3000/d/request-tracing" -ForegroundColor Yellow
