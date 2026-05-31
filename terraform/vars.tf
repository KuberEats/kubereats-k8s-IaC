variable "pm_api_url" {
  description = "Proxmox cluster API URL."
  type        = string
  default     = "https://192.168.16.211:8006/api2/json"
}

variable "pm_tls_insecure" {
  description = "Set true when Proxmox uses a self-signed TLS certificate."
  type        = bool
  default     = true
}

variable "pm_user" {
  description = "Proxmox username including realm, for example root@pam. Leave null when using only API tokens."
  type        = string
  default     = "root@pam"
  nullable    = true
}

variable "pm_password" {
  description = "Proxmox password. Prefer passing this via TF_VAR_pm_password or a local tfvars file excluded from git."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "pm_api_token_id" {
  description = "Optional Proxmox API token ID in the form <username>@pam!<tokenId>."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Optional Proxmox API token secret."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "proxmox_hosts" {
  description = "Proxmox hosts and failure-domain metadata available for Kubernetes VM placement."
  type = map(object({
    node_name     = string
    management_ip = string
  }))
  default = {
    pve-a = {
      node_name     = "pve-a"
      management_ip = "192.168.16.211"
    }
    pve-b = {
      node_name     = "pve-b"
      management_ip = "192.168.16.212"
    }
  }
}

variable "vm_template_name" {
  description = "Ubuntu 24.04 cloud-init VM template to clone."
  type        = string
  default     = "VM9000"
}

variable "network_bridge" {
  description = "Proxmox bridge used by Kubernetes VMs."
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default IPv4 gateway for Kubernetes VMs."
  type        = string
  default     = "192.168.16.1"
}

variable "dns_servers" {
  description = "DNS servers assigned through cloud-init."
  type        = list(string)
  default     = ["192.168.16.1", "8.8.8.8"]
}

variable "k8s_node_cidr_prefix" {
  description = "IPv4 CIDR prefix length for Kubernetes node addresses."
  type        = number
  default     = 20
}

variable "cloudinit_storage" {
  description = "Proxmox storage for the cloud-init drive."
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_storage" {
  description = "Proxmox storage for VM OS disks."
  type        = string
  default     = "local-lvm"
}

variable "ssh_user" {
  description = "Cloud-init user created on each VM."
  type        = string
  default     = "kubereats"
}

variable "ssh_password" {
  description = "Optional cloud-init password. Prefer SSH keys and pass this only through local variables when needed."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key injected into each VM by cloud-init."
  type        = string
  default     = ""
  sensitive   = true
}

variable "control_plane_vm_size" {
  description = "Default control-plane VM sizing. disk_size is in GB and memory is in MB."
  type = object({
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    cores     = 4
    memory    = 8192
    disk_size = 40
  }
}

variable "worker_vm_size" {
  description = "Default worker VM sizing. disk_size is in GB and memory is in MB."
  type = object({
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    cores     = 8
    memory    = 16384
    disk_size = 60
  }
}

variable "k8s_control_plane_nodes" {
  description = "Control-plane VMs managed by this Proxmox module. k8s-cp-02 is prepared as a future control-plane candidate."
  type = map(object({
    ip             = string
    vmid           = number
    failure_domain = string
    bootstrap      = bool
  }))
  default = {
    k8s-cp-01 = {
      ip             = "192.168.17.11"
      vmid           = 1711
      failure_domain = "pve-a"
      bootstrap      = true
    }
    k8s-cp-02 = {
      ip             = "192.168.17.12"
      vmid           = 1712
      failure_domain = "pve-b"
      bootstrap      = false
    }
  }
}

variable "k8s_worker_nodes" {
  description = "Worker VMs managed by this Proxmox module. edge_ingress workers are intended for ingress-nginx DaemonSet placement later."
  type = map(object({
    ip             = string
    vmid           = number
    failure_domain = string
    edge_ingress   = bool
  }))
  default = {
    k8s-worker-a1 = {
      ip             = "192.168.17.21"
      vmid           = 1721
      failure_domain = "pve-a"
      edge_ingress   = true
    }
    k8s-worker-a2 = {
      ip             = "192.168.17.22"
      vmid           = 1722
      failure_domain = "pve-a"
      edge_ingress   = true
    }
    k8s-worker-b1 = {
      ip             = "192.168.17.31"
      vmid           = 1731
      failure_domain = "pve-b"
      edge_ingress   = true
    }
    k8s-worker-b2 = {
      ip             = "192.168.17.32"
      vmid           = 1732
      failure_domain = "pve-b"
      edge_ingress   = true
    }
  }
}

variable "ingress_nodeport" {
  description = "NodePort planned for ingress-nginx HTTPS traffic behind the GCP Hybrid NEG."
  type        = number
  default     = 30443
}

variable "reserved_k8s_api_vip" {
  description = "Reserved Kubernetes API VIP for future HA control-plane endpoint documentation."
  type        = string
  default     = "192.168.17.230"
}

variable "external_nodes_not_managed_here" {
  description = "External or future nodes that are intentionally not provisioned by this Proxmox module."
  type = list(object({
    name     = string
    location = string
    ip       = string
    role     = string
  }))
  default = [
    {
      name     = "k8s-cp-03"
      location = "external / GCP / another host"
      ip       = "TBD"
      role     = "future kubeadm control plane in a third failure domain"
    }
  ]
}
