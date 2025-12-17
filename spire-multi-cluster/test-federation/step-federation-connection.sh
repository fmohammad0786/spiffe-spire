#!/bin/bash

# SPIRE Federation Setup for Three Kubernetes Clusters
# Trust Domains: dev-team.org, devops-team.org
# Clusters: kind-cluster-a, kind-cluster-b, kind-cluster-c

set -e

echo "=== Step 1: Export bundles from all clusters ==="

# Export bundle from cluster-a (dev-team.org)
kubectl --context=kind-cluster-a exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle show -format spiffe > cluster-a-bundle.pem

# Export bundle from cluster-b (assuming it's also dev-team.org or another domain)
kubectl --context=kind-cluster-b exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle show -format spiffe > cluster-b-bundle.pem

# Export bundle from cluster-c (devops-team.org)
kubectl --context=kind-cluster-c exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle show -format spiffe > cluster-c-bundle.pem

echo "✓ Bundles exported successfully"

echo "=== Step 2: Set federation bundles ==="

# Federation for cluster-a: trust cluster-c (devops-team.org)
echo "Setting up federation on cluster-a to trust devops-team.org..."
kubectl --context=kind-cluster-a exec -n spire sts/spire-server -i -- \
  /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://devops-team.org < cluster-c-bundle.pem

# Federation for cluster-b: trust both cluster-a and cluster-c (if needed)
echo "Setting up federation on cluster-b..."
kubectl --context=kind-cluster-b exec -n spire sts/spire-server -i -- \
  /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://dev-team.org < cluster-a-bundle.pem

kubectl --context=kind-cluster-b exec -n spire sts/spire-server -i -- \
  /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://devops-team.org < cluster-c-bundle.pem

# Federation for cluster-c: trust cluster-a (dev-team.org)
echo "Setting up federation on cluster-c to trust dev-team.org..."
kubectl --context=kind-cluster-c exec -n spire sts/spire-server -i -- \
  /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://dev-team.org < cluster-a-bundle.pem

echo "✓ Federation bundles configured"

echo "=== Step 3: Verify federation setup ==="

echo "Checking federated bundles on cluster-a..."
kubectl --context=kind-cluster-a exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle list

echo "Checking federated bundles on cluster-b..."
kubectl --context=kind-cluster-b exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle list

echo "Checking federated bundles on cluster-c..."
kubectl --context=kind-cluster-c exec -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle list

echo "=== Federation setup complete! ==="
echo ""
echo "To update bundles in the future, you can use:"
echo "  kubectl --context=kind-cluster-X exec -n spire sts/spire-server -i -- \\"
echo "    /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://TRUST-DOMAIN < bundle.pem"
echo ""
echo "To refresh a specific bundle:"
echo "  kubectl --context=kind-cluster-X exec -n spire sts/spire-server -- \\"
echo "    /opt/spire/bin/spire-server bundle refresh -id spiffe://TRUST-DOMAIN"
