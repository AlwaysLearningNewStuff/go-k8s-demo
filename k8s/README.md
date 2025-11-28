# Kubernetes Deployment Guide

## Prerequisites
- Docker Desktop running
- kind installed (Kubernetes IN Docker)

## Quick Start

### 1. Install kind (if not already installed)
On Windows with PowerShell:
```powershell
# Using Chocolatey
choco install kind

# Or download manually from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
```

On WSL/Linux:
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### 2. Create kind cluster
```bash
kind create cluster --name demo
```

### 3. Build and load Docker image
```bash
# Build the image
docker build -t go-k8s-demo-api:local .

# Load image into kind cluster
kind load docker-image go-k8s-demo-api:local --name demo
```

### 4. Deploy to Kubernetes
```bash
# Apply all manifests in order
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml

# Wait for postgres to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n demo --timeout=60s

# Run migrations
kubectl apply -f k8s/flyway-job.yaml

# Wait for migration job to complete
kubectl wait --for=condition=complete job/flyway-migration -n demo --timeout=60s

# Deploy API
kubectl apply -f k8s/api-deployment.yaml

# Wait for API to be ready
kubectl wait --for=condition=ready pod -l app=api -n demo --timeout=60s
```

### 5. Access the API
```bash
# Port forward to access locally
kubectl port-forward -n demo service/api 8080:80
```

Then test with:
```bash
curl http://localhost:8080/healthz
curl http://localhost:8080/users
```

## Useful Commands

### Check deployment status
```bash
kubectl get all -n demo
```

### View logs
```bash
# API logs
kubectl logs -n demo -l app=api --tail=50 -f

# Postgres logs
kubectl logs -n demo -l app=postgres --tail=50 -f

# Migration job logs
kubectl logs -n demo job/flyway-migration
```

### Restart migration (if needed)
```bash
kubectl delete job flyway-migration -n demo
kubectl apply -f k8s/flyway-job.yaml
```

### Clean up
```bash
# Delete all resources
kubectl delete namespace demo

# Or delete the entire cluster
kind delete cluster --name demo
```

## Architecture

- **Namespace**: `demo` - Isolated environment
- **PostgreSQL**: Single replica StatefulSet-like deployment
- **Flyway**: Kubernetes Job for database migrations
- **API**: 2 replicas with readiness/liveness probes
- **Services**: ClusterIP for postgres, LoadBalancer for API

## Notes for Demo

- The API service uses `type: LoadBalancer` which in kind will be accessible via port-forward
- For a real demo, you might want to set up an Ingress instead
- Database has no persistent volume (fresh state on each deployment)
- Perfect for disposable demos!
