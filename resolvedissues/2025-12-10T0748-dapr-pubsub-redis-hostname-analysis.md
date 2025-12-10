# Dapr PubSub Component Redis Connection Failure - Incorrect Hostname (Analysis)

**When:** 2025-12-10T07:48:00Z  
**Cluster:** dev-aks-k8sdemo-westeurope  
**Namespace:** prod  
**Impact:** All Fast-Food application services in CrashLoopBackOff due to Dapr sidecar initialization failures. Services affected: `financeservice`, `frontendcustomerorderstatus`, `frontendkitchenmonitor`, `frontendselfservicepos`, `kitchenservice`, `orderservice`

---

## Signals

### Key Alerts
- Monitoring system detected repeated Dapr sidecar restarts
- All pods in namespace `prod` showing `1/2 READY` status (application container up, Dapr sidecar failing)
- CrashLoopBackOff status across all services with 11 restarts in ~32 minutes
- Back-off restart delays increasing (exponential backoff pattern observed)

### Representative Logs

**From kitchenservice Dapr sidecar:**
```
time="2025-12-10T07:46:03.951090708Z" level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host" app_id=kitchenservice instance=kitchenservice-f5c77889d-ppt6r

time="2025-12-10T07:46:03.951848642Z" level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host"
```

**From financeservice Dapr sidecar:**
```
time="2025-12-10T07:46:14.980868744Z" level=error msg="Failed to init component pubsub (pubsub.redis/v1): [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host" app_id=financeservice instance=financeservice-76cbdc5bbc-s77xl

time="2025-12-10T07:46:14.98147Z" level=fatal msg="Fatal error from runtime: process component pubsub error: [INIT_COMPONENT_FAILURE]: initialization error occurred for pubsub (pubsub.redis/v1): redis streams: error connecting to redis at redis-ha-haproxy-wrong.redis:6379: dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host"
```

### Kubernetes Events
```
3m13s   Warning   BackOff   pod/frontendselfservicepos-8455bf4b64-9m9g7        Back-off restarting failed container daprd
3m12s   Warning   BackOff   pod/frontendcustomerorderstatus-5d4694cdd9-wpk4m   Back-off restarting failed container daprd
3m11s   Warning   BackOff   pod/financeservice-76cbdc5bbc-s77xl                Back-off restarting failed container daprd
3m9s    Warning   BackOff   pod/orderservice-ff7959666-xt5x5                   Back-off restarting failed container daprd
3m8s    Warning   BackOff   pod/frontendkitchenmonitor-584c8894f5-nl6hq        Back-off restarting failed container daprd
3m7s    Warning   BackOff   pod/kitchenservice-f5c77889d-ppt6r                 Back-off restarting failed container daprd
```

---

## Diagnosis

### Root Cause
The **pubsub** Dapr component is configured with an incorrect Redis hostname: **`redis-ha-haproxy-wrong.redis:6379`**

The hostname contains an invalid `-wrong` suffix, causing DNS lookups to fail with "no such host" errors. This prevents Dapr sidecars from initializing the pubsub component, which is required by all Fast-Food services, causing all pods to enter CrashLoopBackOff state.

### Components Affected

**Current Configuration Analysis:**

1. **pubsub** (pubsub.redis/v1) - **MISCONFIGURED** ❌
   ```yaml
   spec:
     metadata:
     - name: redisHost
       value: redis-ha-haproxy-wrong.redis:6379  # INCORRECT - contains "-wrong" suffix
   ```
   - Status: Failing initialization
   - Used by: All 6 services for pub/sub messaging
   - Impact: **CRITICAL** - blocks all services from starting

2. **statestore** (state.redis/v1) - **CORRECTLY CONFIGURED** ✅
   ```yaml
   spec:
     metadata:
     - name: redisHost
       value: redis-ha-haproxy.redis:6379  # CORRECT hostname
   ```
   - Status: Would initialize successfully if Dapr reached this component
   - Used by: Services requiring state storage and actor state
   - Impact: Currently not reached due to pubsub failure

### Error Pattern
```
Error Code: INIT_COMPONENT_FAILURE
Component: pubsub (pubsub.redis/v1)
Cause: DNS resolution failure
Details: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host
```

**Failure Sequence:**
1. Dapr sidecar starts and loads configuration
2. Dapr attempts to initialize components in order
3. pubsub component initialization attempted
4. DNS lookup for `redis-ha-haproxy-wrong.redis` fails
5. Dapr sidecar exits with fatal error
6. Kubernetes restarts container (CrashLoopBackOff)
7. Back-off delay increases exponentially (current: ~3 minutes between restarts)

