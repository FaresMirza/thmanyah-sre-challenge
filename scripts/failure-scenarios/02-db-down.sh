#!/usr/bin/env bash
set -euo pipefail

# 02-db-down.sh
# Simple script to simulate database failure by scaling StatefulSet to 0

echo "🔴 Simulating Database Failure..."
echo "Scaling db StatefulSet to 0 replicas in data-ns namespace"

kubectl scale statefulset db --replicas=0 -n data-ns

echo "✅ Database is now DOWN"
echo ""
echo "To recover, run:"
echo "  kubectl scale statefulset db --replicas=1 -n data-ns"
