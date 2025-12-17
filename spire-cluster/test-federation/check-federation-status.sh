#!/bin/bash

echo "=========================================="
echo "SPIRE Federation Status Check"
echo "=========================================="
echo ""

# Check each cluster's federation status
for cluster in cluster-a cluster-b cluster-c; do
  case $cluster in
    cluster-a) trust_domain="bb-team.org" ;;
    cluster-b) trust_domain="dev-team.org" ;;
    cluster-c) trust_domain="devops-team.org" ;;
  esac
  
  echo "=== $cluster ($trust_domain) ==="
  echo ""
  
  # Get the last 20 lines with bundle info
  kubectl --context=kind-$cluster logs -n spire spire-server-0 --tail=100 | \
    grep -E "Trust domain is now managed|Bundle refreshed|Error updating bundle" | \
    tail -10
  
  echo ""
done

echo ""
echo "=========================================="
echo "Testing Bundle Endpoints from Host"
echo "=========================================="
echo ""

echo "Cluster A (bb-team.org) at 172.18.0.2:8443:"
curl -k -s https://172.18.0.2:8443 2>&1 | head -1

echo ""
echo "Cluster B (dev-team.org) at 172.18.0.3:8443:"
curl -k -s https://172.18.0.3:8443 2>&1 | head -1

echo ""
echo "Cluster C (devops-team.org) at 172.18.0.4:8443:"
curl -k -s https://172.18.0.4:8443 2>&1 | head -1

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

# Count successful bundle refreshes in the last 5 minutes
for cluster in cluster-a cluster-b cluster-c; do
  case $cluster in
    cluster-a) trust_domain="bb-team.org" ;;
    cluster-b) trust_domain="dev-team.org" ;;
    cluster-c) trust_domain="devops-team.org" ;;
  esac
  
  SUCCESS_COUNT=$(kubectl --context=kind-$cluster logs -n spire spire-server-0 --tail=200 | \
    grep "Bundle refreshed" | wc -l)
  
  ERROR_COUNT=$(kubectl --context=kind-$cluster logs -n spire spire-server-0 --tail=200 | \
    grep "Error updating bundle" | wc -l)
  
  echo "$cluster ($trust_domain):"
  echo "  ✓ Successful bundle refreshes: $SUCCESS_COUNT"
  echo "  ✗ Failed bundle updates: $ERROR_COUNT"
  echo ""
done