### Historical Context

**This is a RECURRENCE of a previously resolved incident:**
- Original incident: 2025-11-01T20:28:34Z
- Original resolution: Patched both pubsub and statestore components
- Current status: pubsub component has regressed to incorrect configuration
- Possible causes for recurrence:
  1. Configuration was redeployed from source with incorrect value
  2. GitOps/Helm deployment overwrote manual fixes
  3. Configuration management issue (drift between desired and actual state)

### Component Metadata Comparison

| Component  | redisHost Value                        | Status      | Generation |
|------------|---------------------------------------|-------------|------------|
| pubsub     | redis-ha-haproxy-**wrong**.redis:6379 | ❌ FAILING  | 7          |
| statestore | redis-ha-haproxy.redis:6379           | ✅ CORRECT  | 6          |

**Key Observation:** The pubsub component has been modified 7 times (generation: 7), while statestore has been modified 6 times (generation: 6). This suggests that pubsub was recently updated/redeployed, potentially reverting the previous fix.

---

## Current Cluster State

### Pod Status (as of 2025-12-10T07:46:00Z)
```
NAME                                           READY   STATUS             RESTARTS       AGE
financeservice-76cbdc5bbc-s77xl                1/2     CrashLoopBackOff   11 (49s ago)   32m
frontendcustomerorderstatus-5d4694cdd9-wpk4m   1/2     CrashLoopBackOff   11 (43s ago)   32m
frontendkitchenmonitor-584c8894f5-nl6hq        1/2     CrashLoopBackOff   11 (55s ago)   32m
frontendselfservicepos-8455bf4b64-9m9g7        1/2     CrashLoopBackOff   11 (75s ago)   32m
kitchenservice-f5c77889d-ppt6r                 1/2     CrashLoopBackOff   11 (60s ago)   32m
orderservice-ff7959666-xt5x5                   1/2     CrashLoopBackOff   11 (73s ago)   32m
```

**Analysis:**
- All pods show `1/2 READY` (application container healthy, Dapr sidecar failing)
- All pods in CrashLoopBackOff with 11 restarts
- Restart interval increasing due to exponential backoff
- Application containers remain healthy but unable to serve requests without Dapr

### Deployment Status
```
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
financeservice                0/1     1            0           165d
frontendcustomerorderstatus   0/1     1            0           165d
frontendkitchenmonitor        0/1     1            0           165d
frontendselfservicepos        0/1     1            0           165d
kitchenservice                0/1     1            0           165d
orderservice                  0/1     1            0           165d
```

**Analysis:**
- All deployments show 0/1 READY
- No available replicas for any service
- Complete service outage across all Fast-Food applications

---

## Next Steps for Resolution

### Immediate Actions Required

**IMPORTANT: Per the task requirements, NO changes should be made to the cluster as this is an analysis-only task.**

The following steps outline what SHOULD be done to resolve the issue (for execution by authorized personnel):

#### 1. Patch the pubsub Component

**Current value:**
```yaml
redisHost: redis-ha-haproxy-wrong.redis:6379
```

**Required value:**
```yaml
redisHost: redis-ha-haproxy.redis:6379
```

**Command to fix:**
```bash
kubectl patch component pubsub -n prod --type=json \
  -p '[{"op": "replace", "path": "/spec/metadata/0/value", "value": "redis-ha-haproxy.redis:6379"}]'
```

**Verification command:**
```bash
kubectl get component pubsub -n prod -o jsonpath='{.spec.metadata[?(@.name=="redisHost")].value}'
# Expected output: redis-ha-haproxy.redis:6379
```

#### 2. Restart All Affected Deployments

After patching the component, restart all deployments to reload Dapr sidecars:

```bash
# Restart all services
kubectl rollout restart deployment financeservice -n prod
kubectl rollout restart deployment frontendcustomerorderstatus -n prod
kubectl rollout restart deployment frontendkitchenmonitor -n prod
kubectl rollout restart deployment frontendselfservicepos -n prod
kubectl rollout restart deployment kitchenservice -n prod
kubectl rollout restart deployment orderservice -n prod
```

**Batch command:**
```bash
kubectl rollout restart deployment -n prod \
  financeservice \
  frontendcustomerorderstatus \
  frontendkitchenmonitor \
  frontendselfservicepos \
  kitchenservice \
  orderservice
```

#### 3. Monitor Recovery

