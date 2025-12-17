#!/bin/bash
set -e

echo "=========================================="
echo "Bootstrapping SPIRE Federation"
echo "=========================================="
echo ""

# Get the cluster IPs
CLUSTER_A_IP="172.18.0.2"
CLUSTER_B_IP="172.18.0.3"
CLUSTER_C_IP="172.18.0.4"

echo "Step 1: Fetching bundles from each cluster..."
echo ""

# Fetch bundle from Cluster A
echo "Fetching bundle from Cluster A (bb-team.org)..."
curl -k -s "https://$CLUSTER_A_IP:8443" > /tmp/bundle-bb-team.json
echo "  ✓ Fetched ($(wc -c < /tmp/bundle-bb-team.json) bytes)"

# Fetch bundle from Cluster B
echo "Fetching bundle from Cluster B (dev-team.org)..."
curl -k -s "https://$CLUSTER_B_IP:8443" > /tmp/bundle-dev-team.json
echo "  ✓ Fetched ($(wc -c < /tmp/bundle-dev-team.json) bytes)"

# Fetch bundle from Cluster C
echo "Fetching bundle from Cluster C (devops-team.org)..."
curl -k -s "https://$CLUSTER_C_IP:8443" > /tmp/bundle-devops-team.json
echo "  ✓ Fetched ($(wc -c < /tmp/bundle-devops-team.json) bytes)"

echo ""
echo "Step 2: Setting federated bundles..."
echo ""

# Set bundles in Cluster A (needs bundles from B and C)
echo "Setting bundles in Cluster A (bb-team.org)..."
echo "  - Setting dev-team.org bundle..."
kubectl --context=kind-cluster-a exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://dev-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-dev-team.json

echo "  - Setting devops-team.org bundle..."
kubectl --context=kind-cluster-a exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://devops-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-devops-team.json
echo "  ✓ Cluster A configured"

echo ""
# Set bundles in Cluster B (needs bundles from A and C)
echo "Setting bundles in Cluster B (dev-team.org)..."
echo "  - Setting bb-team.org bundle..."
kubectl --context=kind-cluster-b exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://bb-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-bb-team.json

echo "  - Setting devops-team.org bundle..."
kubectl --context=kind-cluster-b exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://devops-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-devops-team.json
echo "  ✓ Cluster B configured"

echo ""
# Set bundles in Cluster C (needs bundles from A and B)
echo "Setting bundles in Cluster C (devops-team.org)..."
echo "  - Setting bb-team.org bundle..."
kubectl --context=kind-cluster-c exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://bb-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-bb-team.json

echo "  - Setting dev-team.org bundle..."
kubectl --context=kind-cluster-c exec -i -n spire sts/spire-server -- \
  /opt/spire/bin/spire-server bundle set -format spiffe \
  -id spiffe://dev-team.org \
  -socketPath /tmp/spire-server/private/api.sock - < /tmp/bundle-dev-team.json
echo "  ✓ Cluster C configured"

echo ""
echo "Step 3: Verifying bundles are set..."
echo ""

for cluster in cluster-a cluster-b cluster-c; do
  case $cluster in
    cluster-a) trust_domain="bb-team.org" ;;
    cluster-b) trust_domain="dev-team.org" ;;
    cluster-c) trust_domain="devops-team.org" ;;
  esac
  
  echo "=== $cluster ($trust_domain) ==="
  kubectl --context=kind-$cluster exec -n spire sts/spire-server -- \
    /opt/spire/bin/spire-server bundle list -socketPath /tmp/spire-server/private/api.sock 2>/dev/null || \
    echo "  Could not list bundles"
  echo ""
done

echo ""
echo "Step 4: Cleaning up temporary files..."
rm -f /tmp/bundle-*.json
echo "  ✓ Cleanup complete"

echo ""
echo "=========================================="
echo "Bootstrap Complete!"
echo "=========================================="
echo ""
echo "Waiting 20 seconds for automatic bundle refresh to begin..."
sleep 20

echo ""
echo "Checking federation status..."
echo ""

# Check for recent activity
for cluster in cluster-a cluster-b cluster-c; do
  case $cluster in
    cluster-a) trust_domain="bb-team.org" ;;
    cluster-b) trust_domain="dev-team.org" ;;
    cluster-c) trust_domain="devops-team.org" ;;
  esac
  
  echo "=== $cluster ($trust_domain) ==="
  
  # Get recent logs
  RECENT_LOGS=$(kubectl --context=kind-$cluster logs -n spire sts/spire-server --tail=30 2>/dev/null)
  
  RECENT_ERRORS=$(echo "$RECENT_LOGS" | grep "Error updating bundle" | wc -l)
  RECENT_SUCCESS=$(echo "$RECENT_LOGS" | grep "Bundle refreshed" | wc -l)
  
  if [ "$RECENT_ERRORS" -eq 0 ] && [ "$RECENT_SUCCESS" -gt 0 ]; then
    echo "  ✅ Federation working ($RECENT_SUCCESS successful refreshes in last 30 log lines)"
  elif [ "$RECENT_ERRORS" -eq 0 ]; then
    echo "  ⏳ No recent errors (waiting for next refresh cycle)"
  else
    echo "  ⚠️  $RECENT_ERRORS errors in last 30 lines"
    echo ""
    echo "  Recent errors:"
    echo "$RECENT_LOGS" | grep "Error updating bundle" | tail -3 | sed 's/^/    /'
  fi
  echo ""
done

echo ""
echo "=========================================="
echo "Federation Matrix:"
echo "=========================================="
echo ""

declare -A matrix
for cluster in cluster-a cluster-b cluster-c; do
  for target in bb-team.org dev-team.org devops-team.org; do
    if kubectl --context=kind-$cluster logs -n spire sts/spire-server --tail=100 2>/dev/null | \
       grep -q "Bundle refreshed.*trust_domain=$target"; then
      matrix["$cluster-$target"]="✅"
    else
      matrix["$cluster-$target"]="⏳"
    fi
  done
done

echo "Cluster A (bb-team.org):"
echo "  → bb-team.org:     ${matrix[cluster-a-bb-team.org]:-N/A} (self)"
echo "  → dev-team.org:    ${matrix[cluster-a-dev-team.org]}"
echo "  → devops-team.org: ${matrix[cluster-a-devops-team.org]}"
echo ""

echo "Cluster B (dev-team.org):"
echo "  → bb-team.org:     ${matrix[cluster-b-bb-team.org]}"
echo "  → dev-team.org:    ${matrix[cluster-b-dev-team.org]:-N/A} (self)"
echo "  → devops-team.org: ${matrix[cluster-b-devops-team.org]}"
echo ""

echo "Cluster C (devops-team.org):"
echo "  → bb-team.org:     ${matrix[cluster-c-bb-team.org]}"
echo "  → dev-team.org:    ${matrix[cluster-c-dev-team.org]}"
echo "  → devops-team.org: ${matrix[cluster-c-devops-team.org]:-N/A} (self)"
echo ""

echo "=========================================="
echo ""
echo "To monitor ongoing federation:"
echo "  watch -n 5 './check-federation-status.sh'"
echo ""
echo "To see live logs from a cluster:"
echo "  kubectl --context=kind-cluster-a logs -n spire sts/spire-server -f"
echo "=========================================="
