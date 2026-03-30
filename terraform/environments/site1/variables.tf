variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox (ex: https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_username" {
  description = "Utilisateur Proxmox (ex: root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Mot de passe Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Nom du noeud Proxmox cible"
  type        = string
  default     = "vm4"
}

variable "storage_pool" {
  description = "Pool de stockage Proxmox (ex: local-lvm, local-zfs)"
  type        = string
  default     = "local-lvm"
}

# ISOs — à remplacer par les vrais noms visibles dans Proxmox > Storage > ISO
variable "pfsense_iso" {
  description = "Nom de l'ISO pfSense dans le stockage Proxmox"
  type        = string
  default     = "local:iso/pfSense-CE-2.7.2-RELEASE-amd64.iso" # <-- REMPLACE ICI
}

variable "ubuntu_iso" {
  description = "Nom de l'ISO Ubuntu dans le stockage Proxmox"
  type        = string
  default     = "local:iso/ubuntu-22.04-live-server-amd64.iso" # <-- REMPLACE ICI
}
