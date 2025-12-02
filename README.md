# Go Kubernetes Demo

A REST API demonstrating Kubernetes deployment with Go, PostgreSQL, Docker, and cloud-native best practices for local development and learning.

## Overview

This project showcases a complete Kubernetes deployment including:
- RESTful API with full CRUD operations
- Containerized Go application with multi-stage Docker builds
- PostgreSQL database with health monitoring
- Automated database migrations using Flyway
- Kubernetes orchestration with proper health probes
- Self-healing and high availability
- Automated deployment scripts

## 🚀 Features

- **REST API** - Full CRUD operations for user management
- **Go + Gin** - High-performance web framework
- **PostgreSQL** - Reliable relational database with connection pooling
- **Docker** - Multi-stage builds for optimized images
- **Kubernetes** - Complete orchestration with health checks
- **Database Migrations** - Versioned schema management with Flyway
- **Health Probes** - Startup, readiness, and liveness checks
- **Graceful Shutdown** - Proper signal handling

## Tech Stack

- **Language**: Go 1.23
- **Web Framework**: Gin
- **Database**: PostgreSQL 15
- **Migration Tool**: Flyway 10
- **Containerization**: Docker with multi-stage builds
- **Orchestration**: Kubernetes (tested with Kind)
- **Database Driver**: pgx/v5 with connection pooling

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) - For building container images
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) - Kubernetes in Docker (for local cluster)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [jq](https://stedolan.github.io/jq/) - JSON processor (optional, for prettier test output)

## Quick Start

### 1. Deploy Everything

```bash
# Make scripts executable
chmod +x deploy.sh endpoint_tests.sh cleanup.sh

# Deploy the entire stack
./deploy.sh
```

The deployment script will:
1. Create a Kind cluster (if it doesn't exist)
2. Build the Docker image with multi-stage build
3. Load the image into the Kind cluster
4. Deploy PostgreSQL with health probes
5. Wait for PostgreSQL to be ready
6. Create ConfigMap from SQL migration files
7. Run Flyway migration as a Kubernetes Job
8. Deploy the API with 2 replicas
9. Wait for all pods to be ready

### 2. Test the API

**Automated tests** (recommended):
```bash
./endpoint_tests.sh
```

This script automatically:
- Starts port-forwarding
- Runs all endpoint tests with colored output
- Shows actual JSON responses
- Cleans up port-forward on exit

**Manual testing:**

```bash
# Port-forward manually
kubectl port-forward -n go-k8s-demo svc/api 8080:80 &

# Health checks
curl http://localhost:8080/healthz        # Basic health check
curl http://localhost:8080/readyz         # Database connectivity check

# CRUD operations
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"username":"Charlie","email":"charlie@example.com"}'

curl http://localhost:8080/users           # List all users
curl http://localhost:8080/users/1         # Get specific user

curl -X PUT http://localhost:8080/users/1 \
  -H "Content-Type: application/json" \
  -d '{"username":"Mike","email":"mike@example.com"}'

curl -X DELETE http://localhost:8080/users/1
```

### 3. Clean Up

```bash
./cleanup.sh
```

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────┐
│           Kind Cluster                      │
│  ┌───────────────────────────────────────┐  │
│  │  Namespace: go-k8s-demo               │  │
│  │                                       │  │
│  │  ┌──────────┐      ┌──────────┐       │  │
│  │  │   API    │──────│   API    │       │  │
│  │  │  (pod1)  │      │  (pod2)  │       │  │
│  │  └────┬─────┘      └────┬─────┘       │  │
│  │       │                 │             │  │
│  │       └────────┬────────┘             │  │
│  │                │                      │  │
│  │         ┌──────▼──────┐               │  │
│  │         │  PostgreSQL │               │  │
│  │         └─────────────┘               │  │
│  │                                       │  │
│  │  ┌──────────────┐                     │  │
│  │  │ Flyway Job   │ (runs once)         │  │
│  │  └──────────────┘                     │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### Kubernetes Resources

- **Namespace:** `go-k8s-demo` - Isolates all resources
- **Deployments:**
  - `api` - 2 replicas with health probes, resource limits
  - `postgres` - Single replica with persistent storage (emptyDir)
- **Services:**
  - `api` - ClusterIP exposing port 8080
  - `postgres` - ClusterIP exposing port 5432
- **Job:** `flyway` - One-time database migration with init container
- **Secret:** `postgres-secret` - Database credentials (base64 encoded)
- **ConfigMap:** `flyway-migrations` - SQL migration files (dynamically created)

### Key Design Decisions

**Multi-stage Docker Build:**
- Builder stage: `golang:1.23-alpine` compiles the binary
- Runtime stage: `gcr.io/distroless/static` for minimal attack surface
- Result: ~2MB final image with no shell or package manager

**Health Probes:**
- **Startup probe:** 30 attempts × 5s = 150s for first-time image pulls
- **Readiness probe:** `/readyz` verifies database connectivity before routing traffic
- **Liveness probe:** `/healthz` restarts containers that become unhealthy

**Database Migrations:**
- Flyway runs as a Kubernetes Job (not in API container)
- Init container ensures Postgres is ready using `pg_isready`
- ConfigMap generated from `migrations/` directory at deploy time

**Resource Management:**
- All pods have CPU/memory requests and limits
- API: 64-128Mi memory, 100-200m CPU
- Postgres: 128-256Mi memory, 100-500m CPU
- Enables proper scheduling and prevents resource starvation

## Production Readiness

### What's Included

✅ **High Availability:** 2 API replicas with automatic load balancing  
✅ **Health Checks:** All three probe types (startup, readiness, liveness)  
✅ **Resource Limits:** CPU/memory requests and limits on all pods  
✅ **Self-Healing:** Kubernetes automatically recreates failed pods  
✅ **Security:** Distroless base image, non-root user, secrets for credentials  
✅ **Database Migrations:** Automated with Flyway as Kubernetes Job  
✅ **Dependency Management:** Init containers ensure correct startup order  

### What's Missing (Intentionally)

This is a **local development/demo project** designed to demonstrate Kubernetes concepts. The following production features are omitted by design:

❌ **Persistent Storage:** Uses `emptyDir` volumes instead of `PersistentVolumeClaims`
- **Why:** Simplifies local setup with Kind; data loss on pod restart is acceptable for demos
- **Production:** Would use PVC with StorageClass for durable database storage

❌ **Ingress Controller:** Uses `kubectl port-forward` instead of Ingress
- **Why:** Avoids complexity of setting up Ingress in Kind (requires extra configuration)
- **Production:** Would use Ingress with TLS termination and proper DNS

❌ **TLS/HTTPS:** All communication is plaintext HTTP
- **Why:** Certificate management adds complexity not needed for local demos
- **Production:** Would use cert-manager for automatic TLS certificates

❌ **Monitoring/Observability:** No Prometheus, Grafana, or logging aggregation
- **Why:** Reduces resource usage on local machine
- **Production:** Would integrate Prometheus metrics, distributed tracing, centralized logging

❌ **Horizontal Pod Autoscaling:** Fixed replica count
- **Why:** Demonstrates HA without metrics-server dependency
- **Production:** Would use HPA based on CPU/memory or custom metrics

❌ **Network Policies:** No network segmentation
- **Why:** Not necessary in single-user local cluster
- **Production:** Would restrict pod-to-pod communication with NetworkPolicies

❌ **RBAC:** Uses default service accounts
- **Why:** Kind cluster has permissive defaults suitable for demos
- **Production:** Would use least-privilege service accounts with RBAC

❌ **Backup/Disaster Recovery:** No backup strategy
- **Why:** Throwaway local environment
- **Production:** Would have automated backups and tested restore procedures

## Project Structure

```
.
├── cmd/
│   └── server/
│       └── main.go                   # API server with health endpoints
├── k8s/                              # Kubernetes manifests
│   ├── namespace.yaml                # Namespace definition
│   ├── postgres-secret.yaml.example  # Secret template (actual file gitignored)
│   ├── postgres-deployment.yaml      # PostgreSQL deployment + service
│   ├── flyway-job.yaml               # Migration job with init container
│   └── api-deployment.yaml           # API deployment + service
├── migrations/
│   └── V1__create_users.sql          # Database schema
├── deploy.sh                         # Automated deployment script
├── endpoint_tests.sh                 # Automated API testing
├── cleanup.sh                        # Cluster deletion script
├── Dockerfile                        # Multi-stage build
├── docker-compose.yaml               # Local development alternative
├── go.mod                            # Go dependencies
├── REFERENCE.md                      # Quick reference guide
└── README.md                         # This file
```

### Kubernetes Manifests

| File | Resource Type | Purpose |
|------|--------------|---------|
| `namespace.yaml` | Namespace | Creates `go-k8s-demo` namespace for resource isolation |
| `postgres-secret.yaml` | Secret | Database credentials (base64 encoded, gitignored) |
| `postgres-deployment.yaml` | Deployment + Service | PostgreSQL with health probes, ClusterIP service on port 5432 |
| `flyway-job.yaml` | Job | Database migration with init container (waits for Postgres) |
| `api-deployment.yaml` | Deployment + Service | Go API with 2 replicas, health probes, LoadBalancer service on port 80 |

## Documentation

- **[REFERENCE.md](REFERENCE.md)** - Quick reference for Kubernetes concepts, commands, and terminology

## Key Kubernetes Concepts Demonstrated

✅ **Pods & Deployments** - Declarative replica management  
✅ **Services** - Internal load balancing and service discovery  
✅ **Jobs** - One-time task execution for migrations  
✅ **ConfigMaps** - Configuration data injection  
✅ **Secrets** - Sensitive credential management  
✅ **Health Probes** - Startup, readiness, liveness monitoring  
✅ **Init Containers** - Dependency management and startup ordering  
✅ **Resource Management** - CPU/memory requests and limits  
✅ **Self-Healing** - Automatic pod recreation on failure  

## License

This project is a learning demonstration and is not licensed for production use.
