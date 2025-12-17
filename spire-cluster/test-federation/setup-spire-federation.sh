#!/bin/bash
set -e

echo "Creating shared Docker network..."
docker network create kind-spire-federation 2>/dev/null || echo "Network already exists"

echo "Connecting clusters to shared network..."
docker network connect kind-spire-federation cluster-a-control-plane 2>/dev/null || true
docker network connect kind-spire-federation cluster-b-control-plane 2>/dev/null || true
docker network connect kind-spire-federation cluster-c-control-plane 2>/dev/null || true

echo "Getting cluster IPs..."
NETWORK_ID=$(docker network inspect kind-spire-federation -f '{{.Id}}')

CLUSTER_A_IP=$(docker inspect cluster-a-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")
CLUSTER_B_IP=$(docker inspect cluster-b-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")
CLUSTER_C_IP=$(docker inspect cluster-c-control-plane -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$NETWORK_ID\"}}{{.IPAddress}}{{end}}{{end}}")

echo "Cluster A (bb-team.org): $CLUSTER_A_IP"
echo "Cluster B (dev-team.org): $CLUSTER_B_IP"
echo "Cluster C (devops-team.org): $CLUSTER_C_IP"

# Verify IPs are not empty
if [ -z "$CLUSTER_A_IP" ] || [ -z "$CLUSTER_B_IP" ] || [ -z "$CLUSTER_C_IP" ]; then
  echo "Error: Could not get all cluster IPs. Please check if clusters are connected to the network."
  exit 1
fi

# Update Cluster A ConfigMap
echo "  - Updating cluster-a (bb-team.org)..."
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
          bundle_endpoint_url = "https://${CLUSTER_B_IP}:30443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://dev-team.org/spire/server"
          }
        }
        federates_with "devops-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_C_IP}:30443"
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
echo "  - Updating cluster-b (dev-team.org)..."
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
          bundle_endpoint_url = "https://${CLUSTER_A_IP}:30443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://bb-team.org/spire/server"
          }
        }
        federates_with "devops-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_C_IP}:30443"
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
echo "  - Updating cluster-c (devops-team.org)..."
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
          bundle_endpoint_url = "https://${CLUSTER_A_IP}:30443"
          bundle_endpoint_profile "https_spiffe" {
            endpoint_spiffe_id = "spiffe://bb-team.org/spire/server"
          }
        }
        federates_with "dev-team.org" {
          bundle_endpoint_url = "https://${CLUSTER_B_IP}:30443"
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
echo "Restarting SPIRE servers..."
kubectl --context=kind-cluster-a rollout restart -n spire statefulset/spire-server
kubectl --context=kind-cluster-b rollout restart -n spire statefulset/spire-server
kubectl --context=kind-cluster-c rollout restart -n spire statefulset/spire-server

echo ""
echo "Waiting for rollouts to complete..."
kubectl --context=kind-cluster-a rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-b rollout status -n spire statefulset/spire-server --timeout=120s
kubectl --context=kind-cluster-c rollout status -n spire statefulset/spire-server --timeout=120s

echo ""
echo "=========================================="
echo "Federation setup complete!"
echo "=========================================="
echo ""
echo "Cluster IPs on shared network:"
echo "  Cluster A (bb-team.org):     $CLUSTER_A_IP:30443"
echo "  Cluster B (dev-team.org):    $CLUSTER_B_IP:30443"
echo "  Cluster C (devops-team.org): $CLUSTER_C_IP:30443"
echo ""
echo "To verify federation, run:"
echo "  kubectl --context=kind-cluster-c logs -n spire -l app=spire-server --tail=50 | grep -i bundle"
echo ""
