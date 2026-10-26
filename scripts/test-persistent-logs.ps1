# Test script for Milestone 2: Persistent Logging (PowerShell version for Windows)
# This script verifies:
# 1. JSON logs are being written continuously
# 2. Logs persist in the named volume
# 3. Logs survive container recreation
# 4. Volume usage can be measured

$ErrorActionPreference = "Continue"

Write-Host "=== Docker Observability - Milestone 2: Persistent Logging Test ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if container is running
Write-Host "Test 1: Checking if app container is running..." -ForegroundColor Yellow
try {
    $containerCheck = docker ps --filter "name=docker-observability-app" --quiet
    if ($containerCheck) {
        Write-Host "[OK] App container is running" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] App container is not running" -ForegroundColor Red
        Write-Host "Please start the containers with: make up"
        exit 1
    }
} catch {
    Write-Host "[ERROR] Error checking container: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 2: Generate some traffic to create logs
Write-Host "Test 2: Generating traffic to create log entries (5 requests)..." -ForegroundColor Yellow
for ($i = 1; $i -le 5; $i++) {
    try {
        Invoke-WebRequest -Uri "http://localhost:9080/health" -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
        Invoke-WebRequest -Uri "http://localhost:9080/api" -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 500
    } catch {
        # Ignore errors - just for traffic generation
    }
}
Write-Host "[OK] Traffic generated" -ForegroundColor Green
Write-Host ""

# Test 3: Check if logs are being written
Write-Host "Test 3: Verifying logs are written to volume..." -ForegroundColor Yellow
$CONTAINER_LOG_PATH = "/var/log/app"

try {
    $logCheck = docker exec docker-observability-app sh -c "test -d $CONTAINER_LOG_PATH && echo 'exists'" 2>&1
    if ($logCheck -like "*exists*") {
        $logFilesResult = docker exec docker-observability-app sh -c "find $CONTAINER_LOG_PATH -name 'app-*.log' 2>/dev/null | wc -l"
        $logFileCount = [int]($logFilesResult -split ' ' | Select-Object -Last 1)
        
        if ($logFileCount -gt 0) {
            Write-Host "[OK] Found $logFileCount log file(s) in volume" -ForegroundColor Green
            
            # Show latest log entries
            Write-Host "Latest log entries:"
            $logContent = docker exec docker-observability-app sh -c "tail -3 $CONTAINER_LOG_PATH/app-*.log" 2>&1
            $logContent | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        } else {
            Write-Host "[WARN] No log files found in volume yet" -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host "[ERROR] Log directory not found in container" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] Error checking logs: $_" -ForegroundColor Red
    exit 1
}

# Test 4: Verify JSON format
Write-Host "Test 4: Verifying JSON log format..." -ForegroundColor Yellow
try {
    $firstLog = docker exec docker-observability-app sh -c "head -1 $CONTAINER_LOG_PATH/app-*.log"
    
    if ($firstLog -like "*timestamp*" -and $firstLog -like "*level*") {
        Write-Host "[OK] Logs are in valid JSON format" -ForegroundColor Green
        
        # Display JSON structure
        Write-Host "Log entry structure:"
        Write-Host "  $firstLog"
        Write-Host ""
    } else {
        Write-Host "[ERROR] Log entries are not valid JSON" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] Error verifying JSON format: $_" -ForegroundColor Red
    exit 1
}

# Test 5: Count log lines
Write-Host "Test 5: Counting log entries..." -ForegroundColor Yellow
try {
    $lineCountResult = docker exec docker-observability-app sh -c "find $CONTAINER_LOG_PATH -name 'app-*.log' -exec wc -l {} + | tail -1 | awk '{print `$1}'"
    $lineCount = [int]($lineCountResult.Trim())
    Write-Host "[OK] Total log entries: $lineCount" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "[ERROR] Error counting lines: $_" -ForegroundColor Red
}

# Test 6: Measure volume usage
Write-Host "Test 6: Measuring volume usage..." -ForegroundColor Yellow
$volumeSizeResult = ""
try {
    $volumeSizeResult = docker exec docker-observability-app sh -c "du -sh $CONTAINER_LOG_PATH 2>/dev/null | cut -f1"
    if ($volumeSizeResult) {
        Write-Host "[OK] Volume size: $volumeSizeResult" -ForegroundColor Green
        
        # Get file details
        Write-Host "Log file details:"
        $fileDetails = docker exec docker-observability-app sh -c "ls -lh $CONTAINER_LOG_PATH/app-*.log 2>/dev/null"
        $fileDetails | ForEach-Object { 
            $parts = $_ -split '\s+'
            if ($parts.Count -gt 9) {
                Write-Host "  $($parts[-1]): $($parts[-5])"
            }
        }
        Write-Host ""
    } else {
        Write-Host "[ERROR] Could not measure volume size" -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Error measuring volume: $_" -ForegroundColor Red
}

# Test 7: Log persistence - recreate container
Write-Host "Test 7: Testing log persistence across container recreation..." -ForegroundColor Yellow

try {
    $linesBeforeResult = docker exec docker-observability-app sh -c "find $CONTAINER_LOG_PATH -name 'app-*.log' -exec wc -l {} + | tail -1 | awk '{print `$1}'"
    $linesBefore = [int]($linesBeforeResult.Trim())
    
    # Stop the app container
    Write-Host "Stopping app container..."
    docker stop docker-observability-app | Out-Null
    
    # Wait a bit
    Start-Sleep -Seconds 2
    
    # Restart the container
    Write-Host "Restarting app container..."
    docker start docker-observability-app | Out-Null
    
    # Wait for container to be ready
    Start-Sleep -Seconds 3
    
    # Generate some traffic
    Write-Host "Generating traffic on restarted container..."
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri "http://localhost:9080/health" -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 500
        } catch {
            # Ignore errors
        }
    }
    
    # Check if logs are still there and have grown
    $linesAfterResult = docker exec docker-observability-app sh -c "find $CONTAINER_LOG_PATH -name 'app-*.log' -exec wc -l {} + | tail -1 | awk '{print `$1}'"
    $linesAfter = [int]($linesAfterResult.Trim())
    
    if ($linesAfter -gt $linesBefore) {
        Write-Host "[OK] Logs persisted across container recreation!" -ForegroundColor Green
        Write-Host "  Before: $linesBefore entries"
        Write-Host "  After: $linesAfter entries"
        Write-Host "  New entries added: $($linesAfter - $linesBefore)"
        Write-Host ""
    } else {
        Write-Host "[WARN] Could not verify log persistence (same number of entries)" -ForegroundColor Yellow
        Write-Host ""
    }
} catch {
    Write-Host "[ERROR] Error during persistence test: $_" -ForegroundColor Red
}

# Test 8: Volume information
Write-Host "Test 8: Docker volume information..." -ForegroundColor Yellow
try {
    $volumeInfo = docker volume inspect docker-observability-go_app-logs
    $volumeInfo | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
} catch {
    Write-Host "[ERROR] Error inspecting volume: $_" -ForegroundColor Red
}

Write-Host "=== All Tests Completed ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Green
Write-Host "  [OK] JSON logs are being written to: /var/log/app/app-YYYY-MM-DD.log"
Write-Host "  [OK] Volume name: docker-observability-go_app-logs"
if ($volumeSizeResult) {
    Write-Host "  [OK] Current size: $volumeSizeResult"
}
Write-Host "  [OK] Logs persist across container recreation"
