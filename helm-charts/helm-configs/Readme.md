# Helm Chart Installation Commands

This document contains the Helm installation commands for the GPU-enabled Kubernetes cluster components.

---

## 1. NVIDIA GPU Operator

Manages GPU drivers, container toolkit, and device plugins automatically.

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator v25.10.1
# --wait ensures all pods are ready before command returns
helm install gpu-operator nvidia/gpu-operator \
  --version v25.10.1 \
  --namespace gpu-operator \
  --create-namespace \
  --wait
```

---

## 2. KAI Scheduler

GPU-aware scheduler with team-based quotas and fair-share scheduling.

```bash
# Install KAI Scheduler with GPU sharing enabled
# This deploys the scheduler as an OCI artifact from GitHub Container Registry
helm upgrade -i kai-scheduler oci://ghcr.io/nvidia/kai-scheduler/kai-scheduler \
  -n kai-scheduler \
  --create-namespace \
  --set "global.gpuSharing=true" \
  --version v0.12.0  --wait
kubectl create -f queue.yaml   
```

---

## 3. JupyterHub

Multi-user Jupyter notebook server for interactive development.

```bash
# Add JupyterHub Helm repository
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# Install JupyterHub with custom values
# Replace jupyterhub-values.yaml with your configuration file
helm install jupyterhub jupyterhub/jupyterhub \
  --version 4.3.2 \
  --namespace jupyterhub \
  --create-namespace \
  -f jupyterhub-values.yaml
```

---

## 4. Prometheus Stack (Optional)

Monitoring and alerting for GPU metrics via DCGM Exporter.

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus with custom values for GPU metrics
helm install prom-operator prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --version 28.3.0 \
  -f prom-values.yaml --wait
```
 
---

## 5. Grafana (Optional)

Visualization dashboard for Prometheus metrics.

```bash 
# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Grafana for metrics visualization
helm install grafana grafana/grafana \
  --namespace monitoring \
  --version 10.5.5 --wait
```

---

## Version Matrix

| Component | Version | Notes |
|-----------|---------|-------|
| GPU Operator | v25.10.1 | Requires K8s >= 1.16 |
| KAI Scheduler | v0.12.0 | GPU-aware scheduling |
| JupyterHub | 4.3.2 | Multi-user notebooks |
| Prometheus | 28.3.0 | GPU metrics monitoring |
| Grafana | 10.5.5 | Metrics visualization |