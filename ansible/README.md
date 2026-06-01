# Ansible — T-NSA-810-CIA

Ansible playbooks for managing school infrastructure VMs across two Proxmox VE environments.

## Infrastructure

| Site | Proxmox host | VM | Role | vmid |
|------|-------------|-----|------|------|
| site1 | ns3183326.ip-146-59-253.eu (node: vm002) | s1_fw  | Firewall   | 105  |
| site1 |                                           | s1_db  | Database   | 2037 |
| site1 |                                           | s1_app | App server | 3037 |
| site2 | ns3050272.ip-51-255-76.eu (node: vm3)     | s2_fw  | Firewall   | 124  |
| site2 |                                           | s2_js  | Jump server| 2037 |
| site2 |                                           | s2_mt  | Monitoring | 3037 |

## Requirements

```bash
sudo apt install ansible python3-proxmoxer python3-requests
ansible-galaxy collection install community.proxmox
```

## Inventory

Hosts are defined in `inventory/hosts.yaml`. Fill in the SSH details for each VM before running playbooks that connect directly to VMs (e.g. `db.yaml`). The snapshot playbook does not need these.

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
| `vault_proxmox_api_password_site1` | API token secret for `GR37@pve!ansible` on site1 |
| `vault_proxmox_api_password_site2` | API token secret for `GR37@pve!ansible` on site2 |

## SSH key setup

All VMs use the `cia` user with SSH key authentication (no password).

Generate the project key once on your laptop:

```bash
ssh-keygen -t ed25519 -C "cia-ansible" -f ~/.ssh/cia_ansible
```

Then copy the public key into `group_vars/all/vars.yaml`:

```bash
cat ~/.ssh/cia_ansible.pub
```

Paste the output as the value of `cloudinit_ssh_pubkey` in `group_vars/all/vars.yaml`.

The private key (`~/.ssh/cia_ansible`) stays on your laptop and is never committed.

To use this key with SSH and Ansible, add to `~/.ssh/config`:

```
Host 10.0.*.*
    User cia
    IdentityFile ~/.ssh/cia_ansible
```

## Proxmox API token

The playbooks authenticate to the Proxmox API using a token (not a password).

To create the token on each site:

1. Log into the Proxmox UI
2. **Datacenter → Permissions → API Tokens → Add**
   - User: `GR37@pve`
   - Token ID: `ansible`
   - Privilege Separation: unchecked
3. Copy the token secret and store it in the vault

## Snapshots

Snapshots are managed via the Makefile. Proxmox handles stopping and restarting the VM on restore — no need to do it manually.

```bash
make snap.<action>.<site>.<vm> SNAP=<name>
```

| Action | Description |
|--------|-------------|
| `create` | Create a new snapshot |
| `restore` | Roll back to a snapshot |
| `delete` | Delete a snapshot |

```bash
# Examples
make snap.create.site1.db  SNAP=pre-mongo
make snap.restore.site1.db SNAP=pre-mongo
make snap.delete.site2.mt  SNAP=old-snap

# See all targets
make help
```

If `SNAP` is omitted on create, the snapshot is named `snapshot-YYYYMMDD-HHMM` automatically.

## VM initial setup (two-phase)

For each new VM, run these in order:

**Phase 1 — cloud-init via Proxmox API** (injects SSH key + creates `cia` user):
```bash
make cloudinit.site1.db
```

**Phase 2 — network config via SSH** (applies VLAN/IP via Netplan):
1. Find the VM's current DHCP IP in the Proxmox console: `ip addr`
2. Fill it in as `ansible_host` for the host in `inventory/hosts.yaml`
3. Run:
```bash
make network.site1.db
```

SSH will drop when `netplan apply` runs — that's expected. After that, update `ansible_host` in the inventory to the static IP (`10.0.20.1` for s1_db).

## Playbooks

### `db.yaml`

Configures the MongoDB server on `db_servers` hosts.

```bash
ansible-playbook playbooks/db.yaml --ask-vault-pass
```
