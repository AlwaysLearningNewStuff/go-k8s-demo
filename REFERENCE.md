# Kubernetes Reference Guide

> Quick reference for Kubernetes concepts, commands, and terminology I don't use daily. Maintaining this helps me recall syntax and definitions without memorizing everything.

## Project Overview

REST API demonstrating Kubernetes deployment with Go and PostgreSQL. Key features: multi-stage Docker builds, all three health probe types, automated database migrations via Jobs, init containers for dependency management, high availability with 2 replicas, self-healing, and resource limits. Deployed locally using Kind.

---

## Kubernetes Core Concepts

### What is Kubernetes?

Container orchestration platform that automates deployment, scaling, and management of containerized applications. Provides self-healing, automatic restarts, load balancing, and rolling updates instead of manual container management.

### Kubernetes Resources

| Resource | Definition | Usage in This Project |
|----------|-----------|--------------|
| **Pod** | Smallest deployable unit - wraps one or more containers | Each API/Postgres/Flyway instance runs in a pod |
| **Deployment** | Manages replicas and rolling updates | Ensures 2 API pods always running, auto-restarts on failure |
| **Service** | Stable network endpoint for pods | Provides DNS name (e.g., `postgres.go-k8s-demo.svc.cluster.local`) and load balances across API pods |
| **Job** | Runs task once to completion | Database migrations that run once then exit |
| **ConfigMap** | Non-sensitive configuration data | Stores SQL migration files loaded from `migrations/` directory |
| **Secret** | Sensitive data (base64 encoded) | Stores database credentials (username, password, connection string) |
| **Namespace** | Logical isolation boundary | Separates this project's resources (`go-k8s-demo` namespace) |
| **Init Container** | Container that runs before main container | Waits for Postgres to be ready (`pg_isready`) before Flyway runs |

---

## Health Probes

### Three Types

