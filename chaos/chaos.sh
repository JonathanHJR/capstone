#!/bin/bash

NAMESPACE="default"
DEPLOYMENT="calorie-tracker"
INTERVAL=30

echo "Starting chaos engineering against $DEPLOYMENT"
echo "Killing a random pod every $INTERVAL seconds. Press Ctrl+C to stop."
echo ""

while true; do
  POD=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | shuf -n 1)

  if [ -z "$POD" ]; then
    echo "No running pods found. Waiting..."
  else
    echo "[$(date +%H:%M:%S)] Killing pod: $POD"
    kubectl delete pod $POD -n $NAMESPACE

    echo "[$(date +%H:%M:%S)] Waiting for recovery..."
    kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=60s
    echo "[$(date +%H:%M:%S)] Recovery confirmed. Pods running:"
    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT
    echo ""
  fi

  sleep $INTERVAL
done
