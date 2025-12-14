#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_success() { echo -e "${GREEN}✓ $1${NC}"; }
echo_info() { echo -e "${BLUE}→ $1${NC}"; }
echo_step() { echo -e "${YELLOW}▶ $1${NC}"; }

CLUSTER_A_CONTEXT="kind-cluster-a"
CLUSTER_B_CONTEXT="kind-cluster-b"
CLUSTER_C_CONTEXT="kind-cluster-c"

echo_step "Step 1: Registering workloads with federation"

kubectl --context=$CLUSTER_A_CONTEXT exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://bb-team.org/ns/test-cross/sa/server-a \
  -parentID spiffe://bb-team.org/ns/spire/sa/spire-agent \
  -selector k8s:ns:test-cross \
  -selector k8s:sa:server-a \
  -federatesWith spiffe://dev-team.org \
  -federatesWith spiffe://devops-team.org 2>/dev/null || echo "Entry exists"

kubectl --context=$CLUSTER_B_CONTEXT exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://dev-team.org/ns/test-cross/sa/client-b \
  -parentID spiffe://dev-team.org/ns/spire/sa/spire-agent \
  -selector k8s:ns:test-cross \
  -selector k8s:sa:client-b \
  -federatesWith spiffe://bb-team.org 2>/dev/null || echo "Entry exists"

kubectl --context=$CLUSTER_C_CONTEXT exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://devops-team.org/ns/test-cross/sa/client-c \
  -parentID spiffe://devops-team.org/ns/spire/sa/spire-agent \
  -selector k8s:ns:test-cross \
  -selector k8s:sa:client-c \
  -federatesWith spiffe://bb-team.org 2>/dev/null || echo "Entry exists"

echo_success "Workload registration complete"

echo_step "Step 2: Deploying server on Cluster A"

kubectl --context=$CLUSTER_A_CONTEXT apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: test-cross
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: server-a
  namespace: test-cross
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: server-script
  namespace: test-cross
data:
  server.sh: |
    #!/bin/sh
    set -e
    echo "=== Starting Server ==="
    apk add --no-cache python3
    /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock -write /tmp/certs
    echo "=== Server SPIFFE ID ==="
    /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock | grep "SPIFFE ID"
    cat > /tmp/index.html <<'HTML'
    <html><body style="font-family: Arial; padding: 20px;">
    <h1 style="color: #4CAF50;">✓ Backend - Cluster A (bb-team.org)</h1>
    <p><strong>SPIFFE ID:</strong> spiffe://bb-team.org/ns/test-cross/sa/server-a</p>
    <p><strong>Status:</strong> Active and accepting connections!</p>
    </body></html>
    HTML
    cd /tmp
    echo "=== Server ready on port 8080 ==="
    python3 -m http.server 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-a
  namespace: test-cross
