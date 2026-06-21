# Policy: ansible-deploy
# Used by the Ansible AppRole "ansible-deploy" for infrastructure playbooks
# (Proxmox snapshots, bastion users, managed VMs).

path "secret/data/infra/*" {
  capabilities = ["read"]
}

path "secret/metadata/infra/*" {
  capabilities = ["read", "list"]
}