| Probe Type | Purpose | On Failure | This Project |
|-----------|---------|-----------|--------------|
| **startupProbe** | Gives container time to start | Restarts pod after threshold | 30 attempts × 5s = 150s for slow startup (image pulls) |
| **readinessProbe** | Is container ready to receive traffic? | Removes from Service (doesn't restart) | `/readyz` endpoint checks database connectivity |
| **livenessProbe** | Is container still healthy? | Kills and restarts pod | `/healthz` endpoint detects deadlocks/hung processes |

**Key Difference:**
- **Readiness** = "Not ready yet, don't send traffic" (temporary state)
- **Liveness** = "Something's broken, restart me" (fatal condition)

### Why All Three?

Different failure scenarios need different responses:
- **Startup**: First deployment with large image pull takes time - don't restart prematurely
- **Readiness**: Database connection lost temporarily - stop routing traffic but give it time to recover
- **Liveness**: Pod is deadlocked - kill and restart is only option

---

## Docker Multi-Stage Builds

### Why Use Multi-Stage?

Security and efficiency. Build stage needs full toolchain, runtime stage only needs the binary.

| Stage | Base Image | Purpose | Size |
|-------|-----------|---------|------|
| **Builder** | `golang:1.23-alpine` | Compile Go code | ~300MB |
| **Runtime** | `gcr.io/distroless/static` | Run binary only | ~2MB |

### Benefits

- **Size**: ~2MB final image vs ~300MB+ with full OS
- **Security**: No shell, package manager, or unnecessary tools (minimal attack surface)
- **CVE Exposure**: Fewer packages = fewer vulnerabilities
- **Non-root**: Runs as UID 65532 (security best practice)

---

## Database Migrations

### Flyway

Tracks database schema changes as versioned SQL files (e.g., `V1__create_users.sql`).

**How it works:**
1. Creates `flyway_schema_history` table in database
2. Checks which migrations have been applied
3. Runs new migrations in order
4. Records results in history table

**Benefits:**
- Every environment gets identical schema
- Migrations are repeatable and idempotent (safe to run multiple times)
- Clear audit trail of all schema changes
- Version control for database structure

### Why Kubernetes Job (Not Deployment)?

| Resource | Behavior | Use Case |
|----------|----------|----------|
| **Deployment** | Runs continuously, restarts on exit | Long-running services (API, database) |
| **Job** | Runs once to completion, exits | One-time tasks (migrations, data imports) |

Jobs are perfect for migrations: they run Flyway once, exit, and don't consume resources afterward. If migration fails, Kubernetes can retry based on `backoffLimit`.

### Init Container Pattern

Init containers run **before** the main container starts. They run sequentially and must complete successfully.

**This project:** Flyway Job uses init container with `pg_isready` to wait for PostgreSQL to accept connections. This prevents race conditions where Flyway starts before database is ready. Init containers complete or the main container never starts - perfect for dependency checking.

---

## Useful kubectl Commands

### Viewing Resources

```bash
# Get all resources in namespace
kubectl get all -n go-k8s-demo

# Get pods with labels
kubectl get pods -n go-k8s-demo -l app=api

# Watch pods in real-time
kubectl get pods -n go-k8s-demo --watch

# Detailed resource info
kubectl describe deployment api -n go-k8s-demo
kubectl describe pod <pod-name> -n go-k8s-demo

# Get pod logs
kubectl logs -n go-k8s-demo <pod-name>
kubectl logs -n go-k8s-demo -l app=api --tail=50
kubectl logs -n go-k8s-demo <pod-name> --follow  # Stream logs

# Get init container logs
kubectl logs -n go-k8s-demo <pod-name> -c <init-container-name>
```

### Debugging

```bash
# Execute command in pod
kubectl exec -n go-k8s-demo <pod-name> -- <command>

# Interactive shell (if available)
kubectl exec -it -n go-k8s-demo <pod-name> -- /bin/sh

# Check events
kubectl get events -n go-k8s-demo --sort-by='.lastTimestamp'

# Port forward to service
kubectl port-forward -n go-k8s-demo svc/api 8080:8080

# Port forward to pod
kubectl port-forward -n go-k8s-demo <pod-name> 8080:8080
```

### Managing Resources

```bash
# Apply configuration
kubectl apply -f k8s/

# Delete resources
kubectl delete -f k8s/api-deployment.yaml
kubectl delete pod <pod-name> -n go-k8s-demo

# Restart deployment (rolling restart)
kubectl rollout restart deployment api -n go-k8s-demo

# Scale deployment
kubectl scale deployment api -n go-k8s-demo --replicas=3

# Check rollout status
kubectl rollout status deployment api -n go-k8s-demo
```

### ConfigMaps & Secrets

```bash
# Create ConfigMap from files
kubectl create configmap flyway-migrations -n go-k8s-demo --from-file=migrations/

# View ConfigMap
kubectl get configmap flyway-migrations -n go-k8s-demo -o yaml

# Create Secret
kubectl create secret generic postgres-secret -n go-k8s-demo \
  --from-literal=username=postgres \
  --from-literal=password=postgres

# Decode Secret (base64)
kubectl get secret postgres-secret -n go-k8s-demo -o jsonpath='{.data.password}' | base64 -d
```

### Jobs

```bash
# Get jobs
kubectl get jobs -n go-k8s-demo

# Get job logs
kubectl logs job/flyway-migration -n go-k8s-demo

# Delete completed job
kubectl delete job flyway-migration -n go-k8s-demo
```

---

## Common Questions & Answers

### Service Types

**Q: What's the difference between ClusterIP and LoadBalancer?**

- **ClusterIP**: Internal-only IP within cluster. Used for services that shouldn't be exposed externally (e.g., databases). Default service type.
- **LoadBalancer**: Exposes service externally via cloud provider's load balancer. In cloud environments (AWS/GCP/Azure) gets external IP. In Kind, stays pending but demonstrates the pattern.
- **NodePort**: Exposes service on each node's IP at a static port. Accessible from outside cluster via `<NodeIP>:<NodePort>`.

### Kubernetes DNS

**Q: How does the API find the database?**

Kubernetes has built-in DNS. Every Service gets a DNS name:
- Full FQDN: `<service-name>.<namespace>.svc.cluster.local`
- Short name (same namespace): `<service-name>`
- Example: Postgres Service accessible at `postgres.go-k8s-demo.svc.cluster.local` or just `postgres` within same namespace

### Secrets

**Q: Are Kubernetes Secrets encrypted?**

- **This project**: Base64 encoded, not encrypted
- **Production**: Use encryption at rest (available in managed Kubernetes) or external secret managers (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault)
- Base64 is encoding, not encryption - anyone with access can decode

### Rolling Updates

**Q: How do updates work without downtime?**

Kubernetes does rolling updates by default:
1. Creates new pods with updated image
2. Waits for new pods to pass readiness checks
3. Terminates old pods one by one
4. Service only routes traffic to ready pods

Control with:
- `maxSurge`: How many pods above desired count during update
- `maxUnavailable`: How many pods can be unavailable during update

### Resource Management

**Q: What's the difference between requests and limits?**

- **Requests**: Guaranteed resources. Scheduler uses this to decide which node can fit the pod.
- **Limits**: Maximum resources pod can use. If exceeded, pod may be throttled (CPU) or killed (memory).

Example: API pod requests 64Mi memory (guaranteed) with 128Mi limit (maximum).

### High Availability

**Q: Why 2 API replicas?**

- If one pod crashes, other continues serving traffic
- Load balancing across multiple pods
- Production: More replicas across multiple nodes/availability zones
- Can use HorizontalPodAutoscaler (HPA) to scale based on CPU/memory/custom metrics

### Persistent Storage

**Q: What happens if database pod restarts?**

- **This project**: Uses `emptyDir` volume - data is lost on pod restart
- **Production**: Use PersistentVolumeClaim (PVC) with StorageClass. Volume survives pod restarts, can move between nodes.

### Monitoring & Logging

**Q: How would you handle production observability?**

**Logging:**
- Centralized logging: ELK stack (Elasticsearch, Logstash, Kibana) or Grafana Loki
- Pods write to stdout/stderr, log aggregator collects from all nodes
- Searchable, centralized logs across all pods

**Monitoring:**
- Prometheus for metrics collection
- Grafana for visualization
- Expose `/metrics` endpoint in applications
- Monitor: request rate, error rate, latency (RED metrics), resource usage

### Kind vs Production Clusters

**Q: Why use Kind?**

- **Kind**: Kubernetes in Docker, perfect for local dev/demos
  - Fast create/destroy
  - Runs entirely locally
  - Supports most Kubernetes features
  
- **Production**: Managed Kubernetes services
  - AWS EKS, Google GKE, Azure AKS
  - High availability across availability zones
  - Automatic upgrades and patching
  - Integration with cloud services (load balancers, storage, IAM)

---

## Kubernetes Terminology

| Term | Definition |
|------|-----------|
| **Container** | Lightweight, standalone executable package (Docker image) |
| **Pod** | Smallest deployable unit - wraps one or more containers |
| **Node** | Worker machine in Kubernetes (VM or physical machine) |
| **Cluster** | Set of nodes running containerized applications |
| **Control Plane** | Manages cluster (API server, scheduler, controller manager) |
| **Deployment** | Declarative updates for Pods and ReplicaSets |
| **ReplicaSet** | Ensures specified number of pod replicas running |
| **Service** | Abstract way to expose pods as network service |
| **Namespace** | Virtual cluster for resource isolation |
| **ConfigMap** | Store non-sensitive configuration data |
| **Secret** | Store sensitive data (passwords, tokens, keys) |
| **Volume** | Directory accessible to containers in a pod |
| **PersistentVolume (PV)** | Piece of storage in cluster |
| **PersistentVolumeClaim (PVC)** | Request for storage by user |
| **StatefulSet** | Manages stateful applications (unique network IDs, persistent storage) |
| **DaemonSet** | Ensures copy of pod runs on all (or some) nodes |
| **Job** | Creates one or more pods, ensures specified number complete |
| **CronJob** | Job that runs on schedule |
| **Ingress** | Manages external access to services (HTTP/HTTPS routing) |
| **Label** | Key-value pair attached to objects (used for selection) |
| **Selector** | Identifies set of objects by labels |
| **Annotation** | Non-identifying metadata attached to objects |
| **Taint & Toleration** | Node can repel pods unless pod tolerates taint |
| **Affinity** | Rules for pod placement (node affinity, pod affinity) |

---

## Docker Commands

```bash
# Build image
docker build -t go-k8s-api:latest .

# Run container
docker run -p 8080:8080 go-k8s-api:latest

# List images
docker images

# List running containers
docker ps

# Stop container
docker stop <container-id>

# Remove image
docker rmi <image-id>

# View image layers
docker history go-k8s-api:latest

# Inspect image
docker inspect go-k8s-api:latest
```

---

## Kind Commands

```bash
# Create cluster
kind create cluster --name demo

# List clusters
kind get clusters

# Delete cluster
kind delete cluster --name demo

# Load image into cluster
kind load docker-image go-k8s-api:latest --name demo

# Get cluster info
kubectl cluster-info --context kind-demo
```

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Docker Documentation](https://docs.docker.com/)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Go Documentation](https://go.dev/doc/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
