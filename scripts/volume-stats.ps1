# Script to display volume statistics
Write-Host "Volume Statistics:" -ForegroundColor Cyan
Write-Host ""

try {
    # Get the app logs volume mount point
    $volumeInfo = docker volume inspect docker-observability-go_app-logs -f '{{.Mountpoint}}'
    
    if (-not $volumeInfo) {
        Write-Host "[ERROR] Could not find app-logs volume" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "App Logs Volume:" -ForegroundColor Yellow
    Write-Host "  Mount point: $volumeInfo"
    
    # We can get file info from inside the container instead
    $fileDetailsResult = docker exec docker-observability-app sh -c "du -sh /var/log/app 2>/dev/null && echo '---' && ls -lh /var/log/app/app-*.log 2>/dev/null || echo 'No log files found'"
    
    if ($fileDetailsResult) {
        Write-Host "  Size information:"
        $lines = $fileDetailsResult -split "`n"
        foreach ($line in $lines) {
            if ($line -and $line -ne "---") {
                Write-Host "    $line"
            }
        }
    }
    
    Write-Host ""
    
    # Count lines in log files
    try {
        $lineCount = docker exec docker-observability-app sh -c "find /var/log/app -name 'app-*.log' -exec wc -l {} + | tail -1 | awk '{print `$1}'"
        if ($lineCount -and $lineCount -gt 0) {
            Write-Host "  Log entries:"
            Write-Host "    Total lines: $($lineCount.Trim())"
        }
    } catch {
        # Ignore if we can't count lines
    }
    
    Write-Host ""
    
} catch {
    Write-Host "[ERROR] Failed to get volume statistics: $_" -ForegroundColor Red
    exit 1
}

Write-Host "All Volumes:" -ForegroundColor Yellow

try {
    $volumes = docker volume ls --format "{{.Name}} ({{.Driver}})"
    $volumes | ForEach-Object {
        Write-Host "  $_"
    }
} catch {
    Write-Host "[ERROR] Failed to list volumes: $_" -ForegroundColor Red
}
