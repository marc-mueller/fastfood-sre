# Dapr Components Redis Connection Failure - Incorrect Hostname

**When:** 2025-11-01T20:28:34Z  
**Cluster:** dev-aks-k8sdemo-westeurope  
**Namespace:** prod  
**Impact:** All Fast-Food application services in CrashLoopBackOff due to Dapr sidecar initialization failures. Services affected: `financeservice`, `frontendcustomerorderstatus`, `frontendkitchenmonitor`, `frontendselfservicepos`, `kitchenservice`, `orderservice`

## Signals

### Key Alerts
- Monitoring system detected repeated Dapr sidecar restarts
- All pods in namespace `prod` showing `1/2 READY` status (application container up, Dapr sidecar failing)
- CrashLoopBackOff status across all services with restart counts over 100

### Representative Logs
```
time="2025-11-01T11:57:31.323879395Z" level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host" app_id=kitchenservice instance=kitchenservice-744b84b596-5phfq

time="2025-11-01T11:57:31.324496344Z" level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host"
```

## Diagnosis

### Root Cause
Dapr components (`pubsub` and `statestore`) were configured with an incorrect Redis hostname: `redis-ha-haproxy-wrong.redis:6379`

The hostname contained `-wrong` suffix, causing DNS lookups to fail with "no such host" errors. This prevented Dapr sidecars from initializing, causing all pods to enter CrashLoopBackOff.

### Components Affected
1. **pubsub** (pubsub.redis/v1) - Used for pub/sub messaging between services
2. **statestore** (state.redis/v1) - Used for state storage and actor state

Both components had the incorrect `redisHost` metadata value.

## Actions Taken (in order)

### 1. Read Current Live Configuration
```bash
kubectl get component pubsub -n prod -o yaml
kubectl get component statestore -n prod -o yaml
```

**Finding:** Both components showed:
```yaml
spec:
  metadata:
  - name: redisHost
    value: redis-ha-haproxy-wrong.redis:6379
```

### 2. Differences Found
- Current (incorrect): `redis-ha-haproxy-wrong.redis:6379`
- Expected (correct): `redis-ha-haproxy.redis:6379`
- Difference: Remove `-wrong` suffix from hostname

### 3. Exact Patches Applied

**Patch pubsub component:**
```bash
kubectl patch component pubsub -n prod --type=json -p '[{"op": "replace", "path": "/spec/metadata/0/value", "value": "redis-ha-haproxy.redis:6379"}]'
```
Result: `component.dapr.io/pubsub patched`

**Patch statestore component:**
```bash
kubectl patch component statestore -n prod --type=json -p '[{"op": "replace", "path": "/spec/metadata/0/value", "value": "redis-ha-haproxy.redis:6379"}]'
```
Result: `component.dapr.io/statestore patched`

**Verification:**
```bash
kubectl get component pubsub -n prod -o jsonpath='{.spec.metadata[?(@.name=="redisHost")].value}'
# Output: redis-ha-haproxy.redis:6379

kubectl get component statestore -n prod -o jsonpath='{.spec.metadata[?(@.name=="redisHost")].value}'
# Output: redis-ha-haproxy.redis:6379
```

### 4. Restarts & Readiness Checks

**Restart all affected deployments to reload Dapr sidecars:**
```bash
kubectl rollout restart deployment financeservice -n prod
kubectl rollout restart deployment frontendcustomerorderstatus -n prod
kubectl rollout restart deployment frontendkitchenmonitor -n prod
kubectl rollout restart deployment frontendselfservicepos -n prod
kubectl rollout restart deployment kitchenservice -n prod
kubectl rollout restart deployment orderservice -n prod
```

All deployments successfully restarted.

**Pod Status After 30 Seconds:**
```
NAME                                           READY   STATUS    RESTARTS   AGE
financeservice-664595b986-6fxf8                2/2     Running   0          46s
frontendcustomerorderstatus-848cc85499-s4zmx   2/2     Running   0          46s
frontendkitchenmonitor-6576fc5649-dj4mf        2/2     Running   0          46s
frontendselfservicepos-bb799cc7d-cp9cf         2/2     Running   0          46s
kitchenservice-6777df776d-xc9g6                2/2     Running   0          46s
orderservice-57c894cd5c-zzwb5                  2/2     Running   0          46s
```

All pods now show `2/2 READY` (application + Dapr sidecar healthy).

### 5. Verification (Logs/Endpoints)

**Checked Dapr sidecar logs for successful initialization:**
```bash
kubectl logs kitchenservice-6777df776d-xc9g6 -n prod -c daprd --tail=100
```

**Key Success Indicators:**
```
time="2025-11-01T20:31:09.624476582Z" level=info msg="Component loaded: pubsub (pubsub.redis/v1)" app_id=kitchenservice
time="2025-11-01T20:31:09.73795743Z" level=info msg="Component loaded: statestore (state.redis/v1)" app_id=kitchenservice
time="2025-11-01T20:31:12.99712311Z" level=info msg="dapr initialized. Status: Running. Init Elapsed 3474ms" app_id=kitchenservice
time="2025-11-01T20:31:12.998341319Z" level=info msg="Scheduler stream connected" app_id=kitchenservice
```

No errors about Redis connection failures. All Dapr components initialized successfully.

## Post-incident

### Resolution Summary
- **Time to Resolution:** ~3 minutes from start of investigation
- **Downtime:** Services were already down for 8+ hours before remediation
- **Service Restored:** All 6 services now running healthy with 2/2 containers ready

### Follow-ups / Backlog Items
1. **Root Cause Investigation:** Determine how the incorrect hostname (`-wrong` suffix) was introduced into the Dapr component configurations
2. **Configuration Validation:** Implement pre-deployment validation to catch invalid DNS hostnames in component configurations
3. **Monitoring Enhancement:** Add specific alerts for Dapr component initialization failures to detect issues faster
4. **GitOps Review:** If these components are managed via GitOps/Helm, audit the source configuration to ensure it doesn't contain the incorrect value
5. **Runbook Creation:** Create runbook entry for this error pattern in the fastfoodmcp knowledge base

### Links to PRs
- This incident resolution: [PR created via copilot/fix-dapr-redis-connection branch]
