resource "proxmox_vm_qemu" "site1_app" {

  name        = "site1-app"
  target_node = "vm1"
  vmid        = 101

  clone = "VM1-GR37"

  cores  = 2
  memory = 2048

  network {
    model  = "virtio"
    bridge = "vmbr137"
  }

}