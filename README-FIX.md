# Dapr Redis Connection Fix

## Problem
All Fast-Food services in namespace `prod` are in CrashLoopBackOff due to Dapr component initialization failure. The Dapr pubsub component is configured with an incorrect Redis hostname: `redis-ha-haproxy-wrong.redis` (DNS fails with "no such host").

## Solution
The hostname needs to be corrected to: `redis-ha-haproxy.redis`

## Files in This Repository

### `kubernetes/dapr-components/pubsub-redis.yaml`
The corrected Dapr Component manifest with the proper Redis hostname.

### `fix-dapr-redis.sh`
Automated script that:
1. Shows current configuration
2. Applies the corrected Dapr component
3. Restarts all deployments in `prod` namespace
4. Waits for readiness
5. Verifies pod status

## Quick Fix (One-liner)

If you want to apply the fix immediately without the script:

```bash
kubectl apply -f kubernetes/dapr-components/pubsub-redis.yaml && \
kubectl rollout restart deployment -n prod --all
```

## Using the Automated Script

```bash
./fix-dapr-redis.sh
```

The script is interactive and will ask for confirmation before making changes.

## Manual Fix (Step-by-step)

### 1. Verify Current Configuration
```bash
kubectl get component pubsub -n prod -o yaml
```

Look for the `redisHost` metadata field - it should contain `redis-ha-haproxy-wrong.redis:6379`.

### 2. Apply Corrected Configuration
```bash
kubectl apply -f kubernetes/dapr-components/pubsub-redis.yaml
```

### 3. Restart Deployments
```bash
kubectl rollout restart deployment financeservice -n prod
kubectl rollout restart deployment frontendcustomerorderstatus -n prod
kubectl rollout restart deployment frontendkitchenmonitor -n prod
kubectl rollout restart deployment frontendselfservicepos -n prod
kubectl rollout restart deployment kitchenservice -n prod
kubectl rollout restart deployment orderservice -n prod
```

Or restart all at once:
```bash
kubectl rollout restart deployment -n prod --all
```

### 4. Wait for Rollout Completion
```bash
kubectl rollout status deployment/kitchenservice -n prod --timeout=5m
kubectl rollout status deployment/orderservice -n prod --timeout=5m
kubectl rollout status deployment/financeservice -n prod --timeout=5m
kubectl rollout status deployment/frontendcustomerorderstatus -n prod --timeout=5m
kubectl rollout status deployment/frontendkitchenmonitor -n prod --timeout=5m
kubectl rollout status deployment/frontendselfservicepos -n prod --timeout=5m
```

### 5. Verify Pod Status
```bash
kubectl get pods -n prod
```

All pods should be in `Running` state with `2/2` containers ready (application + dapr sidecar).

## Verification

### Check Dapr Sidecar Logs
```bash
kubectl logs -n prod deployment/kitchenservice -c daprd --tail=50
```

Should show successful component initialization without Redis connection errors.

### Test Redis Connectivity
```bash
kubectl run redis-test --rm -i --tty -n prod --image=redis:alpine -- \
  redis-cli -h redis-ha-haproxy.redis -p 6379 ping
```

Expected output: `PONG`

## Expected Timeline
- **Apply fix**: 30 seconds
- **Pod restarts**: 2-3 minutes
- **Full recovery**: 5-10 minutes

## Risk Assessment
**LOW** - This is a simple configuration fix correcting a typo in the hostname. No data loss risk.

## Related Documentation
See `/resolvedissues/2025-11-01T13-12-52-dapr-redis-dns-failure.md` for full incident details and post-incident analysis.