spec:
  replicas: 1
  selector:
    matchLabels:
      app: server-a
  template:
    metadata:
      labels:
        app: server-a
    spec:
      serviceAccountName: server-a
      containers:
      - name: server
        image: ghcr.io/spiffe/spire-agent:1.11.2
        command: ["/bin/sh", "/scripts/server.sh"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
          readOnly: true
        - name: server-script
          mountPath: /scripts
      volumes:
      - name: spire-agent-socket
        hostPath:
          path: /run/spire/sockets
          type: Directory
      - name: server-script
        configMap:
          name: server-script
          defaultMode: 0755
YAML

kubectl --context=$CLUSTER_A_CONTEXT wait --for=condition=ready pod -l app=server-a -n test-cross --timeout=120s
echo_success "Server deployed"

SERVER_IP=$(kubectl --context=$CLUSTER_A_CONTEXT get pod -n test-cross -l app=server-a -o jsonpath='{.items[0].status.podIP}')
echo_info "Server IP: $SERVER_IP"

echo_step "Step 3: Deploying clients"

kubectl --context=$CLUSTER_B_CONTEXT apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: test-cross
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: client-b
  namespace: test-cross
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-script
  namespace: test-cross
data:
  client.sh: |
    #!/bin/sh
    set -e
    echo "=== Client B Starting ==="
    apk add --no-cache curl
    sleep 5
    echo "=== Our SPIFFE ID ==="
    /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock | grep "SPIFFE ID"
    /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock -write /tmp/certs
    TARGET_HOST=\${TARGET_HOST:-"$SERVER_IP"}
    echo "=== Testing Connection to \$TARGET_HOST:8080 ==="
    counter=0
    while true; do
      counter=\$((counter + 1))
      echo ""
      echo "--- Test #\$counter at \$(date) ---"
      if curl -s -m 5 "http://\$TARGET_HOST:8080" > /tmp/response.html; then
        echo "✓ SUCCESS! Connected to server"
        grep "SPIFFE ID" /tmp/response.html || true
      else
        echo "✗ Connection failed"
      fi
      sleep 30
    done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-b
  namespace: test-cross
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client-b
  template:
    metadata:
      labels:
        app: client-b
    spec:
      serviceAccountName: client-b
      containers:
      - name: client
        image: ghcr.io/spiffe/spire-agent:1.11.2
        command: ["/bin/sh", "/scripts/client.sh"]
        env:
        - name: TARGET_HOST
          value: "$SERVER_IP"
        volumeMounts:
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
          readOnly: true
        - name: client-script
          mountPath: /scripts
      volumes:
      - name: spire-agent-socket
        hostPath:
          path: /run/spire/sockets
          type: Directory
      - name: client-script
        configMap:
          name: client-script
          defaultMode: 0755
YAML

kubectl --context=$CLUSTER_C_CONTEXT apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: test-cross
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: client-c
  namespace: test-cross
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-script
  namespace: test-cross
data:
  client.sh: |
    #!/bin/sh
    set -e
    echo "=== Client C Starting ==="
    apk add --no-cache curl
    sleep 5
    echo "=== Our SPIFFE ID ==="
    /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock | grep "SPIFFE ID"
    TARGET_HOST=\${TARGET_HOST:-"$SERVER_IP"}
    echo "=== Testing Connection ==="
    counter=0
    while true; do
      counter=\$((counter + 1))
      echo "--- Test #\$counter at \$(date) ---"
      if curl -s -m 5 "http://\$TARGET_HOST:8080" > /tmp/response.html; then
        echo "✓ SUCCESS! Connected"
        grep "SPIFFE ID" /tmp/response.html || true
      else
        echo "✗ Failed"
      fi
      sleep 30
    done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-c
  namespace: test-cross
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client-c
  template:
    metadata:
      labels:
        app: client-c
    spec:
      serviceAccountName: client-c
      containers:
      - name: client
        image: ghcr.io/spiffe/spire-agent:1.11.2
        command: ["/bin/sh", "/scripts/client.sh"]
        env:
        - name: TARGET_HOST
          value: "$SERVER_IP"
        volumeMounts:
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
          readOnly: true
        - name: client-script
          mountPath: /scripts
      volumes:
      - name: spire-agent-socket
        hostPath:
          path: /run/spire/sockets
          type: Directory
      - name: client-script
        configMap:
          name: client-script
          defaultMode: 0755
YAML

kubectl --context=$CLUSTER_B_CONTEXT wait --for=condition=ready pod -l app=client-b -n test-cross --timeout=120s
kubectl --context=$CLUSTER_C_CONTEXT wait --for=condition=ready pod -l app=client-c -n test-cross --timeout=120s
echo_success "Clients deployed"

echo_step "Step 4: Checking results (waiting 15 seconds)..."
sleep 15

echo ""
echo "========== SERVER LOGS (Cluster A) =========="
kubectl --context=$CLUSTER_A_CONTEXT logs -n test-cross -l app=server-a --tail=15

echo ""
echo "========== CLIENT B LOGS (Cluster B -> A) =========="
kubectl --context=$CLUSTER_B_CONTEXT logs -n test-cross -l app=client-b --tail=15

echo ""
echo "========== CLIENT C LOGS (Cluster C -> A) =========="
kubectl --context=$CLUSTER_C_CONTEXT logs -n test-cross -l app=client-c --tail=15

echo ""
echo_success "Test complete! Check above for '✓ SUCCESS!' messages"
