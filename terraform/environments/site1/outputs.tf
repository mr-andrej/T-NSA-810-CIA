output "pfsense_vmid" {
  description = "VM ID de pfSense"
  value       = proxmox_virtual_environment_vm.pfsense.vm_id
}

output "ubuntu_db_vmid" {
  description = "VM ID de la DB"
  value       = proxmox_virtual_environment_vm.ubuntu_db.vm_id
}

output "ubuntu_app_vmid" {
  description = "VM ID de l'App"
  value       = proxmox_virtual_environment_vm.ubuntu_app.vm_id
}
