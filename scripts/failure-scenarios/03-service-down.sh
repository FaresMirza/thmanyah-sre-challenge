#!/usr/bin/env bash
set -euo pipefail

# 03-service-down.sh
# Simple script to simulate service failure by scaling Deployment to 0

SERVICE=${1:-}

if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service-name>"
  echo ""
  echo "Available services:"
  echo "  api    - Scale down API service"
  echo "  auth   - Scale down Auth service"
  echo "  image  - Scale down Image service"
  echo ""
  echo "Example: $0 api"
  exit 1
fi

case "$SERVICE" in
  api)
    DEPLOYMENT="api"
    NAMESPACE="api-ns"
    ;;
  auth)
    DEPLOYMENT="auth"
    NAMESPACE="auth-ns"
    ;;
  image)
    DEPLOYMENT="image"
    NAMESPACE="image-ns"
    ;;
  *)
    echo "❌ Unknown service: $SERVICE"
    echo "Available: api, auth, image"
    exit 1
    ;;
esac

echo "🔴 Simulating $SERVICE Service Failure..."
echo "Scaling $DEPLOYMENT deployment to 0 replicas in $NAMESPACE namespace"

kubectl scale deployment "$DEPLOYMENT" --replicas=0 -n "$NAMESPACE"

echo "✅ $SERVICE service is now DOWN"
echo ""
echo "To recover, run:"
echo "  kubectl scale deployment $DEPLOYMENT --replicas=2 -n $NAMESPACE"
echo ""
echo "Or let HPA auto-scale it back based on load"
