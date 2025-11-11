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
echo "⏳ Waiting for applications to be created..."
sleep 10

echo ""
echo "📊 Initial ArgoCD Applications Status:"
kubectl get applications -n argocd

# Wait for all applications to sync and become healthy
echo ""
echo "⏳ Waiting for applications to sync and become healthy..."
echo "   This may take several minutes..."
echo ""

TIMEOUT=600  # 10 minutes
INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get application statuses
    APP_STATUS=$(kubectl get applications -n argocd -o json)
    
    # Count total applications
    TOTAL=$(echo "$APP_STATUS" | jq -r '.items | length')
    
    # Count synced and healthy applications
    SYNCED=$(echo "$APP_STATUS" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
    HEALTHY=$(echo "$APP_STATUS" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')
    
    echo "Progress: Synced: $SYNCED/$TOTAL | Healthy: $HEALTHY/$TOTAL (${ELAPSED}s elapsed)"
    
    # Check if all are synced and healthy
    if [ "$SYNCED" -eq "$TOTAL" ] && [ "$HEALTHY" -eq "$TOTAL" ]; then
        echo ""
        echo "✅ All applications are synced and healthy!"
        break
    fi
    
    # Show any applications with issues
    DEGRADED=$(echo "$APP_STATUS" | jq -r '[.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing")] | length')
    if [ "$DEGRADED" -gt 0 ]; then
        echo "⚠️  Applications with issues:"
        echo "$APP_STATUS" | jq -r '.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | "   - \(.metadata.name): \(.status.health.status) - \(.status.sync.status)"'
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo "⚠️  Timeout reached. Some applications may not be fully ready."
fi

echo ""
echo "📊 Final ArgoCD Applications Status:"
kubectl get applications -n argocd

echo ""
echo "✅ Deployment complete!"
