# Dapr Component Redis Connection Failure - All Services in CrashLoopBackOff

**When:** 2025-11-05T14:36:58Z  
**Cluster:** dev-aks-k8sdemo-westeurope  
**Namespace:** prod  
**Impact:** All Fast-Food application services were unavailable due to Dapr sidecar initialization failures. Services affected: `financeservice`, `frontendcustomerorderstatus`, `frontendkitchenmonitor`, `frontendselfservicepos`, `kitchenservice`, `orderservice`. All pods were in CrashLoopBackOff state with 1/2 containers ready.

## Signals
- **Monitoring Alert**: Repeated Dapr sidecar restarts detected
- **Pod Status**: All 6 application pods in CrashLoopBackOff state (1/2 Ready)
- **Restart Count**: 37-38 restarts per pod over 170 minutes
- **Key Log Pattern**:
```
level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: 
initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to 
redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 
10.0.0.10:53: no such host"

level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]"
```

## Diagnosis
**Root Cause**: Incorrect Redis hostname configured in Dapr components.

The `pubsub` and `statestore` Dapr components were configured with an invalid Redis hostname:
- **Incorrect hostname**: `redis-ha-haproxy-wrong.redis:6379`
- **Correct hostname**: `redis-ha-haproxy.redis:6379`

The hostname contained the suffix "-wrong" which caused DNS resolution failures. When Dapr sidecars attempted to initialize the pubsub and statestore components, they could not resolve the hostname, leading to fatal initialization errors and pod crashes.

**Affected Components**:
1. `pubsub` (type: pubsub.redis/v1) - used by all services for pub/sub messaging
2. `statestore` (type: state.redis/v1) - used by all services for state management

## Actions Taken (in order)

### 1. Initial Investigation
```bash
kubectl get pods -n prod
```
Confirmed all 6 application pods in CrashLoopBackOff state with 1/2 containers ready.

### 2. Examined Dapr Component Configuration
```bash
kubectl get component pubsub -n prod -o yaml
kubectl get component statestore -n prod -o yaml
```
Identified incorrect Redis hostname `redis-ha-haproxy-wrong.redis:6379` in both components.

### 3. Verified Error in Pod Logs
```bash
kubectl logs kitchenservice-6777df776d-752xh -n prod -c daprd --tail=50
```
Confirmed DNS lookup failure for the incorrect hostname.

### 4. Fixed pubsub Component
The pubsub component was already corrected (hostname already showed `redis-ha-haproxy.redis:6379`).
Verified with:
```bash
kubectl get component pubsub -n prod -o jsonpath='{.spec.metadata[?(@.name=="redisHost")].value}'
```
Result: `redis-ha-haproxy.redis:6379` ✓

### 5. Fixed statestore Component
Applied JSON patch to correct the Redis hostname:
```bash
kubectl patch components statestore -n prod --type=json \
  -p '[{"op":"replace","path":"/spec/metadata/0/value","value":"redis-ha-haproxy.redis:6379"}]'
```
Result: `component.dapr.io/statestore patched`

Verified the change:
```bash
kubectl get component statestore -n prod -o jsonpath='{.spec.metadata[?(@.name=="redisHost")].value}'
```
Result: `redis-ha-haproxy.redis:6379` ✓

### 6. Restarted All Affected Deployments
Performed rollout restart for all services to pick up the corrected Dapr component configuration:
```bash
kubectl rollout restart deployment/financeservice -n prod
kubectl rollout restart deployment/frontendcustomerorderstatus -n prod
kubectl rollout restart deployment/frontendkitchenmonitor -n prod
kubectl rollout restart deployment/frontendselfservicepos -n prod
kubectl rollout restart deployment/kitchenservice -n prod
kubectl rollout restart deployment/orderservice -n prod
```

### 7. Verified Recovery
Waited 30 seconds for pods to restart, then verified status:
```bash
kubectl get pods -n prod
```
Result: All 6 pods showing `2/2 Running` status ✓

```bash
kubectl get deployments -n prod
```
Result: All 6 deployments showing `1/1 READY` and `1 AVAILABLE` ✓

### 8. Confirmed Dapr Sidecar Initialization
Checked logs from a sample pod:
```bash
kubectl logs kitchenservice-f5c77889d-sf9rw -n prod -c daprd --tail=30
```
Key success indicators:
- `dapr initialized. Status: Running. Init Elapsed 218ms` ✓
- `app is subscribed to the following topics... through pubsub=pubsub` ✓
- No Redis connection errors ✓

## Post-incident
**Service Restored**: All 6 Fast-Food services are now running normally with both application and Dapr sidecar containers healthy.

**Follow-up Items**:
1. **Root Cause Investigation**: Determine how the incorrect hostname "-wrong" was introduced into the Dapr component configurations
2. **Configuration Review**: Audit all Dapr components across all namespaces for similar configuration issues
3. **Validation Gates**: Consider adding Helm chart validation or admission webhooks to prevent invalid hostnames in Dapr component configurations
4. **Monitoring Enhancement**: Implement proactive monitoring for Dapr component initialization failures to catch issues faster
5. **Documentation**: Update runbooks with this incident pattern for faster resolution in the future

**Resolution Time**: ~5 minutes from diagnosis to full recovery  
**Downtime**: Approximately 170 minutes (based on pod age at time of fix)
