# SPIRE and SPIFFE Setup on Kubernetes

This document provides step-by-step instructions for deploying SPIRE and SPIFFE on a Kubernetes cluster, registering workloads, and testing SPIFFE IDs.

---

## 1. Configure Kubernetes Namespace for SPIRE Components

Create the `spire` namespace where SPIRE Server and SPIRE Agent will be deployed:

```bash
kubectl create namespace spire
kubectl get namespaces

