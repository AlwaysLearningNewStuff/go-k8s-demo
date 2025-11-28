Write-Host "Starting Kubernetes deployment..." -ForegroundColor Green

$clusterExists = kind get clusters 2>$null | Select-String "demo"
if (-not $clusterExists) {
    Write-Host "Creating kind cluster..." -ForegroundColor Yellow
    kind create cluster --name demo
}
else {
    Write-Host "Kind cluster 'demo' already exists" -ForegroundColor Green
}

Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t go-k8s-demo-api:local .

Write-Host "Loading image into kind cluster..." -ForegroundColor Yellow
kind load docker-image go-k8s-demo-api:local --name demo

Write-Host "Deploying to Kubernetes..." -ForegroundColor Yellow

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml

Write-Host "Waiting for Postgres to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=postgres -n demo --timeout=60s

Write-Host "Running database migrations..." -ForegroundColor Yellow
kubectl delete job flyway-migration -n demo --ignore-not-found=true
kubectl apply -f k8s/flyway-job.yaml
kubectl wait --for=condition=complete job/flyway-migration -n demo --timeout=60s

Write-Host "Deploying API..." -ForegroundColor Yellow
kubectl apply -f k8s/api-deployment.yaml
kubectl wait --for=condition=ready pod -l app=api -n demo --timeout=60s

Write-Host ""
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Cluster status:" -ForegroundColor Cyan
kubectl get all -n demo
Write-Host ""
Write-Host "To access the API, run:" -ForegroundColor Cyan
Write-Host "   kubectl port-forward -n demo service/api 8080:80" -ForegroundColor White
Write-Host ""
Write-Host "Then test with:" -ForegroundColor Cyan
Write-Host "   curl http://localhost:8080/healthz" -ForegroundColor White
Write-Host "   curl http://localhost:8080/users" -ForegroundColor White
