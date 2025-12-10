# Dapr Redis Connection Failure - Incorrect Hostname Configuration

**When:** 2025-12-10T09:23:00Z  
**Cluster:** dev-aks-k8sdemo-westeurope  
**Namespace:** prod  
**Impact:** All Fast-Food application pods in CrashLoopBackOff state. Services unable to initialize Dapr sidecars due to pubsub component failure. User-facing services completely unavailable.

## Signals
- All 6 application pods showing 1/2 READY status in CrashLoopBackOff
- Affected services: `financeservice`, `frontendcustomerorderstatus`, `frontendkitchenmonitor`, `frontendselfservicepos`, `kitchenservice`, `orderservice`
- Dapr sidecar restart count: 29 restarts per pod over 126 minutes
- Representative logs:
```
time="2025-12-10T09:18:14.93704703Z" level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host" app_id=kitchenservice instance=kitchenservice-f5c77889d-ppt6r

time="2025-12-10T09:18:14.937090302Z" level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1)"
```

## Diagnosis
**Root Cause:** The Dapr `pubsub` component had an incorrect Redis hostname configured: `redis-ha-haproxy-wrong.redis:6379`

**Discovery:** 
1. Retrieved current configuration of all Dapr components in the `prod` namespace
2. Compared `pubsub` component configuration with `statestore` component configuration
3. Identified that `statestore` component used the correct hostname: `redis-ha-haproxy.redis:6379`
4. The typo ("wrong" appended to hostname) caused DNS resolution failures

**fastfoodmcp references:** None available - error code INIT_COMPONENT_FAILURE not in knowledge base

## Actions Taken (in order)

### 1. Initial Investigation
```bash
kubectl get pods -n prod
kubectl get components -n prod
kubectl logs -n prod kitchenservice-f5c77889d-ppt6r -c daprd --tail=50
```
**Result:** Confirmed all 6 services in CrashLoopBackOff with identical error pattern pointing to incorrect Redis hostname

### 2. Configuration Analysis
```bash
kubectl get component pubsub -n prod -o yaml
kubectl get component statestore -n prod -o yaml
```
**Differences Found:**
- **pubsub component:** `redisHost: redis-ha-haproxy-wrong.redis:6379` ❌
- **statestore component:** `redisHost: redis-ha-haproxy.redis:6379` ✅

### 3. Applied Configuration Fix
```bash
kubectl patch component pubsub -n prod --type json -p '[{"op": "replace", "path": "/spec/metadata/0/value", "value": "redis-ha-haproxy.redis:6379"}]'
```
**Result:** `component.dapr.io/pubsub patched`

**Verification:**
```bash
kubectl get component pubsub -n prod -o jsonpath='{.spec.metadata[0]}'
```
**Output:** `{"name":"redisHost","value":"redis-ha-haproxy.redis:6379"}` ✅

### 4. Restarted All Affected Workloads
```bash
kubectl rollout restart deployment financeservice -n prod
kubectl rollout restart deployment frontendcustomerorderstatus -n prod
kubectl rollout restart deployment frontendkitchenmonitor -n prod
kubectl rollout restart deployment frontendselfservicepos -n prod
kubectl rollout restart deployment kitchenservice -n prod
kubectl rollout restart deployment orderservice -n prod
```
**Result:** All 6 deployments restarted successfully

### 5. Readiness Verification (waited 30 seconds)
```bash
kubectl get pods -n prod
```
**Result:** All pods showing 2/2 READY status
```
NAME                                           READY   STATUS    RESTARTS   AGE
financeservice-bdf869cb9-wdfzt                 2/2     Running   0          47s
frontendcustomerorderstatus-65b74cc99f-jxkxn   2/2     Running   0          46s
frontendkitchenmonitor-5d545995b9-5tfvm        2/2     Running   0          46s
frontendselfservicepos-7499b5c97d-cmtzs        2/2     Running   0          47s
kitchenservice-d479649b-n6b5j                  2/2     Running   0          46s
orderservice-6d76b59f59-bkdgt                  2/2     Running   0          46s
```

### 6. Log Verification
Checked logs from `kitchenservice` and `orderservice` Dapr sidecars:
```bash
kubectl logs -n prod kitchenservice-d479649b-n6b5j -c daprd --tail=30
kubectl logs -n prod orderservice-6d76b59f59-bkdgt -c daprd --tail=30
```

**Key Success Indicators:**
- ✅ `"dapr initialized. Status: Running. Init Elapsed 462ms"` (kitchenservice)
- ✅ `"dapr initialized. Status: Running. Init Elapsed 475ms"` (orderservice)
- ✅ `"app is subscribed to the following topics: [...] through pubsub=pubsub"` 
- ✅ No fatal errors or component initialization failures
- ✅ Pubsub component successfully initialized and operational

## Post-incident

### Follow-ups
1. **Configuration Management Review:** Investigate how the incorrect hostname was introduced into the `pubsub` component configuration (generation: 7, indicating it was modified 7 times)
2. **Monitoring Enhancement:** Add alerting for Dapr component initialization failures to reduce MTTR
3. **Infrastructure-as-Code:** If not already in place, implement GitOps or Terraform to manage Dapr component configurations and prevent manual configuration drift
4. **Validation Testing:** Consider adding smoke tests that validate connectivity to Redis from Dapr components in pre-production environments
5. **Documentation:** Add this common failure pattern to the internal runbook/knowledge base for faster resolution

### Resolution Summary
- **MTTR:** ~5 minutes (from incident detection to service restoration)
- **Root Cause:** Typo in Dapr component configuration (`redis-ha-haproxy-wrong.redis`)
- **Resolution:** Single-line JSON patch to correct the hostname
- **Impact Duration:** 126+ minutes before remediation
- **Services Restored:** All 6 Fast-Food services fully operational

### Links
- PR: (This resolution)
- Related Incident: `/resolvedissues/2025-11-01T2028-dapr-redis-connection-failure.md` (possibly similar root cause)
