# Kubereats Kubernetes On-Prem Architecture

This repository provisions only the on-prem Kubernetes VM layer on Proxmox and keeps the existing kubeadm Ansible flow working. Database infrastructure is intentionally out of scope here: no PostgreSQL, DB VMs, Patroni, pgBackRest, GCS backup, Redis, or related resources are managed by this project.

## Proxmox Hosts

| Proxmox host | Management IP | Hardware | Failure domain |
| --- | --- | --- | --- |
| `pve-a` | `192.168.16.211` | 32 cores / 64 GB RAM | `pve-a` |
| `pve-b` | `192.168.16.212` | 32 cores / 64 GB RAM | `pve-b` |

The on-prem network is `192.168.16.0/20`. Kubernetes node IPs are allocated from `192.168.17.11-192.168.17.39`.

## VM Inventory

| VM name | Proxmox host | IP | Role | Managed here |
| --- | --- | --- | --- | --- |
| `k8s-cp-01` | `pve-a` | `192.168.17.11` | kubeadm bootstrap control plane | yes |
| `k8s-cp-02` | `pve-b` | `192.168.17.12` | second control-plane candidate | yes |
| `k8s-cp-03` | external / GCP / another host | TBD | future kubeadm control plane in third failure domain | no |
| `k8s-worker-a1` | `pve-a` | `192.168.17.21` | worker + edge ingress capable | yes |
| `k8s-worker-a2` | `pve-a` | `192.168.17.22` | worker + edge ingress capable | yes |
| `k8s-worker-b1` | `pve-b` | `192.168.17.31` | worker + edge ingress capable | yes |
| `k8s-worker-b2` | `pve-b` | `192.168.17.32` | worker + edge ingress capable | yes |

## IP Plan

| Purpose | Address or range | Notes |
| --- | --- | --- |
| On-prem network | `192.168.16.0/20` | Existing LAN |
| Kubernetes node range | `192.168.17.11-192.168.17.39` | VM static addresses |
| Kubernetes API VIP | `192.168.17.230` | Reserved only, not configured by this repo |
| Optional MetalLB pool | `192.168.17.240-192.168.17.249` | Reserved for possible internal/demo use later |

MetalLB is not part of the production external ingress path in this phase.

## VM Sizing Defaults

| Node type | vCPU | RAM | OS disk |
| --- | ---: | ---: | ---: |
| Control plane | 4 | 8192 MB | 40 GB |
| Worker | 8 | 16384 MB | 60 GB |

These are Terraform variables in `terraform/vars.tf` and can be overridden with `terraform.tfvars` or `TF_VAR_*` values.

## Production Ingress Plan

Production traffic is expected to use GCP Global HTTPS Load Balancer with a Hybrid NEG pointing at node IP and NodePort endpoints:

```text
192.168.17.21:30443
192.168.17.22:30443
192.168.17.31:30443
192.168.17.32:30443
```

Expected path:

```text
GCP Global HTTPS Load Balancer
  -> Hybrid NEG with 4 NodeIP:NodePort endpoints
  -> ingress-nginx DaemonSet on all 4 edge workers
  -> Kubernetes Services
  -> Application Pods
```

This repository does not create GCP load balancer, Hybrid NEG, service account, or firewall resources. It also does not install ingress-nginx. The four workers are prepared and documented as edge ingress-capable nodes for a later add-on step.

## Control Plane HA Status

The current Ansible flow bootstraps one kubeadm control plane through `ansible/k8s-master.yml`. For compatibility, the `k8s_master` inventory group contains only `k8s-cp-01`.

`k8s-cp-02` is provisioned and has Kubernetes dependencies installed as a control-plane candidate, but it is not automatically joined as a real control-plane node. Adding it properly requires a stable `controlPlaneEndpoint`, certificate handling, and a `kubeadm join --control-plane` flow.

The final HA design also requires `k8s-cp-03` in a third failure domain. That node is external and is not provisioned by this Proxmox Terraform module.

## Terraform Command Sequence

From the repository root:

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Provide secrets and local settings outside git. For example:

```bash
export TF_VAR_pm_password='...'
export TF_VAR_ssh_public_key="$(cat ../tf-cloud-init.pub)"
```

Or use a local `terraform.tfvars` file that is not committed.

## Ansible Command Sequence

After Terraform provisions the VMs, from the repository root:

```bash
chmod 400 tf-cloud-init
cd ansible
ansible-playbook k8s-setup.yml -i k8s-inventory.yml --key-file ../tf-cloud-init
ansible-playbook k8s-master.yml -i k8s-inventory.yml --key-file ../tf-cloud-init
cd ..
./join-nodes.sh
```

The setup playbook runs against all six VMs. The master playbook initializes only `k8s-cp-01`. The join script joins these worker nodes:

```text
k8s-worker-a1 192.168.17.21
k8s-worker-a2 192.168.17.22
k8s-worker-b1 192.168.17.31
k8s-worker-b2 192.168.17.32
```

## Labels To Apply Later

After the cluster exists, label edge workers for ingress-nginx scheduling, monitoring, and failure-domain awareness:

```bash
kubectl label node k8s-worker-a1 kubereats.io/edge=true kubereats.io/failure-domain=pve-a
kubectl label node k8s-worker-a2 kubereats.io/edge=true kubereats.io/failure-domain=pve-a
kubectl label node k8s-worker-b1 kubereats.io/edge=true kubereats.io/failure-domain=pve-b
kubectl label node k8s-worker-b2 kubereats.io/edge=true kubereats.io/failure-domain=pve-b
```

## Known Limitations

- Two on-prem Proxmox hosts provide only two physical failure domains.
- Full HA control plane requires a third control-plane node in a third failure domain.
- The current Ansible flow initializes one bootstrap control plane and does not implement multi-control-plane kubeadm join.
- The Kubernetes API VIP `192.168.17.230` is reserved but not configured.
- MetalLB is not used for production external ingress in this design.
- GCP resources are not managed in this repository.
- Database and cache infrastructure are intentionally out of scope.
