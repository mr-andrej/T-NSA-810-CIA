# Ansible — T-NSA-810-CIA

Ansible playbooks for managing school infrastructure VMs across Proxmox VE environments.

## Requirements

```bash
sudo apt install ansible python3-proxmoxer python3-requests
ansible-galaxy collection install community.proxmox
```

## Inventory

Hosts are defined in `inventory/hosts.yaml`. Fill in the SSH details for each VM:

```yaml
s1_db:
  ansible_host: <VM IP>
  ansible_user: <SSH user>
  proxmox_vmid: 2037
  proxmox_node: vm002
```

## Vault setup

Secrets are stored encrypted in `group_vars/all/vault.yaml`.

To set up for the first time:

```bash
cp group_vars/all/vault.yaml.example group_vars/all/vault.yaml
nano group_vars/all/vault.yaml  # fill in real values
ansible-vault encrypt group_vars/all/vault.yaml
```

`vault.yaml` is in `.gitignore` and must never be committed. Only `vault.yaml.example` is tracked by git.

To edit later:

```bash
ansible-vault edit group_vars/all/vault.yaml
```

### Vault variables

| Variable | Description |
|---|---|
| `vault_proxmox_api_password` | Proxmox API token secret for `GR37@pve!ansible` |

## Proxmox API token

The playbooks authenticate to the Proxmox API using a token (not a password).

To create the token:

1. Log into the Proxmox UI
2. **Datacenter → Permissions → API Tokens → Add**
   - User: `GR37@pve`
   - Token ID: `ansible`
   - Privilege Separation: unchecked
3. Copy the token secret and store it in the vault as `vault_proxmox_api_password`

## Playbooks

### `proxmox_snapshot.yaml`

Manages snapshots for VM `S1-DB` (vmid 2037) on `ns3183326.ip-146-59-253.eu`.

**Create a snapshot:**

```bash
ansible-playbook playbooks/proxmox_snapshot.yaml -e "snap_action=create snap_name=pre-mongo" --ask-vault-pass
```

**Restore a snapshot** (Proxmox will handle stopping and restarting the VM):

```bash
ansible-playbook playbooks/proxmox_snapshot.yaml -e "snap_action=restore snap_name=pre-mongo" --ask-vault-pass
```

**Delete a snapshot:**

```bash
ansible-playbook playbooks/proxmox_snapshot.yaml -e "snap_action=delete snap_name=pre-mongo" --ask-vault-pass
```

If `snap_name` is omitted on create, the snapshot is named `snapshot-YYYYMMDD-HHMM` automatically.

### `db.yaml`

Configures the MongoDB server on `db_servers` hosts.

```bash
ansible-playbook playbooks/db.yaml --ask-vault-pass
```
