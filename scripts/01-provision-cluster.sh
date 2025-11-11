#!/bin/bash
set -e

echo "🚀 Provisioning Kubernetes Cluster with Kind"
echo "=============================================="
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ kind not found. Installing kind..."
    
    # Detect OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "📦 Detected macOS"
        
        # Check if Homebrew is available
        if command -v brew &> /dev/null; then
            echo "Installing kind via Homebrew..."
            brew install kind
        else
            echo "⚠️  Homebrew not found."
            echo ""
            read -p "Do you want to (1) Install Homebrew and kind, or (2) Install kind binary directly? [1/2]: " choice
            
            if [ "$choice" = "1" ]; then
                echo "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                
                # Add Homebrew to PATH for Apple Silicon Macs
                if [[ $(uname -m) == "arm64" ]]; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                else
                    echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                
                brew install kind
            elif [ "$choice" = "2" ]; then
                echo "Installing kind binary directly..."
                # Detect architecture
                if [[ $(uname -m) == "arm64" ]]; then
                    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-arm64
                else
                    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-amd64
                fi
                chmod +x ./kind
                sudo mv ./kind /usr/local/bin/kind
            else
                echo "❌ Invalid choice. Please run the script again."
                exit 1
            fi
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "📦 Detected Linux - Installing kind binary..."
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
        # Windows (Git Bash, Cygwin, or native)
        echo "❌ Windows detected. Please install kind manually:"
        echo "   Using Chocolatey: choco install kind"
        echo "   Or download from: https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries"
        exit 1
    else
        echo "❌ Unsupported OS: $OSTYPE"
        echo "   Please install kind manually from: https://kind.sigs.k8s.io/docs/user/quick-start/"
        exit 1
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

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Delete existing cluster if it exists
if kind get clusters | grep -q "kind"; then
    echo "⚠️  Existing kind cluster found. Deleting..."
    kind delete cluster
fi

# Create cluster
kind create cluster --config="${SCRIPT_DIR}/config/kind-config.yaml"

echo ""
echo "🌐 Installing Calico CNI..."

# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Wait for operator pod to exist and start pulling image
echo "⏳ Waiting for Calico operator pod..."
sleep 10
kubectl wait --for=condition=Ready pod -l k8s-app=tigera-operator -n tigera-operator --timeout=300s

# Wait for operator deployment to be ready
echo "⏳ Waiting for Calico operator deployment..."
kubectl wait --for=condition=available --timeout=180s deployment/tigera-operator -n tigera-operator

# Install Calico custom resources
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

echo "⏳ Waiting for Calico pods to be ready..."
# Wait for namespaces to be created
timeout=120
counter=0
until kubectl get namespace calico-system &> /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo ""
        echo "❌ Timeout waiting for calico-system namespace"
        echo "Checking tigera-operator logs:"
        kubectl logs -n tigera-operator -l k8s-app=tigera-operator --tail=50
        exit 1
    fi
    if [ $((counter % 10)) -eq 0 ]; then
        echo "Waiting for calico-system namespace... (${counter}s/${timeout}s)"
    fi
    sleep 5
    ((counter+=5))
done

# Wait for calico-system pods
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=300s

# Wait for calico-apiserver if it exists
if kubectl get namespace calico-apiserver &> /dev/null; then
    kubectl wait --for=condition=Ready pods --all -n calico-apiserver --timeout=300s || true
fi

echo ""
echo "⏳ Waiting for all nodes to be ready..."
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

