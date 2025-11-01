#!/bin/bash
# Verification script for Dapr component configurations

set -e

echo "🔍 Verifying Dapr component configurations..."
echo ""

# Check for YAML syntax
echo "✓ Checking YAML syntax..."
yamllint k8s/dapr-components/ || { echo "❌ YAML lint failed"; exit 1; }

# Verify correct Redis hostname
echo "✓ Checking Redis hostname..."
if grep -q "redis-ha-haproxy-wrong" k8s/dapr-components/*.yaml; then
    echo "❌ ERROR: Found incorrect hostname with 'wrong' in it!"
    exit 1
fi

if ! grep -q "redis-ha-haproxy.redis:6379" k8s/dapr-components/*.yaml; then
    echo "❌ ERROR: Correct Redis hostname not found!"
    exit 1
fi

# Verify both components exist
echo "✓ Checking required components..."
if [ ! -f "k8s/dapr-components/pubsub.yaml" ]; then
    echo "❌ ERROR: pubsub.yaml not found!"
    exit 1
fi

if [ ! -f "k8s/dapr-components/statestore.yaml" ]; then
    echo "❌ ERROR: statestore.yaml not found!"
    exit 1
fi

# Verify component structure
echo "✓ Verifying component structure..."
python3 - <<'EOF'
import yaml
import sys

files = ['k8s/dapr-components/pubsub.yaml', 'k8s/dapr-components/statestore.yaml']

for file in files:
    with open(file, 'r') as f:
        doc = yaml.safe_load(f)
    
    assert doc['apiVersion'] == 'dapr.io/v1alpha1', f"Wrong apiVersion in {file}"
    assert doc['kind'] == 'Component', f"Wrong kind in {file}"
    assert doc['metadata']['namespace'] == 'prod', f"Wrong namespace in {file}"
    
    redis_host = [m for m in doc['spec']['metadata'] if m['name'] == 'redisHost'][0]
    assert redis_host['value'] == 'redis-ha-haproxy.redis:6379', f"Wrong Redis host in {file}"
    
    print(f"✓ {file} structure is valid")
EOF

echo ""
echo "✅ All verifications passed!"
echo ""
echo "To deploy to the cluster, run:"
echo "  kubectl apply -f k8s/dapr-components/"
