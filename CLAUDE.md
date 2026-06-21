# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

T-NSA-810-CIA: GitOps-driven hybrid infrastructure across two Proxmox sites (site1 on-prem, site2 remote) with site-to-site VPN, pfSense firewalls, a bastion/jump server, NetBox IPAM, and centralized Elasticsearch logging. The repo is infra-as-code only — no application code.

## Architecture

Two-site topology, with all VM access to site1 services brokered through the site2 bastion (`s2_js`):

- **site1** (`ns3183326.ip-146-59-253.eu`, node `vm002`): `s1_fw` (firewall, vmid 105), `s1_db` (MongoDB, 2037, 10.0.20.1), `s1_app` (app server, 3037, 10.0.10.1)
- **site2** (`ns3050272.ip-51-255-76.eu`, node `vm3`): `s2_fw` (firewall, vmid 124), `s2_js` (bastion/jump, 2037, 192.168.10.10), `s2_mt` (monitoring/log sink, 3037, 192.168.20.1)

SSH into site1 VMs always uses `ProxyJump=bastion` (see `ansible/inventory/hosts.yaml`); never connect directly. The bastion (`s2_js`) also rsyncs its logs to `s2_mt` on a 1-min cron — see `ansible/roles/bastion/templates/sync-logs.sh.j2`.

Bastion user accounts are derived from the `admin_users` list in `ansible/playbooks/bastion.yaml`; each user's SSH public key is fetched at runtime from Vault under `secret/infra/ssh/admins/<name>`. Add a user there (and store their key in Vault), not by editing the role.

Top-level layout (most dirs are still placeholders with `.gitkeep`):
- `ansible/` — playbooks, roles, inventory. **This is the active area.**
- `terraform/` — Proxmox provisioning (modules + per-site environments). Placeholder.
- `networking/`, `services/`, `configs/`, `scripts/` — placeholders for VPN/firewall/DNS/Elasticsearch/NetBox configs.
- `docs/` — `access-isolation-validation.md` documents the access matrix; subdirs are placeholders.

## Commands

All Ansible commands run from `ansible/`.

```bash
# Snapshot management (via Makefile, wraps proxmox_snapshot.yaml)
make snap.<create|restore|delete>.<site1|site2>.<fw|db|app|js|mt> SNAP=<name>
make help

# Playbooks (no --ask-vault-pass anymore — secrets are pulled from HashiCorp Vault)
ansible-playbook playbooks/bastion.yaml
ansible-playbook playbooks/managed_vms.yaml
ansible-playbook playbooks/netbox.yaml
ansible-playbook playbooks/vault.yaml          # deploys Vault itself
```

`ansible.cfg` pins `-i ~/.ssh/id_ed25519` and `IdentitiesOnly=yes`; `forks=1` (operations run serially by design — don't bump it without reason).

## Conventions

- **Secret management**: HashiCorp Vault hosted on `s2_mt` (`https://192.168.20.1:8200`). No more `ansible-vault`. Playbooks authenticate via AppRole: `role_id` is in `ansible/group_vars/all/vars.yaml`, `secret_id` must exist locally at `~/.ansible/vault-secret-id` (gitignored, distributed out of band). The Vault CA cert lives at `~/.ansible/vault-ca.crt`. Policies are versioned in `policies/*.hcl`. Full doc: `docs/secret-management/`. Wiki-ready summary: `docs/secret-management/wiki-page-Vault-Implementation.md`.
- **Adding a Vault-backed secret to a playbook**: `import_tasks: tasks/vault_login.yml` then `lookup('community.hashi_vault.vault_kv2_get', '<path>', url=vault_addr, ca_cert=vault_ca_cert, token=vault_token).data.data.<key>`.
- **Commit style**: conventional commits scoped by component, e.g. `feat(bastion): ...`, `fix(bastion): ...`, `docs(bastion): ...`. Many commits reference a ticket number (`- ticket #67`).
- **Branches**: `<issue-number>-<short-slug>` (e.g. `67-validate-bastion-documents`).
- **Proxmox API auth**: token-based (`GR37@pve!ansible`), not password. Tokens must be created in the Proxmox UI per site with privilege separation off.
