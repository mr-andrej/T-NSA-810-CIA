terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://ns3050272.ip-51-255-76.eu:8006/api2/json"
  pm_user         = "GR37@pve"
  pm_password     = var.pm_password
  pm_tls_insecure = true
}