Wait 30-60 seconds for pods to restart, then verify:

```bash
# Check pod status
kubectl get pods -n prod

# Expected: All pods showing 2/2 READY, Running status

# Verify Dapr sidecar logs show successful initialization
kubectl logs <pod-name> -n prod -c daprd --tail=50

# Expected log messages:
# - "Component loaded: pubsub (pubsub.redis/v1)"
# - "Component loaded: statestore (state.redis/v1)"
# - "dapr initialized. Status: Running."
```

#### 4. Verify Service Health

```bash
# Check deployment readiness
kubectl get deployments -n prod

# Expected: All deployments showing 1/1 READY

# Check for any error events
kubectl get events -n prod --sort-by='.lastTimestamp' | grep -i error

# Expected: No recent error events
```

---

## Post-Resolution Investigation Required

### 1. Root Cause Analysis - Configuration Source
**Priority:** HIGH

**Actions:**
- Investigate what caused the pubsub component to be redeployed with incorrect configuration
- Review GitOps/Helm chart source for the Dapr components
- Check if incorrect value exists in source control (Git repository, Helm values)
- Review recent deployment history and change logs
- Identify who/what triggered the redeployment

**Verification:**
```bash
# Check component annotations for Helm release info
kubectl get component pubsub -n prod -o yaml | grep -A5 "annotations:"

# Current annotations show:
#   meta.helm.sh/release-name: daprenv
#   meta.helm.sh/release-namespace: prod
# This indicates it's managed by Helm - investigate Helm chart source
```

### 2. Implement Configuration Validation
**Priority:** HIGH

**Recommendations:**
- Add pre-deployment validation for Dapr component configurations
- Validate DNS resolvability of hostnames before applying configurations
- Implement admission webhooks to reject invalid component configurations
- Add automated tests for component configurations in CI/CD pipeline

**Example validation script:**
```bash
# Validate Redis hostname is resolvable
nslookup redis-ha-haproxy.redis || echo "ERROR: Invalid hostname"
```

### 3. Prevent Configuration Drift
**Priority:** MEDIUM

**Recommendations:**
- Implement GitOps with proper reconciliation
- Use Flux/ArgoCD to maintain desired state and prevent manual drift
- Add monitoring for component configuration changes
- Set up alerts for component generation changes (e.g., generation > expected value)
- Review and update Helm charts to ensure correct values

**Monitoring example:**
```yaml
# Alert when component is modified unexpectedly
alert: DaprComponentModified
expr: increase(kube_dapr_component_generation{component="pubsub"}[5m]) > 0
annotations:
  summary: "Dapr component {{ $labels.component }} was modified"
```

### 4. Improve Monitoring and Alerting
**Priority:** MEDIUM

**Recommendations:**
- Add specific alerts for Dapr component initialization failures
- Monitor Dapr sidecar restart counts
- Alert on CrashLoopBackOff status for pods with Dapr sidecars
- Create dashboard showing Dapr component health across clusters

**Example alert:**
```yaml
alert: DaprComponentInitializationFailure
expr: |
  count by (namespace, component) (
    dapr_component_init_errors_total > 0
  ) > 0
for: 5m
annotations:
  summary: "Dapr component {{ $labels.component }} failing to initialize"
  description: "Component initialization errors detected for {{ $labels.component }} in namespace {{ $labels.namespace }}"
```

### 5. Create Runbook Entry
**Priority:** LOW

**Actions:**
- Add error code `INIT_COMPONENT_FAILURE` to fastfoodmcp knowledge base
- Document this specific scenario (Redis hostname misconfiguration)
- Include diagnostic steps and resolution procedures
- Reference this incident for historical context

**Suggested knowledge base entry:**
```yaml
code: "INIT_COMPONENT_FAILURE"
title: "Dapr Component Initialization Failure"
severity: "critical"
services: ["all"]
likelyCauses:
  - "Invalid Redis hostname in component configuration"
  - "DNS resolution failure for external dependencies"
  - "Network connectivity issues to external services"
  - "Authentication/authorization failures"
recommendedSteps:
  - "Check component configuration for incorrect values"
  - "Verify DNS resolution of hostnames"
  - "Check Dapr sidecar logs for specific error details"
  - "Validate external service availability"
  - "Review recent configuration changes"
references:
  - "Incident 2025-12-10: Pubsub Redis hostname misconfiguration"
  - "Incident 2025-11-01: Previous occurrence of same issue"
```

---

## Impact Assessment

