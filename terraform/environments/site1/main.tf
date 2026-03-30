# ──────────────────────────────────────────────
#  VM 1 — pfSense
# ──────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "pfsense" {
  node_name = var.proxmox_node
  vm_id     = 401
  name      = "vm4-pfsense"
  started   = false
  tags      = ["pfsense"]

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Disque principal
  disk {
    datastore_id = var.storage_pool
    file_format  = "raw"
    interface    = "virtio0"
    size         = 20 # Go
  }

  # Lecteur CD-ROM avec l'ISO pfSense
  cdrom {
    file_id   = var.pfsense_iso
    interface = "ide2"
  }

  # Interface WAN (vers le réseau de l'école)
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Interface LAN (réseau interne — vmbr137)
  network_device {
    bridge = "vmbr137"
    model  = "virtio"
  }

  boot_order = ["ide2", "virtio0"]
}

# ──────────────────────────────────────────────
#  VM 2 — Ubuntu (DB)
# ──────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "ubuntu_db" {
  node_name = var.proxmox_node
  vm_id     = 402
  name      = "vm4-db"
  started   = false
  tags      = ["DB"]

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048 # 2 Go RAM
  }

  disk {
    datastore_id = var.storage_pool
    file_format  = "raw"
    interface    = "virtio0"
    size         = 30
  }

  cdrom {
    file_id   = var.ubuntu_iso
    interface = "ide2"
  }

  # Sur le LAN interne (vmbr137)
  network_device {
    bridge = "vmbr137"
    model  = "virtio"
  }

  boot_order = ["ide2", "virtio0"]
}

# ──────────────────────────────────────────────
#  VM 3 — Ubuntu (App)
# ──────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "ubuntu_app" {
  node_name = var.proxmox_node
  vm_id     = 403
  name      = "vm4-app"
  started   = false
  tags      = ["app"]

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.storage_pool
    file_format  = "raw"
    interface    = "virtio0"
    size         = 25 # Go
  }

  cdrom {
    file_id   = var.ubuntu_iso
    interface = "ide2"
  }

  # Sur le LAN interne (vmbr137)
  network_device {
    bridge = "vmbr137"
    model  = "virtio"
  }

  boot_order = ["ide2", "virtio0"]
}
