#!/bin/bash
set -e

echo "🚀 Provisioning Kubernetes Cluster with Kind"
echo "=============================================="
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ kind not found. Installing kind..."
    # macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kind
    else
        # Linux
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    fi
    echo "✅ kind installed successfully"
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

echo ""
echo "📋 Creating Kind cluster with custom configuration..."

# Delete existing cluster if it exists
if kind get clusters | grep -q "kind"; then
    echo "⚠️  Existing kind cluster found. Deleting..."
    kind delete cluster
fi

# Create cluster
kind create cluster --config=scripts/config/kind-config.yaml

echo ""
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "🌐 Installing Calico CNI..."

# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Wait for operator to be ready
echo "⏳ Waiting for Calico operator..."
kubectl wait --for=condition=available --timeout=180s deployment/tigera-operator -n tigera-operator

# Install Calico custom resources
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

echo "⏳ Waiting for Calico to be ready..."
# Wait for calico-system namespace
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=180s || true

# Wait for all nodes to be ready with Calico
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo ""
echo "✅ Cluster provisioned successfully!"
echo ""
echo "📊 Cluster Information:"
echo "----------------------"
kubectl cluster-info
echo ""
echo "📦 Nodes:"
kubectl get nodes
echo ""
echo "🌐 Calico Pods:"
kubectl get pods -n calico-system
echo ""
echo "🎉 Setup Complete!"

