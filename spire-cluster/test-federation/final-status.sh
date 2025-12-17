#!/bin/bash

echo "=========================================="
echo "SPIRE Federation Final Status"
echo "=========================================="
echo ""
echo "Time: $(date)"
echo ""

# Check each cluster
for cluster in cluster-a cluster-b cluster-c; do
  case $cluster in
    cluster-a) trust_domain="bb-team.org" ;;
    cluster-b) trust_domain="dev-team.org" ;;
    cluster-c) trust_domain="devops-team.org" ;;
  esac
  
  echo "=== $cluster ($trust_domain) ==="
  
  # Count successful refreshes in last 50 lines
  SUCCESS=$(kubectl --context=kind-$cluster logs -n spire sts/spire-server --tail=50 2>/dev/null | grep "Bundle refreshed" | wc -l)
  ERRORS=$(kubectl --context=kind-$cluster logs -n spire sts/spire-server --tail=50 2>/dev/null | grep "Error updating bundle" | wc -l)
  
  echo "  Bundle refreshes (last 50 lines): $SUCCESS"
  echo "  Errors (last 50 lines): $ERRORS"
  
  # List all bundles
  echo "  Federated bundles:"
  kubectl --context=kind-$cluster exec -n spire sts/spire-server -- \
    /opt/spire/bin/spire-server bundle list -socketPath /tmp/spire-server/private/api.sock 2>/dev/null | \
    grep "^\*" | sed 's/^/    /'
  
  echo ""
done

echo "=========================================="
echo "Federation Matrix (All should be ✅)"
echo "=========================================="
echo ""

# Build matrix
declare -A status
for cluster in cluster-a cluster-b cluster-c; do
  LOGS=$(kubectl --context=kind-$cluster logs -n spire sts/spire-server --tail=100 2>/dev/null)
  
  if echo "$LOGS" | grep -q "Bundle refreshed.*trust_domain=bb-team.org"; then
    status["$cluster-bb"]="✅"
  else
    status["$cluster-bb"]="❌"
  fi
  
  if echo "$LOGS" | grep -q "Bundle refreshed.*trust_domain=dev-team.org"; then
    status["$cluster-dev"]="✅"
  else
    status["$cluster-dev"]="❌"
  fi
  
  if echo "$LOGS" | grep -q "Bundle refreshed.*trust_domain=devops-team.org"; then
    status["$cluster-devops"]="✅"
  else
    status["$cluster-devops"]="❌"
  fi
done

echo "Cluster A (bb-team.org) federating with:"
echo "  → dev-team.org:    ${status[cluster-a-dev]}"
echo "  → devops-team.org: ${status[cluster-a-devops]}"
echo ""

echo "Cluster B (dev-team.org) federating with:"
echo "  → bb-team.org:     ${status[cluster-b-bb]}"
echo "  → devops-team.org: ${status[cluster-b-devops]}"
echo ""

echo "Cluster C (devops-team.org) federating with:"
echo "  → bb-team.org:     ${status[cluster-c-bb]}"
echo "  → dev-team.org:    ${status[cluster-c-dev]}"
echo ""

# Check if all are working
ALL_WORKING=true
for key in "${!status[@]}"; do
  if [[ "${status[$key]}" != "✅" ]]; then
    ALL_WORKING=false
  fi
done

if $ALL_WORKING; then
  echo "=========================================="
  echo "🎉 SUCCESS! ALL FEDERATIONS WORKING! 🎉"
  echo "=========================================="
  echo ""
  echo "Your 3-cluster SPIRE federation is fully operational!"
  echo ""
  echo "Next steps:"
  echo "  1. Create workload entries in each cluster"
  echo "  2. Deploy workloads that use federated identities"
  echo "  3. Test cross-cluster authentication"
else
  echo "=========================================="
  echo "⚠️  Some federations still initializing"
  echo "=========================================="
fi
