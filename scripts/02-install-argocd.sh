#!/bin/bash
set -e

echo "🚀 Installing ArgoCD"
echo "===================="
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

echo "📦 Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "📥 Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ""
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n argocd

echo ""
echo "🔐 Installing Sealed Secrets controller..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

echo "⏳ Waiting for Sealed Secrets controller..."
kubectl wait --for=condition=available --timeout=180s deployment/sealed-secrets-controller -n kube-system

echo ""
echo "📊 Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "⏳ Patching Metrics Server for Kind..."
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

echo "⏳ Increasing Metrics Server resources..."
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/cpu",
    "value": "500m"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "512Mi"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/resources/limits",
    "value": {
      "cpu": "1000m",
      "memory": "1Gi"
    }
  }
]'

echo "⏳ Waiting for Metrics Server..."
kubectl wait --for=condition=available --timeout=180s deployment/metrics-server -n kube-system

echo ""
echo "📈 Installing kube-state-metrics..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/v2.10.1/examples/standard/cluster-role-binding.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/v2.10.1/examples/standard/cluster-role.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/v2.10.1/examples/standard/deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/v2.10.1/examples/standard/service-account.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/v2.10.1/examples/standard/service.yaml

echo "⏳ Waiting for kube-state-metrics..."
kubectl wait --for=condition=available --timeout=360s deployment/kube-state-metrics -n kube-system

echo ""
echo "✅ ArgoCD, Sealed Secrets, Metrics Server, and kube-state-metrics installed successfully!"
echo ""
echo "📊 ArgoCD Pods:"
kubectl get pods -n argocd
echo ""
echo "🔐 Sealed Secrets Pod:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
echo ""
echo "📈 kube-state-metrics Pod:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics
echo ""
echo "🎉 Setup Complete!"

