# 🚀 Thmanyah SRE Challenge

This repository contains a production-grade simulation of a multi-service system designed and deployed with Site Reliability Engineering (SRE) principles.  
It demonstrates **high availability**, **security**, **observability**, and **auto-healing** on Kubernetes.

---

## 🧩 1. Overview

The environment consists of:
- **3 microservices:** API, Auth, and Image services (Node.js, Go, Python)
- **2 infrastructure components:** PostgreSQL database and MinIO (S3-compatible storage)
- **Ingress layer:** NGINX ingress controller with TLS termination
- **Monitoring stack:** Prometheus, Alertmanager, and Grafana

All workloads are deployed declaratively on **Kubernetes (kind)** and continuously managed through **ArgoCD (GitOps)**.

---

## 🏗️ 2. System Architecture

### Layers

| Layer | Description | Namespace |
|--------|--------------|------------|
| 🟧 Ingress | Handles all inbound HTTPS traffic | `ingress-ns` |
| 🟩 Application | Hosts API, Auth, and Image services | `api-ns`, `auth-ns`, `image-ns` |
| 🟦 Data | Stores system and user data | `data-ns` |
| 🟣 Monitoring | Observes, visualizes, and alerts on metrics | `monitoring-ns` |

**Flow:**

- Each service is isolated in its own namespace.
- Calico NetworkPolicies strictly control inter-service communication.
- SOPS + AWS KMS secure all credentials.

---

## ⚙️ 3. Deployment Instructions

### Prerequisites

- Docker and kubectl  
- kind (Kubernetes-in-Docker)  
- Helm  
- ArgoCD CLI  
- SOPS configured with AWS KMS key  

### Steps

```bash
# 1️⃣ Create cluster
bash scripts/setup-kind.sh

# 2️⃣ Bootstrap ArgoCD and SOPS integration
bash scripts/bootstrap-argocd.sh

# 3️⃣ Deploy applications (GitOps)
kubectl apply -f argocd/applicationset.yaml

# 4️⃣ Verify
kubectl get pods -A
```

---

## 📡 4. API Endpoints

### Authentication

#### Register User
```bash
curl -X POST http://localhost:3000/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"password123"}'
```

#### Login
```bash
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"password123"}'
```

Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Image Upload & Retrieval

#### Upload Image
```bash
curl -X POST http://localhost:3000/upload \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "file=@image.png"
```

Response:
```json
{
  "message": "Uploaded successfully",
  "filename": "7c393cab-f916-48de-9ce3-480c6c2c158d_image.png",
  "url": "http://localhost:3000/images/7c393cab-f916-48de-9ce3-480c6c2c158d_image.png"
}
```

#### Retrieve Image
```bash
curl -X GET http://localhost:3000/images/7c393cab-f916-48de-9ce3-480c6c2c158d_image.png \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -o downloaded.png
```

**Architecture Flow:**
```
User → API Service (port 3000)
  ↓
  → Auth Service (JWT verification)
  → Image Service (internal)
    → MinIO (S3 storage)
```

**Security:**
- ✅ All requests authenticated via JWT
- ✅ Image service not publicly exposed
- ✅ MinIO accessed only internally
- ✅ File streaming (memory efficient)


