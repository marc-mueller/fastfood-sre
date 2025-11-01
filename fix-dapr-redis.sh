#!/bin/bash
#
# Script to fix Dapr Redis connection issue
# Issue: redis-ha-haproxy-wrong.redis -> redis-ha-haproxy.redis
#
# Usage: ./fix-dapr-redis.sh
#

set -e

NAMESPACE="prod"
COMPONENTS=("pubsub" "statestore")

echo "======================================"
echo "Dapr Redis Connection Fix"
echo "======================================"
echo ""
echo "This script will:"
echo "1. Show current Dapr component configurations"
echo "2. Apply the corrected configurations for both pubsub and statestore"
echo "3. Restart all deployments in namespace: $NAMESPACE"
echo "4. Wait for deployments to be ready"
echo "5. Verify pod status"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "[1/5] Current Dapr component configurations:"
echo "-------------------------------------------"
for component in "${COMPONENTS[@]}"; do
    echo "Component: $component"
    kubectl get component $component -n $NAMESPACE -o yaml 2>/dev/null || echo "  Component $component not found (will be created)"
    echo ""
done

echo ""
echo "[2/5] Applying corrected configurations..."
echo "-------------------------------------------"
kubectl apply -f kubernetes/dapr-components/pubsub-redis.yaml
kubectl apply -f kubernetes/dapr-components/statestore-redis.yaml

echo ""
echo "[3/5] Restarting deployments in namespace: $NAMESPACE..."
echo "-------------------------------------------"
for deployment in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    echo "  Restarting deployment: $deployment"
    kubectl rollout restart deployment/$deployment -n $NAMESPACE
done

echo ""
echo "[4/5] Waiting for deployments to be ready..."
echo "-------------------------------------------"
for deployment in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    echo "  Waiting for: $deployment"
    kubectl rollout status deployment/$deployment -n $NAMESPACE --timeout=5m
done

echo ""
echo "[5/5] Verifying pod status..."
echo "-------------------------------------------"
kubectl get pods -n $NAMESPACE

echo ""
echo "======================================"
echo "Fix completed!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Monitor pods for 15 minutes to ensure stability"
echo "2. Check application logs for any errors"
echo "3. Verify Redis connectivity:"
echo "   kubectl run redis-test --rm -i --tty -n $NAMESPACE --image=redis:alpine -- redis-cli -h redis-ha-haproxy.redis -p 6379 ping"
echo ""
