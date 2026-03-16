terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.5"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Disque principal
resource "libvirt_volume" "proxmox_disk" {
  name   = "proxmox1.qcow2"
  pool   = "default"
  capacity   = 64424509440  # 60 Go
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# ISO Proxmox
resource "libvirt_volume" "proxmox_iso" {
  name   = "proxmox.iso"
  pool   = "default"
  target = {
    format = {
      type = "raw"
    }
  }
  create = {
    content = {
      url = "/iso-proxmox/proxmox-ve_9.1-1.iso"
    }
  }
}

# VM
resource "libvirt_domain" "proxmox1" {
  name   = "proxmox1"
  memory = 10240
  vcpu   = 6
  type   = "kvm"

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [
      {
        dev = "cdrom"
      },
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = "default"
            volume = libvirt_volume.proxmox_disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        source = {
          volume = {
            pool   = "default"
            volume = libvirt_volume.proxmox_iso.name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        readonly = true
      }
    ]

    interfaces = [
      {
        model  = { type = "virtio" }
        source = { network = { network = "default" } }
      }
    ]

    # Console série pour voir le boot
    consoles = [
      {
        type        = "pty"
        target_port = "0"
        target_type = "serial"
      }
    ]
  }
}
