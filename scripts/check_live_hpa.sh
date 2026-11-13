#!/bin/bash

# NOTE: This script is intended to be run in a separate terminal
# window to continuously check the status of the Horizontal Pod Autoscaler (HPA)

NAMESPACE="devops-task"
INTERVAL=5

echo "TIMESTAMP $(kubectl get hpa -n "$NAMESPACE" --no-headers | head -1 | awk '{print "NAME REFERENCE TARGETS MINPODS MAXPODS REPLICAS"}')"

while true; do
    kubectl get hpa -n "$NAMESPACE" --no-headers | while read -r line; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
    done
    sleep "$INTERVAL"
done
