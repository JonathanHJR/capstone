$NAMESPACE = "default"
$DEPLOYMENT = "calorie-tracker"
$INTERVAL = 30

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CHAOS ENGINEERING - $DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Killing a random pod every $INTERVAL seconds" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Initial pod state:" -ForegroundColor White
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT
Write-Host ""
Write-Host "  Starting chaos in 10 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

while ($true) {
    $pods = kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'
    $podList = $pods -split ' ' | Where-Object { $_ -ne '' }

    if ($podList.Count -eq 0) {
        Write-Host "  No running pods found. Waiting..." -ForegroundColor Yellow
    } else {
        $pod = $podList | Get-Random
        $time = Get-Date -Format "HH:mm:ss"

        Write-Host ""
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        Write-Host "  [$time] CHAOS: Killing pod" -ForegroundColor Red
        Write-Host "  Target: $pod" -ForegroundColor Red
        Write-Host "----------------------------------------" -ForegroundColor DarkGray

        kubectl delete pod $pod -n $NAMESPACE | Out-Null

        Write-Host "  Pod killed. Current state:" -ForegroundColor Yellow
        kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT
        Write-Host ""
        Write-Host "  Waiting for Kubernetes to recover..." -ForegroundColor Yellow

        $recovered = $false
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 1
            $notReady = kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT --no-headers | Where-Object { $_ -notmatch "Running" -or $_ -match "0/" }
            if (-not $notReady) {
                $recovered = $true
                break
            }
        }

        $time = Get-Date -Format "HH:mm:ss"
        Write-Host ""
        if ($recovered) {
            Write-Host "  [$time] RECOVERED - All pods healthy" -ForegroundColor Green
        } else {
            Write-Host "  [$time] WARNING - Recovery timeout exceeded" -ForegroundColor Red
        }
        Write-Host "  Pods now running:" -ForegroundColor Green
        kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT
        Write-Host "  Next kill in $INTERVAL seconds..." -ForegroundColor DarkGray
    }

    Start-Sleep -Seconds $INTERVAL
}