### Service Availability
- **Duration:** Unknown start time, ongoing at time of analysis
- **Scope:** 100% of production Fast-Food services unavailable
- **Services down:** 6 critical services
  - `financeservice` - Financial transactions and reporting
  - `frontendcustomerorderstatus` - Customer order tracking
  - `frontendkitchenmonitor` - Kitchen operations display
  - `frontendselfservicepos` - Self-service point of sale
  - `kitchenservice` - Kitchen order processing
  - `orderservice` - Order management and orchestration

### User Impact
- **Customers:** Cannot place orders via self-service POS
- **Customers:** Cannot check order status
- **Kitchen staff:** Cannot view incoming orders
- **Kitchen staff:** Cannot process orders
- **Finance:** Cannot process or track transactions
- **Overall:** Complete service outage for Fast-Food operations

### Business Impact
- Revenue loss during downtime period
- Customer dissatisfaction and potential reputation damage
- Operational disruption for kitchen and front-of-house staff
- Potential data loss if orders were attempted during outage (depends on retry/queue mechanisms)

---

## Technical Details

### Dapr Version
- **Version:** 1.15.5
- **Commit:** e4869dbba529d57b4807d0f13f86ce9ad089ca65
- **Runtime:** Stable

### Component Specifications

**pubsub Component (FAILING):**
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
  namespace: prod
  generation: 7
  resourceVersion: "30373194"
  annotations:
    meta.helm.sh/release-name: daprenv
    meta.helm.sh/release-namespace: prod
  labels:
    app.kubernetes.io/managed-by: Helm
spec:
  type: pubsub.redis
  version: v1
  metadata:
  - name: redisHost
    value: redis-ha-haproxy-wrong.redis:6379  # INCORRECT
  - name: redisPassword
    secretKeyRef:
      key: redis-password
      name: daprenv-dapr-secrets
  - name: redisDB
    value: "0"
  - name: maxLenApprox
    value: "100"
scopes:
  - orderservice
  - kitchenservice
  - financeservice
  - orderserviceactors
  - frontendselfservicepos
  - frontendkitchenmonitor
  - frontendcustomerorderstatus
```

**statestore Component (CORRECT):**
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: prod
  generation: 6
  resourceVersion: "14325372"
  annotations:
    meta.helm.sh/release-name: daprenv
    meta.helm.sh/release-namespace: prod
  labels:
    app.kubernetes.io/managed-by: Helm
spec:
  type: state.redis
  version: v1
  metadata:
  - name: redisHost
    value: redis-ha-haproxy.redis:6379  # CORRECT
  - name: redisPassword
    secretKeyRef:
      key: redis-password
      name: daprenv-dapr-secrets
  - name: actorStateStore
    value: "true"
scopes:
  - orderservice
  - kitchenservice
  - financeservice
  - orderserviceactors
  - frontendselfservicepos
  - frontendkitchenmonitor
  - frontendcustomerorderstatus
```

### DNS Error Details
```
dial tcp: lookup redis-ha-haproxy-wrong.redis on 10.0.0.10:53: no such host
```

**Analysis:**
- DNS server: `10.0.0.10:53` (cluster DNS)
- Failed lookup: `redis-ha-haproxy-wrong.redis`
- Error: `no such host` (NXDOMAIN)
- Expected hostname: `redis-ha-haproxy.redis` (without `-wrong` suffix)

---

## Summary

### Current Status
🔴 **OUTAGE IN PROGRESS** - All production Fast-Food services are down

### Root Cause
Dapr pubsub component misconfigured with invalid Redis hostname (`redis-ha-haproxy-wrong.redis:6379`)

### Resolution Path
1. Patch pubsub component to correct hostname
2. Restart all deployments
3. Verify service recovery
4. **Estimated time to resolution:** 3-5 minutes (once authorized to proceed)

### Critical Finding
This is a **RECURRENCE** of incident from 2025-11-01. The configuration has regressed, indicating a **configuration management issue** that must be addressed to prevent future occurrences.

### Recommended Immediate Action
Execute the patching and restart procedures outlined in the "Next Steps for Resolution" section.

### Follow-up Required
Complete all post-resolution investigation items, particularly:
- Root cause analysis of configuration source
- Implementation of configuration validation
- Prevention of configuration drift
- Enhanced monitoring and alerting

---

## References

- Previous incident: `/resolvedissues/2025-11-01T2028-dapr-redis-connection-failure.md`
- Dapr Component Specs: https://docs.dapr.io/reference/components-reference/
- Kubernetes CrashLoopBackOff troubleshooting: https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/
