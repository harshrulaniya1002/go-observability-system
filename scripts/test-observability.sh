#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Docker Observability Stack - Test Suite ===${NC}\n"

# Test 1: Check if all containers are running
echo -e "${BLUE}Test 1: Checking if all containers are running...${NC}"
CONTAINERS=("docker-observability-app" "docker-observability-prometheus" "docker-observability-loki" "docker-observability-fluent-bit" "docker-observability-grafana")

for container in "${CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        echo -e "${GREEN}✓${NC} $container is running"
    else
        echo -e "${RED}✗${NC} $container is NOT running"
    fi
done

echo ""

# Test 2: Test app metrics endpoint
echo -e "${BLUE}Test 2: Testing app metrics endpoint...${NC}"
METRICS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/metrics)
if [ "$METRICS_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Metrics endpoint is responding (HTTP $METRICS_RESPONSE)"
    echo "   Sample metrics:"
    curl -s http://localhost:8080/metrics | head -5 | sed 's/^/   /'
else
    echo -e "${RED}✗${NC} Metrics endpoint failed (HTTP $METRICS_RESPONSE)"
fi

echo ""

# Test 3: Test Prometheus
echo -e "${BLUE}Test 3: Testing Prometheus...${NC}"
PROM_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/api/v1/targets)
if [ "$PROM_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Prometheus is responding (HTTP $PROM_RESPONSE)"
    # Check if app target is registered
    if curl -s http://localhost:9090/api/v1/targets | grep -q "app:8080"; then
        echo -e "${GREEN}✓${NC} App target is registered in Prometheus"
    else
        echo -e "${RED}✗${NC} App target is NOT registered in Prometheus"
    fi
else
    echo -e "${RED}✗${NC} Prometheus failed (HTTP $PROM_RESPONSE)"
fi

echo ""

# Test 4: Test Loki
echo -e "${BLUE}Test 4: Testing Loki...${NC}"
LOKI_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/loki/api/v1/status/buildinfo)
if [ "$LOKI_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Loki is responding (HTTP $LOKI_RESPONSE)"
else
    echo -e "${RED}✗${NC} Loki failed (HTTP $LOKI_RESPONSE)"
fi

echo ""

# Test 5: Test Grafana
echo -e "${BLUE}Test 5: Testing Grafana...${NC}"
GRAFANA_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health)
if [ "$GRAFANA_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Grafana is responding (HTTP $GRAFANA_RESPONSE)"
    # Check datasources
    PROM_DS=$(curl -s -u admin:admin http://localhost:3000/api/datasources | grep -i prometheus || echo "")
    LOKI_DS=$(curl -s -u admin:admin http://localhost:3000/api/datasources | grep -i loki || echo "")
    
    if [ -n "$PROM_DS" ]; then
        echo -e "${GREEN}✓${NC} Prometheus datasource is configured"
    else
        echo -e "${RED}✗${NC} Prometheus datasource is NOT configured"
    fi
    
    if [ -n "$LOKI_DS" ]; then
        echo -e "${GREEN}✓${NC} Loki datasource is configured"
    else
        echo -e "${RED}✗${NC} Loki datasource is NOT configured"
    fi
else
    echo -e "${RED}✗${NC} Grafana failed (HTTP $GRAFANA_RESPONSE)"
fi

echo ""

# Test 6: Test API endpoints and request IDs
echo -e "${BLUE}Test 6: Testing API endpoints and request IDs...${NC}"
RESPONSE=$(curl -s -i http://localhost:9080/api 2>&1)
REQUEST_ID=$(echo "$RESPONSE" | grep -i "x-request-id" | head -1 | cut -d' ' -f2-)

if [ -n "$REQUEST_ID" ]; then
    echo -e "${GREEN}✓${NC} Request ID generated: $REQUEST_ID"
    
    # Check if request ID is in logs
    sleep 2
    LOGS=$(docker exec docker-observability-app grep -r "$REQUEST_ID" /var/log/app/ 2>/dev/null || echo "")
    if [ -n "$LOGS" ]; then
        echo -e "${GREEN}✓${NC} Request ID found in application logs"
    else
        echo -e "${YELLOW}⚠${NC} Request ID may not yet be in logs (check again after a moment)"
    fi
else
    echo -e "${RED}✗${NC} Request ID header not found in response"
fi

echo ""

# Test 7: Check Fluent Bit log collection
echo -e "${BLUE}Test 7: Checking Fluent Bit log collection...${NC}"
FLUENT_BIT_LOGS=$(docker logs docker-observability-fluent-bit 2>&1 | grep -i error | head -3 || echo "")
if [ -z "$FLUENT_BIT_LOGS" ]; then
    echo -e "${GREEN}✓${NC} Fluent Bit is running without errors"
else
    echo -e "${YELLOW}⚠${NC} Fluent Bit warnings:"
    echo "$FLUENT_BIT_LOGS" | sed 's/^/   /'
fi

echo ""
echo -e "${BLUE}=== Test Suite Complete ===${NC}\n"

echo -e "${BLUE}Access URLs:${NC}"
echo -e "  Grafana:     ${YELLOW}http://localhost:3000${NC} (admin / admin)"
echo -e "  Prometheus:  ${YELLOW}http://localhost:9090${NC}"
echo -e "  Loki:        ${YELLOW}http://localhost:3100${NC}"
echo -e "  App:         ${YELLOW}http://localhost:9080${NC}"
echo -e "  Metrics:     ${YELLOW}http://localhost:8080/metrics${NC}"

echo ""
echo -e "${BLUE}Dashboards:${NC}"
echo -e "  HTTP Metrics:    ${YELLOW}http://localhost:3000/d/http-metrics${NC}"
echo -e "  Logs:            ${YELLOW}http://localhost:3000/d/logs-dashboard${NC}"
echo -e "  Request Tracing: ${YELLOW}http://localhost:3000/d/request-tracing${NC}"
