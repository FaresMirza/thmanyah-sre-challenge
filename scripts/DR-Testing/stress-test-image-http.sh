#!/bin/bash

echo "=========================================="
echo "Image Service HTTP Stress Test (In-Pod)"
echo "=========================================="
echo ""

# Get all image service pods dynamically
get_pods() {
  kubectl get pods -n image-ns -l app=image -o jsonpath='{.items[*].metadata.name}'
}

PODS=$(get_pods)

if [ -z "$PODS" ]; then
  echo "ERROR: No image service pods found"
  exit 1
fi

echo "Found image service pods:"
for pod in $PODS; do
  echo "  - $pod"
done
echo ""

# Function to stress test a pod with HTTP requests
stress_pod() {
  POD=$1
  echo "Starting HTTP stress test on pod: $POD"
  
  kubectl exec -n image-ns $POD -- python3 -c '
import time
import sys
from urllib.request import urlopen, Request
from urllib.error import URLError
import multiprocessing

def http_stress():
    """Make steady HTTP requests to generate moderate CPU load"""
    end_time = time.time() + 70  # 1 minute 10 seconds
    count = 0
    errors = 0
    
    while time.time() < end_time:
        try:
            # Make request to local service
            req = Request("http://localhost:5000/healthz")
            with urlopen(req, timeout=2) as response:
                _ = response.read()
            count += 1
        except (URLError, Exception) as e:
            errors += 1
        
        # Light delay for ~90-100% CPU target - ~25 requests/sec per process
        time.sleep(0.04)
    
    print(f"Process completed: {count} requests, {errors} errors")

print("Running HTTP stress test...")
print("  Target: http://localhost:5000/healthz")
print("  Processes: 2 (tuned for 90-100% CPU)")
print("  Rate: ~50 requests/sec per pod")
print("  Duration: 1 minute 10 seconds")
print()

# Start 2 processes tuned for 90-100% CPU utilization
processes = []
for i in range(2):
    p = multiprocessing.Process(target=http_stress)
    p.start()
    processes.append(p)
    print(f"Started HTTP stress process {i+1}")

# Wait for all processes to complete
for p in processes:
    p.join()

print()
print("HTTP stress test completed!")
' &
}

# Start stress test on all pods in background
echo "Launching HTTP stress tests on all image service pods..."
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

# Monitor for new pods every 5 seconds and stress them too
echo "Monitoring for newly scaled pods..."
echo "Will automatically stress new pods as they appear"
echo "Press Ctrl+C to stop monitoring"
echo "=========================================="
echo ""

INITIAL_PODS="$PODS"

while true; do
  sleep 5
  
  # Get current pods
  CURRENT_PODS=$(get_pods)
  
  # Find new pods
  for pod in $CURRENT_PODS; do
    if ! echo "$INITIAL_PODS" | grep -q "$pod"; then
      echo "NEW POD DETECTED: $pod"
      echo "Waiting for pod to be ready..."
      
      # Wait for pod to be ready (timeout after 60s)
      if kubectl wait --for=condition=Ready pod/$pod -n image-ns --timeout=60s 2>/dev/null; then
        echo "Pod is ready! Starting stress test..."
        stress_pod $pod
        INITIAL_PODS="$INITIAL_PODS $pod"
      else
        echo "Warning: Pod $pod did not become ready in time, will retry next cycle"
      fi
    fi
  done
done
