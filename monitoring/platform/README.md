# Kubereats Platform Monitoring

These manifests add platform-specific monitoring on top of the existing `kube-prometheus-stack` installation.

The live cluster currently has:

- ArgoCD in `argocd`
- CoreDNS in `kube-system`
- kube-prometheus-stack in `monitoring`

The live cluster currently does not have an ingress controller, MetalLB, cert-manager, external-dns, StorageClass, PV, or PVC. Related dashboards and alert rules are still included as dormant checks where possible so they start showing data when those components are added.

## Applied Manifests

```bash
kubectl apply -k monitoring/platform
```

## Private Prometheus Access

Central Grafana on `10.250.0.4` reads the cluster Prometheus through the existing private NodePort service:

```text
http://192.168.17.11:30990
```

The service is `monitoring/kube-prometheus-stack-prometheus-federation`. It is reachable on the internal Kubernetes node IPs only. Firewall policy should allow only `10.250.0.4/32` to reach TCP `30990` on Kubernetes node IPs.

Do not expose Prometheus or node-exporter to the public internet.

## Verification

```bash
kubectl get servicemonitor,prometheusrule -n monitoring
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Then query Prometheus:

```bash
curl -s http://127.0.0.1:9090/api/v1/targets
```

Expected target groups include:

- `node-exporter`
- `kube-state-metrics`
- `kubelet`
- `coredns`
- `argocd-metrics`
- `argocd-server-metrics`
- `argocd-repo-server`
- `argocd-applicationset-controller`
- `argocd-notifications-controller-metrics`

`argocd-dex-server` exposes a metrics port in the service definition, but the target did not return healthy metrics during validation, so it is intentionally not scraped by this manifest.
