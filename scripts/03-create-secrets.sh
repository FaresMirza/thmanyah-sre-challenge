#!/bin/bash
set -e

echo "🔐 Creating Sealed Secrets"
echo "=========================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "❌ kubeseal not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install kubeseal
        else
            echo "❌ Please install Homebrew or download kubeseal manually from:"
            echo "   https://github.com/bitnami-labs/sealed-secrets/releases"
            exit 1
        fi
    else
        echo "❌ Please install kubeseal manually from:"
        echo "   https://github.com/bitnami-labs/sealed-secrets/releases"
        exit 1
    fi
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster not found. Please run 01-provision-cluster.sh first."
    exit 1
fi

# Check if sealed-secrets controller is running
if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
    echo "❌ Sealed Secrets controller not found. Please run 02-install-argocd.sh first."
    exit 1
fi

echo "✅ Prerequisites check passed!"
echo ""

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to create and seal a secret
create_sealed_secret() {
    local name=$1
    local namespace=$2
    local output_file=$3
    shift 3
    local literals=("$@")
    
    echo "Creating sealed secret: $name in namespace $namespace"
    
    # Create namespace if it doesn't exist
    kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f - &> /dev/null
    
    # Build kubectl command
    cmd="kubectl create secret generic $name --namespace=$namespace --dry-run=client -o yaml"
    for literal in "${literals[@]}"; do
        cmd="$cmd --from-literal=$literal"
    done
    
    # Create and seal the secret
    eval $cmd | kubeseal -o yaml > $output_file
    echo "✅ Created: $output_file"
}

echo "📝 Creating sealed secrets with default values..."
echo ""

# Database secret - using default values
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Database Secret (namespace: data-ns)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
POSTGRES_USER="admin"
POSTGRES_PASSWORD="changeme"
POSTGRES_DB="thmanyah"
echo "Using defaults: POSTGRES_USER=$POSTGRES_USER, POSTGRES_DB=$POSTGRES_DB"

create_sealed_secret "db-secret" "data-ns" "$REPO_ROOT/infra/thmanyah/db/sealed-secret.yaml" \
    "POSTGRES_USER=$POSTGRES_USER" \
    "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    "POSTGRES_DB=$POSTGRES_DB"

echo ""

# MinIO secret - using default values
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗄️  MinIO Secret (namespace: minio-ns)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"
echo "Using defaults: MINIO_ROOT_USER=$MINIO_ROOT_USER"

create_sealed_secret "minio-secret" "minio-ns" "$REPO_ROOT/infra/thmanyah/minio/sealed-secret.yaml" \
    "MINIO_ROOT_USER=$MINIO_ROOT_USER" \
    "MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD"

echo ""

# JWT Secret (used by both API and Auth) - generate automatically
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 JWT Secret (shared between API and Auth)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
JWT_SECRET=$(openssl rand -hex 32)
echo "✅ Generated random JWT_SECRET"

# Auth secret
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Auth Service Secret (namespace: auth-ns)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@db.data-ns.svc.cluster.local:5432/$POSTGRES_DB?sslmode=disable"
echo "Database URL: $DATABASE_URL"

create_sealed_secret "auth-secret" "auth-ns" "$REPO_ROOT/infra/thmanyah/auth/sealed-secret.yaml" \
    "JWT_SECRET=$JWT_SECRET" \
    "DATABASE_URL=$DATABASE_URL"

echo ""

# API secret
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 API Service Secret (namespace: api-ns)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
create_sealed_secret "api-secret" "api-ns" "$REPO_ROOT/infra/thmanyah/api/sealed-secret.yaml" \
    "JWT_SECRET=$JWT_SECRET" \
    "DATABASE_URL=$DATABASE_URL" \
    "AUTH_SERVICE_URL=http://auth-service.auth-ns.svc.cluster.local:4000" \
    "IMAGE_SERVICE_URL=http://image-service.image-ns.svc.cluster.local:8000"

echo ""

# Image secret
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖼️  Image Service Secret (namespace: image-ns)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
create_sealed_secret "image-secret" "image-ns" "$REPO_ROOT/infra/thmanyah/image/sealed-secret.yaml" \
    "MINIO_ENDPOINT=minio-service.minio-ns.svc.cluster.local:9000" \
    "MINIO_ACCESS_KEY=$MINIO_ROOT_USER" \
    "MINIO_SECRET_KEY=$MINIO_ROOT_PASSWORD"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 All sealed secrets created successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary of created secrets:"
echo "   ✅ $REPO_ROOT/infra/thmanyah/db/sealed-secret.yaml"
echo "   ✅ $REPO_ROOT/infra/thmanyah/minio/sealed-secret.yaml"
echo "   ✅ $REPO_ROOT/infra/thmanyah/auth/sealed-secret.yaml"
echo "   ✅ $REPO_ROOT/infra/thmanyah/api/sealed-secret.yaml"
echo "   ✅ $REPO_ROOT/infra/thmanyah/image/sealed-secret.yaml"
echo ""
echo "💡 These secrets are encrypted and safe to commit to Git!"
