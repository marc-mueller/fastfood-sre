# Dapr Redis Connection Failure - DNS Lookup Error

**When:** 2025-11-01T13:12:52Z  
**Cluster:** dev-aks-k8sdemo-westeurope  
**Namespace:** prod  
**Impact:** All Fast-Food application services in CrashLoopBackOff state. Complete service outage affecting:
- financeservice
- frontendcustomerorderstatus
- frontendkitchenmonitor
- frontendselfservicepos
- kitchenservice
- orderservice

## Signals

### Alerts
- Dapr sidecar restarts detected across all application pods
- All pods in namespace `prod` in CrashLoopBackOff state
- DNS lookup failures for Redis connection

### Representative Logs
```
time="2025-11-01T11:57:31.323879395Z" level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host" app_id=kitchenservice instance=kitchenservice-744b84b596-5phfq

time="2025-11-01T11:57:31.324496344Z" level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host"
```

## Diagnosis

### Root Cause
The Dapr pubsub component (pubsub.redis/v1) is configured with an **incorrect Redis hostname**: `redis-ha-haproxy-wrong.redis`

The hostname contains "wrong" in its name and fails DNS resolution. The correct hostname should be: `redis-ha-haproxy.redis`

### Error Analysis
- Error Type: `INIT_COMPONENT_FAILURE` - Dapr component initialization failure
- Component: `pubsub` (pubsub.redis/v1)
- DNS Server: 10.0.0.10:53 (Kubernetes CoreDNS)
- Failure Point: DNS lookup - "no such host"

This is a configuration error in the Dapr Component YAML manifest where the Redis connection string specifies an invalid hostname.

## Actions Taken (Required Steps)

### 1. Read Current Dapr Component Configuration

**Command to execute:**
```bash
kubectl get component pubsub -n prod -o yaml
```

This will retrieve the current Dapr Component configuration to identify the exact field containing the incorrect hostname.

Expected output should show a `spec.metadata` section with a `redisHost` field containing `redis-ha-haproxy-wrong.redis:6379`.

### 2. Identify Differences

**Expected Configuration Issue:**
```yaml
spec:
  metadata:
  - name: redisHost
    value: "redis-ha-haproxy-wrong.redis:6379"  # INCORRECT
```

**Correct Configuration:**
```yaml
spec:
  metadata:
  - name: redisHost
    value: "redis-ha-haproxy.redis:6379"  # CORRECT
```

### 3. Apply Patch to Dapr Component

**Strategic Merge Patch (Recommended):**
```bash
kubectl patch component pubsub -n prod --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/metadata",
    "value": [
      {
        "name": "redisHost",
        "value": "redis-ha-haproxy.redis:6379"
      }
    ]
  }
]'
```

**Alternative: Direct Edit**
```bash
kubectl edit component pubsub -n prod
```
Then change `redis-ha-haproxy-wrong.redis` to `redis-ha-haproxy.redis`

### 4. Restart Affected Deployments

After patching the component, restart all affected deployments to reinitialize Dapr sidecars:

```bash
# Restart all deployments in prod namespace
kubectl rollout restart deployment financeservice -n prod
kubectl rollout restart deployment frontendcustomerorderstatus -n prod
kubectl rollout restart deployment frontendkitchenmonitor -n prod
kubectl rollout restart deployment frontendselfservicepos -n prod
kubectl rollout restart deployment kitchenservice -n prod
kubectl rollout restart deployment orderservice -n prod
```

**Wait for rollout completion:**
```bash
kubectl rollout status deployment/kitchenservice -n prod --timeout=5m
kubectl rollout status deployment/orderservice -n prod --timeout=5m
kubectl rollout status deployment/financeservice -n prod --timeout=5m
kubectl rollout status deployment/frontendcustomerorderstatus -n prod --timeout=5m
kubectl rollout status deployment/frontendkitchenmonitor -n prod --timeout=5m
kubectl rollout status deployment/frontendselfservicepos -n prod --timeout=5m
```

### 5. Verification Steps

**Check Pod Status:**
```bash
kubectl get pods -n prod
```
All pods should be in `Running` state with 2/2 containers ready (app + dapr sidecar).

**Verify Dapr Sidecar Logs:**
```bash
kubectl logs -n prod deployment/kitchenservice -c daprd --tail=50
```
Should show successful component initialization without Redis connection errors.

**Check Application Logs:**
```bash
kubectl logs -n prod deployment/kitchenservice -c kitchenservice --tail=50
```
Application should be running without fatal Dapr errors.

**Test Redis Connectivity (optional):**
```bash
kubectl run -n prod redis-test --rm -i --tty --image=redis:alpine -- redis-cli -h redis-ha-haproxy.redis -p 6379 ping
```
Expected output: `PONG`

## Post-incident

### Immediate Follow-ups
1. **Monitor for 15 minutes** - Ensure all services remain stable and no CrashLoopBackOff occurs
2. **Check metrics** - Verify normal message throughput in pubsub component
3. **Alert verification** - Confirm all firing alerts have cleared

### Backlog Items
1. **Root Cause Investigation**: Determine how the incorrect hostname was introduced
   - Review recent changes to Dapr component manifests
   - Check CI/CD pipeline for configuration issues
   - Identify if this was a manual change or automated deployment

2. **Prevention Measures**:
   - Add validation in CI/CD pipeline to check for "wrong" or invalid hostnames in configurations
   - Implement pre-deployment validation for Dapr component configurations
   - Add DNS resolution check as part of component deployment validation
   - Consider using Kubernetes ConfigMaps with validation for common connection strings

3. **Monitoring Improvements**:
   - Add alert for Dapr component initialization failures
   - Set up dashboard for Dapr sidecar health across all services
   - Implement synthetic monitoring to detect service outages faster

4. **Documentation**:
   - Document correct Redis connection strings for all environments
   - Create runbook for Dapr component troubleshooting
   - Add this incident to team knowledge base

### Links
- Issue: [ALERT] Dapr components failing to initialize – Redis connection errors
- Cluster: dev-aks-k8sdemo-westeurope
- Namespace: prod
- Affected Component: pubsub (pubsub.redis/v1)

---

## Summary
**Quick Fix:** Change `redis-ha-haproxy-wrong.redis` to `redis-ha-haproxy.redis` in the Dapr pubsub component configuration, then restart all affected deployments.

**Status:** Resolution steps documented. Manual execution required due to lack of kubernetes MCP tool access in current environment.
