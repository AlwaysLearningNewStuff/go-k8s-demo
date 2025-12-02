#!/bin/bash
set -e

echo "Starting Kubernetes deployment..."

# Check if kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "demo"; then
    echo "Creating kind cluster..."
    kind create cluster --name demo
else
    echo "Kind cluster 'demo' already exists"
fi

echo "Building Docker image..."
docker build -t go-k8s-demo-api:local .

echo "Loading image into kind cluster..."
kind load docker-image go-k8s-demo-api:local --name demo

echo "Deploying to Kubernetes..."

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml

echo "Waiting for Postgres to be ready (this may take a few minutes on first run)..."
kubectl wait --for=condition=ready pod -l app=postgres -n go-k8s-demo --timeout=180s

echo "Running database migrations..."
# Create ConfigMap from actual migration files
kubectl delete configmap flyway-migrations -n go-k8s-demo --ignore-not-found
kubectl create configmap flyway-migrations -n go-k8s-demo --from-file=migrations/

kubectl delete job flyway-migration -n go-k8s-demo --ignore-not-found
kubectl apply -f k8s/flyway-job.yaml

echo "Waiting for migrations to complete (this may take a few minutes on first run)..."
kubectl wait --for=condition=complete job/flyway-migration -n go-k8s-demo --timeout=300s

echo "Deploying API..."
kubectl apply -f k8s/api-deployment.yaml
kubectl wait --for=condition=ready pod -l app=api -n go-k8s-demo --timeout=180s

echo ""
echo "Deployment complete!"
echo ""
echo "Cluster status:"
kubectl get all -n go-k8s-demo
echo ""
