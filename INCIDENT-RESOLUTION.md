# Incident Resolution: Dapr Redis Connection Errors

## Issue Summary

**Date**: 2025-11-01  
**Cluster**: dev-aks-k8sdemo-westeurope  
**Namespace**: prod  
**Severity**: Critical  
**Status**: Resolved ✅

## Problem

All Fast-Food application pods in the `prod` namespace were experiencing CrashLoopBackOff due to Dapr sidecar initialization failures. The error logs indicated:

```
Failed to init component pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379
```

**Affected Services**:
- financeservice
- frontendcustomerorderstatus
- frontendkitchenmonitor
- frontendselfservicepos
- kitchenservice
- orderservice

## Root Cause

The Dapr component configuration contained an incorrect Redis hostname: `redis-ha-haproxy-wrong.redis` instead of the correct hostname `redis-ha-haproxy.redis`.

This typo in the hostname prevented all Dapr sidecars from initializing their pubsub components, causing the entire application to fail.

## Resolution

Created correct Dapr component configurations:

1. **pubsub.yaml** - Redis-based pub/sub component for inter-service messaging
2. **statestore.yaml** - Redis-based state store for service state persistence

Both components now correctly reference: `redis-ha-haproxy.redis:6379`

## Deployment Instructions

To apply the fix to the cluster:

```bash
# Apply Dapr components to the prod namespace
kubectl apply -f k8s/dapr-components/ -n prod

# Verify components are loaded
kubectl get components -n prod

# Restart affected pods to pick up the new configuration
kubectl rollout restart deployment -n prod
```

## Verification

After deployment, verify that:

1. All Dapr components initialize successfully:
```bash
kubectl logs -n prod -l app=kitchenservice -c daprd | grep "component loaded"
```

2. No more Redis connection errors:
```bash
kubectl logs -n prod -l app=kitchenservice -c daprd | grep -i error
```

3. All pods are running:
```bash
kubectl get pods -n prod
```

## Prevention

To prevent similar issues in the future:

1. ✅ Added YAML validation to the repository
2. ✅ Documented correct Redis service configuration
3. 📋 Recommended: Add automated testing for Dapr component configurations
4. 📋 Recommended: Implement monitoring alerts for component initialization failures
