# https://registry.terraform.io/providers/bpg/proxmox/latest/docs
terraform {
  required_version = ">= 1.14.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.99.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password

  # because self-signed TLS certificate is in use
  insecure = true
}
