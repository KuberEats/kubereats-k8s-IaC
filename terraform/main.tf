terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc4"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_tls_insecure = var.pm_tls_insecure

  pm_user     = var.pm_user
  pm_password = var.pm_password

  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}

locals {
  k8s_control_plane_nodes = {
    for name, node in var.k8s_control_plane_nodes : name => merge(node, {
      name         = name
      node_type    = "control_plane"
      edge_ingress = false
      role         = node.bootstrap ? "kubeadm bootstrap control plane" : "control-plane candidate"
    })
  }

  k8s_worker_nodes = {
    for name, node in var.k8s_worker_nodes : name => merge(node, {
      name      = name
      node_type = "worker"
      role      = node.edge_ingress ? "worker + edge ingress capable" : "worker"
    })
  }

  k8s_vms = merge(local.k8s_control_plane_nodes, local.k8s_worker_nodes)

  hybrid_neg_ingress_endpoints = [
    for name, node in local.k8s_worker_nodes : "${node.ip}:${var.ingress_nodeport}"
    if node.edge_ingress
  ]
}

resource "proxmox_vm_qemu" "k8s_vm" {
  for_each = local.k8s_vms

  name        = each.value.name
  desc        = each.value.role
  target_node = var.proxmox_hosts[each.value.failure_domain].node_name
  clone       = var.vm_template_name

  cores   = each.value.node_type == "control_plane" ? var.control_plane_vm_size.cores : var.worker_vm_size.cores
  sockets = 1
  memory  = each.value.node_type == "control_plane" ? var.control_plane_vm_size.memory : var.worker_vm_size.memory
  agent   = 1

  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.cloudinit_storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size      = each.value.node_type == "control_plane" ? var.control_plane_vm_size.disk_size : var.worker_vm_size.disk_size
          cache     = "writeback"
          storage   = var.vm_disk_storage
          replicate = true
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
  }

  boot       = "order=scsi0"
  ipconfig0  = "ip=${each.value.ip}/${var.k8s_node_cidr_prefix},gw=${var.gateway}"
  nameserver = join(" ", var.dns_servers)
  os_type    = "cloud-init"
  vmid       = each.value.vmid

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key

  serial {
    id   = 0
    type = "socket"
  }
}

output "k8s_control_plane_nodes" {
  description = "On-prem Kubernetes control-plane VM inventory managed by this Terraform module."
  value = [
    for name, node in local.k8s_control_plane_nodes : {
      name           = node.name
      ip             = node.ip
      proxmox_node   = var.proxmox_hosts[node.failure_domain].node_name
      role           = node.role
      failure_domain = node.failure_domain
      bootstrap      = node.bootstrap
    }
  ]
}

output "k8s_worker_nodes" {
  description = "Kubernetes worker VM inventory managed by this Terraform module."
  value = [
    for name, node in local.k8s_worker_nodes : {
      name           = node.name
      ip             = node.ip
      proxmox_node   = var.proxmox_hosts[node.failure_domain].node_name
      role           = node.role
      edge_ingress   = node.edge_ingress
      failure_domain = node.failure_domain
    }
  ]
}

output "hybrid_neg_ingress_endpoints" {
  description = "NodeIP:NodePort endpoints intended for GCP Hybrid NEG backends."
  value       = local.hybrid_neg_ingress_endpoints
}

output "reserved_k8s_api_vip" {
  description = "Reserved Kubernetes API VIP for the future HA control-plane endpoint. Not configured by this module."
  value       = var.reserved_k8s_api_vip
}

output "external_nodes_not_managed_here" {
  description = "Planned cluster nodes outside this Proxmox Terraform module."
  value       = var.external_nodes_not_managed_here
}
