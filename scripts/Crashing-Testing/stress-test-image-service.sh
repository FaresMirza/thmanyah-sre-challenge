#!/bin/bash

echo "=========================================="
echo "Image Service CPU Stress Test"
echo "=========================================="
echo ""

# Get all image service pods
PODS=$(kubectl get pods -n image-ns -l app=image -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PODS" ]; then
  echo "ERROR: No image service pods found"
  exit 1
fi

echo "Found image service pods:"
for pod in $PODS; do
  echo "  - $pod"
done
echo ""

# Function to stress test a pod
stress_pod() {
  POD=$1
  echo "Starting CPU stress test on pod: $POD"
  
  kubectl exec -n image-ns $POD -- python3 -c '
import multiprocessing
import time
import sys

def cpu_stress():
    """Function to use moderate CPU"""
    end_time = time.time() + 180  # 3 minutes
    while time.time() < end_time:
        # Moderate CPU usage - work for 0.8s, sleep for 0.2s (80% load)
        start = time.time()
        while time.time() - start < 0.8:
            _ = sum(i*i for i in range(10000))
        time.sleep(0.2)

print("Running CPU stress test...")
print("  CPUs: 1")
print("  Load: ~80%")
print("  Duration: 3 minutes")
print()

# Start only 1 process to avoid crashing the cluster
processes = []
for i in range(1):
    p = multiprocessing.Process(target=cpu_stress)
    p.start()
    processes.append(p)
    print(f"Started CPU stress process {i+1}")

# Wait for all processes to complete
for p in processes:
    p.join()

print()
print("CPU stress test completed!")
' &
}

# Start stress test on all pods
echo "Launching CPU stress tests on all image service pods..."
echo ""

for pod in $PODS; do
  stress_pod $pod
done

echo "=========================================="
echo "Stress tests launched!"
echo ""
echo "Monitor with:"
echo "  kubectl get hpa -n image-ns -w"
echo "  kubectl get pods -n image-ns -w"
echo "  kubectl top pods -n image-ns"
echo ""
echo "Waiting for stress tests to complete (3 minutes)..."
echo "=========================================="

# Wait for all background jobs
wait

echo ""
echo "All stress tests completed!"
