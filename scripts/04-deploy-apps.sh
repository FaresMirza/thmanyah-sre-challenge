#!/bin/bash
set -e

echo "🚀 Deploying Applications via ArgoCD"
echo "====================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster not found. Please run 01-provision-cluster.sh first."
    exit 1
fi

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &> /dev/null; then
    echo "❌ ArgoCD not found. Please run 03-install-argocd.sh first."
    exit 1
fi

# Check if ArgoCD server is ready
if ! kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo "❌ ArgoCD server not found. Please run 03-install-argocd.sh first."
    exit 1
fi

echo "✅ Prerequisites check passed!"
echo ""

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "📦 Applying sealed secrets..."
if [ -f "$REPO_ROOT/infra/thmanyah/db/sealed-secret.yaml" ]; then
    kubectl apply -f "$REPO_ROOT/infra/thmanyah/db/sealed-secret.yaml"
    kubectl apply -f "$REPO_ROOT/infra/thmanyah/api/sealed-secret.yaml"
    kubectl apply -f "$REPO_ROOT/infra/thmanyah/auth/sealed-secret.yaml"
    kubectl apply -f "$REPO_ROOT/infra/thmanyah/image/sealed-secret.yaml"
    kubectl apply -f "$REPO_ROOT/infra/thmanyah/minio/sealed-secret.yaml"
    echo "✅ Sealed secrets applied"
else
    echo "⚠️  No sealed secrets found. You need to create them first."
    echo "   Run: bash scripts/02-create-secrets.sh"
    exit 1
fi

echo ""
echo "📋 Deploying ApplicationSet..."
kubectl apply -f "$REPO_ROOT/infra/thmanyah-applicationset.yaml"

echo ""
echo "⏳ Waiting for pods to be ready..."
sleep 15

# Wait for all pods to be running
TIMEOUT=300  # 5 minutes
INTERVAL=5
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check pod status across all namespaces
    TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E '(api-ns|auth-ns|image-ns|data-ns|minio-ns|ingress-ns)' | wc -l | tr -d ' ')
    RUNNING_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E '(api-ns|auth-ns|image-ns|data-ns|minio-ns|ingress-ns)' | grep -c "Running" || echo 0)
    READY_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E '(api-ns|auth-ns|image-ns|data-ns|minio-ns|ingress-ns)' | grep -E "1/1.*Running" | wc -l | tr -d ' ')
    
    if [ "$TOTAL_PODS" -eq 0 ]; then
        echo "⏳ Waiting for pods to be created..."
    else
        echo "📊 Pods status: $READY_PODS/$TOTAL_PODS ready (${ELAPSED}s elapsed)"
        
        # Check if all pods are ready
        if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
            echo ""
            echo "✅ All pods are running and ready!"
            break
        fi
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo "⚠️  Timeout reached. Some pods may not be ready yet."
    echo "   Check status with: kubectl get pods -A"
    exit 1
fi

echo ""
echo "🎉 Deployment complete!"


