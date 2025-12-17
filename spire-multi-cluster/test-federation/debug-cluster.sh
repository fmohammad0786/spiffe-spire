#!/bin/bash

echo "=========================================="
echo "Forcing immediate federation refresh"
echo "=========================================="
echo ""

echo "Current time: $(date -u)"
echo "Next scheduled dev-team.org refresh: 09:02:10 UTC"
echo "That's still ~7-8 minutes away!"
echo ""
echo "Restarting Cluster C to trigger immediate refresh..."
echo ""

kubectl --context=kind-cluster-c delete pod -n spire spire-server-0

echo "Waiting for pod to restart..."
kubectl --context=kind-cluster-c wait --for=condition=ready pod -n spire spire-server-0 --timeout=120s

echo ""
echo "Waiting 30 seconds for SPIRE to initialize and start federation..."
sleep 30

echo ""
echo "Checking if both federations are now active..."
echo ""

kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=50 | \
  grep -E "Trust domain is now managed|Polling for bundle update|Bundle refreshed"

echo ""
echo "=========================================="
echo "Final Status Check"
echo "=========================================="
echo ""

BB_COUNT=$(kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=50 | grep "Bundle refreshed.*bb-team" | wc -l)
DEV_COUNT=$(kubectl --context=kind-cluster-c logs -n spire sts/spire-server --tail=50 | grep "Bundle refreshed.*dev-team" | wc -l)

echo "Cluster C (devops-team.org) federation status:"
echo "  → bb-team.org:  $([ $BB_COUNT -gt 0 ] && echo '✅' || echo '⏳') ($BB_COUNT refreshes)"
echo "  → dev-team.org: $([ $DEV_COUNT -gt 0 ] && echo '✅' || echo '⏳') ($DEV_COUNT refreshes)"
echo ""

if [ $BB_COUNT -gt 0 ] && [ $DEV_COUNT -gt 0 ]; then
  echo "🎉 SUCCESS! Both federations are now active!"
  echo ""
  echo "Running complete federation verification..."
  echo ""
  ./final-status.sh
else
  echo "⚠️  Waiting for first refresh cycle..."
  echo ""
  echo "The bundles are configured. If you see 'Trust domain is now managed'"
  echo "for both bb-team.org and dev-team.org above, just wait 60-90 seconds"
  echo "for the automatic refresh to occur, then run:"
  echo ""
  echo "  ./final-status.sh"
fi

echo ""
echo "=========================================="
