#!/bin/bash
set -e

echo "Updating StatefulSets to use hostPort for federation endpoint..."

# Update Cluster A
kubectl --context=kind-cluster-a apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spire-server
  namespace: spire
  labels:
    app: spire-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spire-server
  serviceName: spire-server
  template:
    metadata:
      namespace: spire
      labels:
        app: spire-server
    spec:
      serviceAccountName: spire-server
      securityContext:
        fsGroup: 1000
      containers:
        - name: spire-server
          image: ghcr.io/spiffe/spire-server:1.11.2
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
              name: grpc
            - containerPort: 8443
              name: federation
              hostPort: 8443
            - containerPort: 8080
              name: healthz
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
          livenessProbe:
            httpGet:
              path: /live
              port: 8080
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
  volumeClaimTemplates:
    - metadata:
        name: spire-data
        namespace: spire
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
EOF

# Update Cluster B
kubectl --context=kind-cluster-b apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spire-server
  namespace: spire
  labels:
    app: spire-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spire-server
  serviceName: spire-server
  template:
    metadata:
      namespace: spire
      labels:
        app: spire-server
    spec:
      serviceAccountName: spire-server
      securityContext:
        fsGroup: 1000
      containers:
        - name: spire-server
          image: ghcr.io/spiffe/spire-server:1.11.2
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
              name: grpc
            - containerPort: 8443
              name: federation
              hostPort: 8443
            - containerPort: 8080
              name: healthz  
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
          livenessProbe:
            httpGet:
              path: /live
              port: 8080
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
  volumeClaimTemplates:
    - metadata:
        name: spire-data
        namespace: spire
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
EOF

# Update Cluster C
kubectl --context=kind-cluster-c apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spire-server
  namespace: spire
  labels:
    app: spire-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spire-server
  serviceName: spire-server
  template:
    metadata:
      namespace: spire
      labels:
        app: spire-server
    spec:
      serviceAccountName: spire-server
      securityContext:
        fsGroup: 1000
      containers:
        - name: spire-server
          image: ghcr.io/spiffe/spire-server:1.11.2
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
              name: grpc
            - containerPort: 8443
              name: federation
              hostPort: 8443
            - containerPort: 8080
              name: healthz
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
          livenessProbe:
            httpGet:
              path: /live
              port: 8080
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
  volumeClaimTemplates:
    - metadata:
        name: spire-data
        namespace: spire
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
EOF

echo ""
echo "Waiting for StatefulSets to rollout..."
kubectl --context=kind-cluster-a rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-b rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-c rollout status -n spire statefulset/spire-server --timeout=120s

echo ""
echo "Updating ConfigMaps to use port 8443 (not 30443)..."

# Get cluster IPs
NETWORK_ID=$(docker network inspect kind-spire-federation -f '{{.Id}}')
CLUSTER_A_IP=$(docker inspect cluster-a-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")
CLUSTER_B_IP=$(docker inspect cluster-b-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")
CLUSTER_C_IP=$(docker inspect cluster-c-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")

echo "Using IPs:"
echo "  Cluster A: $CLUSTER_A_IP:8443"
echo "  Cluster B: $CLUSTER_B_IP:8443"
echo "  Cluster C: $CLUSTER_C_IP:8443"

# Update Cluster A ConfigMap
kubectl --context=kind-cluster-a apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server
  namespace: spire
data:
  server.conf: |
    server {
      bind_address = "0.0.0.0"
      bind_port = "8081"
      socket_path = "/tmp/spire-server/private/api.sock"
      trust_domain = "bb-team.org"
      data_dir = "/run/spire/data"
      log_level = "DEBUG"
      ca_key_type = "rsa-2048"
      ca_subject = {
          country = ["US"],
          organization = ["SPIFFE"],
          common_name = "",
      }
      federation {
        bundle_endpoint {
          address = "0.0.0.0"
          port = 8443
        }
        federates_with "dev-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_B_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://dev-team.org/spire/server"
          }
        }
        federates_with "devops-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_C_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://devops-team.org/spire/server"
          }
        }
      }
    }
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "/run/spire/data/datastore.sqlite3"
        }
      }
      NodeAttestor "k8s_psat" {
        plugin_data {
          clusters = {
            "kind-cluster-a" = {
              service_account_allow_list = ["spire:spire-agent"]
              audience = ["spire-server"]
            }
          }
        }
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }
      Notifier "k8sbundle" {
        plugin_data {
          namespace = "spire"
          config_map = "spire-bundle"
        }
      }
    }
    health_checks {
      listener_enabled = true
      bind_address = "0.0.0.0"
      bind_port = "8080"
      live_path = "/live"
      ready_path = "/ready"
    }
