#!/bin/bash

echo "Diagnosing Cluster C → dev-team.org federation..."
echo ""

# Check recent logs from Cluster C
echo "=== Recent Cluster C logs for dev-team.org ==="
kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=100 | grep "dev-team.org" | tail -10

echo ""
echo "=== Checking if dev-team.org bundle exists in Cluster C ==="
kubectl --context=kind-cluster-c exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle show -format spiffe \
  -socketPath /tmp/spire-server/private/api.sock \
  spiffe://dev-team.org 2>&1 | head -5

echo ""
echo "=== Testing connectivity from Cluster C to Cluster B ==="
kubectl --context=kind-cluster-c exec -n spire sts/spire-server -- \
  timeout 3 wget -O- --no-check-certificate https://172.18.0.3:8443 2>&1 | head -3

echo ""
echo "Refreshing dev-team.org bundle in Cluster C..."

# Fetch latest bundle from Cluster B
curl -k -s "https://172.18.0.3:8443" > /tmp/bundle-dev-team-refresh.json

# Set it in Cluster C
kubectl --context=kind-cluster-c exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://dev-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-dev-team-refresh.json

rm -f /tmp/bundle-dev-team-refresh.json

echo ""
echo "Waiting 20 seconds for next refresh cycle..."
sleep 20

echo ""
echo "Checking if federation is now working..."
kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=20 | grep -E "dev-team.org|Bundle refreshed"

echo ""
echo "=========================================="
echo "Running final verification..."
echo ""

# Quick check
if kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=30 | grep -q "Bundle refreshed.*trust_domain=dev-team.org"; then
  echo "✅ Cluster C → dev-team.org: NOW WORKING!"
else
  echo "⚠️  Still initializing, check logs:"
  echo "   kubectl --context=kind-cluster-c logs -n spire sts/spire-server -f | grep dev-team"
fi

echo "=========================================="
