# deploy.ps1 — Full EKS setup and teardown runbook
# Usage:
#   .\deploy.ps1 setup    — provision cluster and deploy everything
#   .\deploy.ps1 teardown — clean teardown in correct order

param([Parameter(Mandatory)][ValidateSet("setup","teardown")][string]$Action)

$ECR    = "910929919817.dkr.ecr.ap-southeast-1.amazonaws.com"
$REGION = "ap-southeast-1"
$PROFILE = "capstone"

# -----------------------------------------------------------------------
if ($Action -eq "setup") {

    Write-Host "==> [1/7] Provisioning AWS infrastructure via Terraform..."
    Set-Location terraform
    terraform apply -auto-approve
    Set-Location ..

    Write-Host "==> [2/7] Connecting kubectl to EKS..."
    aws eks update-kubeconfig --region $REGION --name capstone-cluster --profile $PROFILE

    Write-Host "==> [3/7] Building and pushing image to ECR..."
    $token = aws ecr get-login-password --region $REGION --profile $PROFILE
    docker login --username AWS --password "$token" $ECR
    docker build -t "$ECR/calorie-tracker:latest" .
    docker push "$ECR/calorie-tracker:latest"

    Write-Host "==> [4/7] Deploying Kubernetes manifests..."
    kubectl apply -f k8s/secrets.yml
    kubectl apply -f k8s/rbac.yml
    kubectl apply -f k8s/postgres.yml
    kubectl apply -f k8s/app.yml
    kubectl apply -f k8s/hpa.yml
    kubectl apply -f k8s/network-policies.yml

    Write-Host "==> [5/7] Installing Helm charts..."
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add kyverno https://kyverno.github.io/kyverno/
    helm repo update

    helm install metrics-server metrics-server/metrics-server --namespace kube-system
    kubectl create namespace monitoring
    $grafanaPassword = Read-Host "Grafana admin password"
    helm install monitoring prometheus-community/kube-prometheus-stack `
        --namespace monitoring `
        --set grafana.adminPassword="$grafanaPassword"
    helm install kyverno kyverno/kyverno `
        --namespace kyverno --create-namespace `
        --set global.image.registry=ghcr.io

    Write-Host "==> [6/7] Creating Slack webhook secret..."
    Write-Host "    ACTION REQUIRED: Enter credentials when prompted."
    $slackUrl = Read-Host "Slack webhook URL"
    kubectl create secret generic slack-webhook `
        --from-literal=url="$slackUrl" `
        --namespace monitoring

    Write-Host "==> [7/7] Applying monitoring and policy manifests..."
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
    aws eks update-kubeconfig --region $REGION --name capstone-cluster --profile $PROFILE
    kubectl delete svc calorie-tracker --ignore-not-found

    Write-Host "    Waiting 30s for ELB to be fully deprovisioned..."
    Start-Sleep -Seconds 30

    Write-Host "==> [2/2] Destroying AWS infrastructure via Terraform..."
    Set-Location terraform
    terraform destroy -auto-approve
    Set-Location ..

    Write-Host "==> Teardown complete."
}
