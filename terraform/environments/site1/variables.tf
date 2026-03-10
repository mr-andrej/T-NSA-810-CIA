variable "pm_password" {
  type      = string
  sensitive = true
}

variable "target_node" {
  default = "vm3"
}

variable "bridge" {
  default = "vmbr137"
}

variable "storage" {
  default = "local-lvm"
}

variable "template" {
  default = "ubuntu-22.04-template"
}