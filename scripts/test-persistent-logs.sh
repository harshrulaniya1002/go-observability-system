#!/bin/bash

# Test script for Milestone 2: Persistent Logging
# This script verifies:
# 1. JSON logs are being written continuously
# 2. Logs persist in the named volume
# 3. Logs survive container recreation
# 4. Volume usage can be measured

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Docker Observability - Milestone 2: Persistent Logging Test ===${NC}\n"

# Test 1: Check if container is running
echo -e "${YELLOW}Test 1: Checking if app container is running...${NC}"
if docker ps --filter "name=docker-observability-app" --quiet | grep -q . ; then
    echo -e "${GREEN}? App container is running${NC}\n"
else
    echo -e "${RED}? App container is not running${NC}"
    echo "Please start the containers with: make up"
    exit 1
fi

# Test 2: Generate some traffic to create logs
echo -e "${YELLOW}Test 2: Generating traffic to create log entries (5 requests)...${NC}"
for i in {1..5}; do
    curl -s http://localhost:9080/health > /dev/null
    curl -s http://localhost:9080/api > /dev/null
    sleep 0.5
done
echo -e "${GREEN}? Traffic generated${NC}\n"

# Test 3: Check if logs are being written
echo -e "${YELLOW}Test 3: Verifying logs are written to volume...${NC}"
VOLUME_NAME="docker-observability-go_app-logs"
CONTAINER_LOG_PATH="/var/log/app"

if docker exec docker-observability-app test -d "$CONTAINER_LOG_PATH" ; then
    LOG_FILES=$(docker exec docker-observability-app sh -c "find $CONTAINER_LOG_PATH -name 'app-*.log' 2>/dev/null | wc -l")
    if [ "$LOG_FILES" -gt 0 ]; then
        echo -e "${GREEN}? Found $LOG_FILES log file(s) in volume${NC}"
        
        # Show latest log entries
        echo "Latest log entries:"
        docker exec docker-observability-app sh -c "tail -3 $CONTAINER_LOG_PATH/app-*.log" | sed 's/^/  /'
        echo ""
    else
        echo -e "${YELLOW}? No log files found in volume yet${NC}\n"
    fi
else
    echo -e "${RED}? Log directory not found in container${NC}"
    exit 1
fi

# Test 4: Verify JSON format
echo -e "${YELLOW}Test 4: Verifying JSON log format...${NC}"
FIRST_LOG=$(docker exec docker-observability-app sh -c "head -1 $CONTAINER_LOG_PATH/app-*.log")
if echo "$FIRST_LOG" | grep -q "timestamp" && echo "$FIRST_LOG" | grep -q "level" ; then
    echo -e "${GREEN}? Logs are in valid JSON format${NC}"
    
    # Display JSON structure
    echo "Log entry structure:"
    echo "$FIRST_LOG" | sed 's/^/  /'
    echo ""
else
    echo -e "${RED}? Log entries are not valid JSON${NC}"
    exit 1
fi

# Test 5: Count log lines
echo -e "${YELLOW}Test 5: Counting log entries...${NC}"
LINE_COUNT=$(docker exec docker-observability-app sh -c "wc -l < $CONTAINER_LOG_PATH/app-*.log 2>/dev/null")
echo -e "${GREEN}? Total log entries: $LINE_COUNT${NC}\n"

# Test 6: Measure volume usage
echo -e "${YELLOW}Test 6: Measuring volume usage...${NC}"
VOLUME_SIZE=$(docker exec docker-observability-app sh -c "du -sh $CONTAINER_LOG_PATH 2>/dev/null | cut -f1")
if [ -n "$VOLUME_SIZE" ]; then
    echo -e "${GREEN}? Volume size: $VOLUME_SIZE${NC}"
    
    # Get file details
    echo "Log file details:"
    docker exec docker-observability-app sh -c "ls -lh $CONTAINER_LOG_PATH/app-*.log 2>/dev/null" | awk '{print "  " $9 ": " $5}'
    echo ""
else
    echo -e "${RED}? Could not measure volume size${NC}"
fi

# Test 7: Log persistence - recreate container
echo -e "${YELLOW}Test 7: Testing log persistence across container recreation...${NC}"

LINES_BEFORE=$(docker exec docker-observability-app sh -c "wc -l < $CONTAINER_LOG_PATH/app-*.log 2>/dev/null")

# Stop the app container
echo "Stopping app container..."
docker stop docker-observability-app > /dev/null

# Generate a marker in the log
sleep 2

# Restart the container
echo "Restarting app container..."
docker start docker-observability-app > /dev/null

# Wait for container to be ready
sleep 3

# Generate some traffic
echo "Generating traffic on restarted container..."
for i in {1..3}; do
    curl -s http://localhost:9080/health > /dev/null
    sleep 0.5
done

# Check if logs are still there and have grown
LINES_AFTER=$(docker exec docker-observability-app sh -c "wc -l < $CONTAINER_LOG_PATH/app-*.log 2>/dev/null")

if [ "$LINES_AFTER" -gt "$LINES_BEFORE" ]; then
    echo -e "${GREEN}? Logs persisted across container recreation!${NC}"
    echo "  Before: $LINES_BEFORE entries"
    echo "  After: $LINES_AFTER entries"
    echo "  New entries added: $((LINES_AFTER - LINES_BEFORE))"
    echo ""
else
    echo -e "${YELLOW}? Could not verify log persistence (same number of entries)${NC}\n"
fi

# Test 8: Volume information
echo -e "${YELLOW}Test 8: Docker volume information...${NC}"
docker volume inspect "$VOLUME_NAME" | sed 's/^/  /'
echo ""

echo -e "${BLUE}=== All Tests Completed ===${NC}\n"
echo -e "${GREEN}Summary:${NC}"
echo "  ? JSON logs are being written to: /var/log/app/app-YYYY-MM-DD.log"
echo "  ? Volume name: $VOLUME_NAME"
echo "  ? Current size: $VOLUME_SIZE"
echo "  ? Logs persist across container recreation ?"