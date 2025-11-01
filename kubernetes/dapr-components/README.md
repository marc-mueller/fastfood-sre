# Dapr Components

This directory contains corrected Dapr component manifests for the Fast-Food system.

## Files

### `pubsub-redis.yaml`
Complete Dapr Component manifest with the corrected Redis hostname.

**Usage:**
```bash
kubectl apply -f pubsub-redis.yaml
```

### `pubsub-redis-patch.json`
JSON Patch file that can be used to update just the Redis hostname without replacing the entire component.

This patch corrects the Redis hostname from `redis-ha-haproxy-wrong.redis` to `redis-ha-haproxy.redis`.

**Usage with patch file:**
```bash
kubectl patch component pubsub -n prod --type=json \
  --patch-file pubsub-redis-patch.json
```

**Usage as inline patch:**
```bash
kubectl patch component pubsub -n prod --type=json \
  -p='[{"op":"replace","path":"/spec/metadata/0/value","value":"redis-ha-haproxy.redis:6379"}]'
```

## Important Notes

- Both approaches achieve the same result
- After applying either fix, restart deployments: `kubectl rollout restart deployment -n prod --all`
- The patch assumes `redisHost` is the first item (index 0) in the metadata array
- If your component has a different structure, adjust the path accordingly

## Verification

After applying the fix, verify the component:
```bash
kubectl get component pubsub -n prod -o yaml | grep redisHost -A 1
```

Expected output:
```yaml
- name: redisHost
  value: redis-ha-haproxy.redis:6379
```
