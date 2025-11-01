# fastfood-sre

This repository contains the Site Reliability Engineering (SRE) configuration for the Fast-Food application running on Azure Kubernetes Service (AKS) with Dapr.

## Directory Structure

```
k8s/
  dapr-components/     # Dapr component definitions
    pubsub.yaml        # Redis pubsub component
    statestore.yaml    # Redis state store component
```

## Dapr Components

### Redis Configuration

The application uses Redis (via HAProxy) for both pub/sub messaging and state storage:

- **Service Name**: `redis-ha-haproxy.redis`
- **Port**: 6379
- **Namespace**: `redis`

### Components

1. **pubsub** - Redis Streams-based pub/sub for inter-service communication
2. **statestore** - Redis-based state management for service state persistence

## Deployment

To deploy the Dapr components to the cluster:

```bash
kubectl apply -f k8s/dapr-components/
```

## Troubleshooting

### Redis Connection Issues

If you see errors like:
```
Failed to init component pubsub (pubsub.redis/v1): redis streams: error connecting to redis
```

Verify:
1. Redis service is running in the `redis` namespace
2. The hostname `redis-ha-haproxy.redis` is resolvable
3. The `redis-secret` exists in the target namespace with key `redis-password`