EOF

# Update Cluster B ConfigMap
kubectl --context=kind-cluster-b apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server
  namespace: spire
data:
  server.conf: |
    server {
      bind_address = "0.0.0.0"
      bind_port = "8081"
      socket_path = "/tmp/spire-server/private/api.sock"
      trust_domain = "dev-team.org"
      data_dir = "/run/spire/data"
      log_level = "DEBUG"
      ca_key_type = "rsa-2048"
      ca_subject = {
        country = ["US"],
        organization = ["SPIFFE"],
        common_name = "",
      }
      federation {
        bundle_endpoint {
          address = "0.0.0.0"
          port = 8443
        }
        federates_with "bb-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_A_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://bb-team.org/spire/server"
          }
        }
        federates_with "devops-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_C_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://devops-team.org/spire/server"
          }
        }
      }
    }    
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "/run/spire/data/datastore.sqlite3"
        }
      }
      NodeAttestor "k8s_psat" {
        plugin_data {
          clusters = {
            "kind-cluster-b" = {
              service_account_allow_list = ["spire:spire-agent"]
              audience = ["spire-server"]
            }
          }
        }
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }
      Notifier "k8sbundle" {
        plugin_data {
          namespace = "spire"
          config_map = "spire-bundle"
        }
      }
    }
    health_checks {
      listener_enabled = true
      bind_address = "0.0.0.0"
      bind_port = "8080"
      live_path = "/live"
      ready_path = "/ready"
    }
EOF

# Update Cluster C ConfigMap
kubectl --context=kind-cluster-c apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server
  namespace: spire
data:
  server.conf: |
    server {
      bind_address = "0.0.0.0"
      bind_port = "8081"
      socket_path = "/tmp/spire-server/private/api.sock"
      trust_domain = "devops-team.org"
      data_dir = "/run/spire/data"
      log_level = "DEBUG"
      ca_key_type = "rsa-2048"
      ca_subject = {
        country = ["US"],
        organization = ["SPIFFE"],
        common_name = "",
      }
      federation {
        bundle_endpoint {
          address = "0.0.0.0"
          port = 8443
        }
        federates_with "bb-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_A_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://bb-team.org/spire/server"
          }
        }
        federates_with "dev-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_B_IP}:8443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://dev-team.org/spire/server"
          }
        }
      }
    } 
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "/run/spire/data/datastore.sqlite3"
        }
      }
      NodeAttestor "k8s_psat" {
        plugin_data {
          clusters = {
            "kind-cluster-c" = {
              service_account_allow_list = ["spire:spire-agent"]
              audience = ["spire-server"]
            }
          }
        }
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }
      Notifier "k8sbundle" {
        plugin_data {
          namespace = "spire"
          config_map = "spire-bundle"
        }
      }
    }
    health_checks {
      listener_enabled = true
      bind_address = "0.0.0.0"
      bind_port = "8080"
      live_path = "/live"
      ready_path = "/ready"
    }
EOF

echo ""
echo "Restarting SPIRE servers to pick up new config..."
kubectl --context=kind-cluster-a rollout restart -n spire statefulset/spire-server
kubectl --context=kind-cluster-b rollout restart -n spire statefulset/spire-server
kubectl --context=kind-cluster-c rollout restart -n spire statefulset/spire-server

kubectl --context=kind-cluster-a rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-b rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-c rollout status -n spire statefulset/spire-server --timeout=120s

echo ""
echo "=========================================="
echo "Setup Complete with hostPort!"
echo "=========================================="
echo ""
echo "Federation endpoints:"
echo "  Cluster A (bb-team.org):     $CLUSTER_A_IP:8443"
echo "  Cluster B (dev-team.org):    $CLUSTER_B_IP:8443"
echo "  Cluster C (devops-team.org): $CLUSTER_C_IP:8443"
echo ""
echo "Verifying federation in 10 seconds..."
sleep 10

kubectl --context=kind-cluster-c logs -n spire -l app=spire-server --tail=30 | grep -i "bundle\|federation"
