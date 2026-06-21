# Policy: ansible-netbox
# Used by the Ansible AppRole "ansible-netbox" for NetBox deploy/populate/sync.

path "secret/data/netbox/*" {
  capabilities = ["read"]
}

path "secret/metadata/netbox/*" {
  capabilities = ["read", "list"]
}
