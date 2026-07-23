# deploy.ps1 — Full EKS setup and teardown runbook
# Usage:
#   .\deploy.ps1 setup    — provision cluster and deploy everything
#   .\deploy.ps1 teardown — clean teardown in correct order

param([Parameter(Mandatory)][ValidateSet("setup","teardown")][string]$Action)

$ECR     = "910929919817.dkr.ecr.ap-southeast-1.amazonaws.com"
$REGION  = "ap-southeast-1"
$AWS_PROFILE = "capstone"

# --- Pre-flight checks -----------------------------------------------------
Write-Host "==> Pre-flight checks..."

# Check Docker is running
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    Write-Host "ERROR: Docker Desktop is not running. Start it and try again." -ForegroundColor Red
    exit 1
}

# Ensure kubectl points at EKS (runs early and again before k8s steps)
function Set-EKSContext {
    aws eks update-kubeconfig --region $REGION --name capstone-cluster --profile $AWS_PROFILE 2>&1 | Out-Null
}

# -----------------------------------------------------------------------
if ($Action -eq "setup") {

    Write-Host "==> [1/7] Provisioning AWS infrastructure via Terraform..."
    Set-Location terraform
    terraform apply -auto-approve
    Set-Location ..

    Write-Host "==> [2/7] Connecting kubectl to EKS..."
    Set-EKSContext

    Write-Host "==> [3/7] Building and pushing image to ECR..."
    $token = aws ecr get-login-password --region $REGION --profile $AWS_PROFILE
    docker login --username AWS --password "$token" $ECR
    docker build -t "$ECR/calorie-tracker:latest" .
    docker push "$ECR/calorie-tracker:latest"

    Write-Host "==> [4/7] Deploying Kubernetes manifests..."
    Set-EKSContext
    kubectl apply -f k8s/secrets.yml
    kubectl apply -f k8s/rbac.yml
    kubectl apply -f k8s/postgres.yml
    kubectl apply -f k8s/app.yml
    kubectl apply -f k8s/hpa.yml
    kubectl apply -f k8s/network-policies.yml

    Write-Host "==> [5/7] Installing Helm charts..."
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>&1 | Out-Null
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>&1 | Out-Null
    helm repo add kyverno https://kyverno.github.io/kyverno/ 2>&1 | Out-Null
    helm repo update

    helm install metrics-server metrics-server/metrics-server --namespace kube-system

    kubectl create namespace monitoring

    $grafanaPassword = ""
    while ($grafanaPassword -eq "") {
        $grafanaPassword = Read-Host "Grafana admin password"
        if ($grafanaPassword -eq "") {
            Write-Host "Password cannot be empty. Try again." -ForegroundColor Yellow
        }
    }
    helm install monitoring prometheus-community/kube-prometheus-stack `
        --namespace monitoring `
        --set grafana.adminPassword="$grafanaPassword"

    helm install kyverno kyverno/kyverno `
        --namespace kyverno --create-namespace `
        --set global.image.registry=ghcr.io

    Write-Host "==> [6/7] Creating Slack webhook secret..."
    $slackUrl = ""
    while ($slackUrl -eq "") {
        $slackUrl = Read-Host "Slack webhook URL"
        if ($slackUrl -eq "") {
            Write-Host "Slack URL cannot be empty. Try again." -ForegroundColor Yellow
        }
    }
    kubectl create secret generic slack-webhook `
        --from-literal=url="$slackUrl" `
        --namespace monitoring

    Write-Host "==> [7/7] Applying monitoring and policy manifests..."
    kubectl apply -f k8s/servicemonitor.yml
    kubectl apply -f k8s/kyverno-policies.yml
    kubectl apply -f k8s/alerts.yml
    kubectl apply -f k8s/grafana-dashboard.yml
    kubectl apply -f k8s/alertmanager-config.yml

    Write-Host ""
    Write-Host "==> Setup complete. Waiting for LoadBalancer URL..."
    Start-Sleep -Seconds 30
    kubectl get svc calorie-tracker
}

# -----------------------------------------------------------------------
if ($Action -eq "teardown") {

    Write-Host "==> [1/2] Deleting LoadBalancer service (deprovisions ELB)..."
    Set-EKSContext
    kubectl delete svc calorie-tracker --ignore-not-found

    Write-Host "    Waiting 30s for ELB to be fully deprovisioned..."
    Start-Sleep -Seconds 30

    Write-Host "==> [2/2] Destroying AWS infrastructure via Terraform..."
    Set-Location terraform
    terraform destroy -auto-approve
    Set-Location ..

    Write-Host "==> Teardown complete."
}
