# Kubereats Kubernetes Monitoring

This directory defines the cluster-local Kubernetes monitoring layer for Kubereats.

It uses `prometheus-community/kube-prometheus-stack` in the `monitoring` namespace to collect Kubernetes node, pod, deployment, kubelet, cAdvisor, kube-state-metrics, and node-exporter metrics.

Cluster-local Grafana is disabled because central Grafana already runs on the monitoring VM at `10.250.0.4`. Do not expose Prometheus, Alertmanager, or any cluster-local monitoring service publicly.

## Install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/kube-prometheus-stack-values.yaml

kubectl apply -f monitoring/kubereats-k8s-alerts.yaml
```

## Validate Rendering

```bash
helm template kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f monitoring/kube-prometheus-stack-values.yaml >/tmp/kps-rendered.yaml
```

## Verify Runtime

```bash
kubectl get ns monitoring
kubectl get pods -n monitoring -o wide
kubectl get svc -n monitoring
kubectl get servicemonitor,prometheusrule -A
```

Port-forward Prometheus only from a trusted workstation or admin shell:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

In Prometheus, verify these targets are `UP`:

- kubelet
- cAdvisor
- kube-state-metrics
- node-exporter for every Kubernetes node

## Storage

No Prometheus `storageSpec` is set yet. This keeps the deployment portable across the current self-hosted cluster where a stable default `StorageClass` was not verified from this shell. Prometheus retention is set to `7d`, but data is ephemeral until a durable storage class is selected and configured.
