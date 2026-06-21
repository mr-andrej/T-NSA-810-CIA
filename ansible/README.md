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
ansible-galaxy collection install -r requirements.yml
```

## Inventory

Hosts are defined in `inventory/hosts.yaml`. Fill in the SSH details for each VM before running playbooks that connect directly to VMs (e.g. `db.yaml`). The snapshot playbook does not need these.

## Vault setup

Secrets are stored encrypted in `inventory/group_vars/all/vault.yaml`.

To set up for the first time:

```bash
cp inventory/group_vars/all/vault.yaml.example inventory/group_vars/all/vault.yaml
nano inventory/group_vars/all/vault.yaml  # fill in real values
ansible-vault encrypt inventory/group_vars/all/vault.yaml
```

`vault.yaml` is in `.gitignore` and must never be committed. Only `vault.yaml.example` is tracked by git.

To edit later:

```bash
ansible-vault edit inventory/group_vars/all/vault.yaml
```

### Vault variables

| Variable | Description |
|---|---|
| `vault_proxmox_api_password_site1` | API token secret for `GR37@pve!ansible` on site1 |
| `vault_proxmox_api_password_site2` | API token secret for `GR37@pve!ansible` on site2 |

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
make snap.create.site1.db  SNAP=pre-postgresql
make snap.restore.site1.db SNAP=pre-postgresql
make snap.delete.site2.mt  SNAP=old-snap

# See all targets
make help
```

If `SNAP` is omitted on create, the snapshot is named `snapshot-YYYYMMDD-HHMM` automatically.

## Playbooks

### `db.yaml`

Installs and configures PostgreSQL on the Site 1 database server (`site1_db`,
`10.0.20.1`): binds it to the DATABASE VLAN, opens `pg_hba.conf` to the SERVERS
VLAN (`10.0.10.0/24`, the app server) and the bastion (`192.168.10.0/24`),
creates the `appdb` database and `appuser` role, and creates a `healthcheck`
test table that it seeds and reads back to prove the DB works. It also enriches
PostgreSQL's local logging (`/var/log/postgresql/`) so the VM's log shipper can
forward records to monitoring. All settings live in
`roles/postgresql/defaults/main.yml`; the `appuser` password is fetched at
runtime from HashiCorp Vault (`secret/infra/postgresql/app`, key `password`) by
the playbook's `vault_login` pre-task — see `docs/secret-management/`.

```bash
ansible-galaxy collection install -r requirements.yml   # one-time

# Requires the Vault AppRole secret_id at ~/.ansible/vault-secret-id and the
# Vault CA at ~/.ansible/vault-ca.crt (see docs/secret-management/bootstrap.md).
# The inventory's ansible_user is `administrator`; override with -e if you log
# in as a personal account (e.g. over the bastion). Add --ask-become-pass only
# if your user does NOT have passwordless sudo.
ansible-playbook playbooks/db.yaml -e ansible_user=<you>
```

> **Note on `--check`:** a dry run is unreliable for the *first* deploy — the
> `postgresql_db`/`postgresql_table`/`postgresql_query` tasks error in check mode
> because they try to inspect a database/table that doesn't exist yet. Those
> errors are harmless; just run the playbook for real. `--check` is meaningful
> only once the database already exists.

**Connecting from a client.** The app server (`s1_app`, SERVERS VLAN) connects
directly to `10.0.20.1:5432` as `appuser`/`appdb`. For admin/dev access from a
GoLand database tool, connect the OpenVPN, then use GoLand's SSH/SSL tab to
tunnel through the `bastion` host; the connection target stays
`jdbc:postgresql://10.0.20.1:5432/appdb`.

### `app.yaml`

Deploys **visitapp**, a small Go visit-log web service, on the Site 1 app
server (`site1_app`, `10.0.10.1`). It is a single static binary run by systemd
as the unprivileged `visitapp` user (binding `:80` via
`CAP_NET_BIND_SERVICE`). Each request to `/` records the caller's IP and
User-Agent in a `visits` table in `appdb` and shows the caller's IP, the total
visit count and the most recent visits; `/healthz` pings the database and the
deploy asserts it returns `200`.

The app reuses the existing `appdb`/`appuser` and reads the **same** Vault
secret as `db.yaml` (`secret/infra/postgresql/app`) — no new database or
credential. The role installs `golang-go`, copies the sources from
`roles/webapp/files/` and builds the binary on the host (the module targets Go
1.22 to match Ubuntu 24.04's `golang-go`, so no toolchain download is needed;
`go mod download` does need the app server's HTTPS egress).

```bash
ansible-galaxy collection install -r requirements.yml   # one-time

# First time only: authorize this laptop's key on the app server (same two-key
# bastion model as s1_db), so Ansible's ProxyJump final hop is accepted.
cat ~/.ssh/id_ed25519_NSA.pub | ssh bastion 'ssh s1-app "cat >> ~/.ssh/authorized_keys"'

# Apply. Reads secret/infra/postgresql/app from Vault (needs the AppRole
# secret_id at ~/.ansible/vault-secret-id). Override ansible_user with -e if you
# log in as a personal account.
ansible-playbook playbooks/app.yaml -e ansible_user=<you>
```

**Access.** The app is reachable **only over the VPN**. `app.site1.internal`
resolves to `10.0.10.1` via the Site 1 firewall's DNS resolver, the SERVERS
VLAN is already permitted to the DB, and the inter-sites OpenVPN rule lets VPN
clients reach `10.0.10.1:80` while the WAN is blocked — so no firewall change
is needed. Visit `http://app.site1.internal/` (or `http://10.0.10.1/` if your
VPN client does not resolve `site1.internal`).

### `s1_fw.yaml`

Configures the Site 1 pfSense firewall (`site1_fw`) end to end — VLANs,
interfaces, least-privilege rules, DHCP, DNS Resolver and (opt-in) the OpenVPN
site-to-site client — using the `pfsensible.core` collection over SSH. All data
lives in `inventory/host_vars/s1_fw.yaml`; see `roles/firewall/README.md`.

```bash
ansible-galaxy collection install -r requirements.yml   # one-time
ansible-playbook playbooks/s1_fw.yaml --check           # dry run
ansible-playbook playbooks/s1_fw.yaml                   # apply
```

### `s2_fw.yaml`

Configures the Site 2 pfSense firewall (`site2_fw`) with the same `firewall`
role and data model — VLANs (DMZ/MONITORING), OPT1/OPT2 interfaces,
least-privilege rules, DHCP, and the DNS Resolver (host overrides +
`site1.internal` domain override). It codifies the hand-built configuration
(see the wiki "Site 2 Firewall" runbook) plus the rules added for the s1 stack
(Vault `:8200` and Admin-VPN→app `:80`). All data lives in
`inventory/host_vars/s2_fw.yaml`.

> **The two OpenVPN servers (Admin VPN 1194, site-to-site 1195) and their
> certificates are NOT managed** — the role only handles an OpenVPN *client*,
> and server/PKI provisioning isn't safely idempotent. They stay configured by
> hand per the runbook.

```bash
ansible-galaxy collection install -r requirements.yml   # one-time

# One-time SSH bootstrap on the box: enable SSH (System > Advanced > Admin
# Access), add your laptop pubkey (User Manager > admin), and add the mgmt rule
# 192.168.100.0/24 → This Firewall:22 by hand (it's in host_vars with a matching
# description so the playbook then adopts it). Connect over the Admin VPN.

ansible-playbook playbooks/s2_fw.yaml --check           # dry run — ALWAYS do this first
ansible-playbook playbooks/s2_fw.yaml                   # apply
```

> **Run `--check` first.** The role positions each rule relative to the previous
> rule *of the same name*, so if an existing hand-made rule's description doesn't
> match the data model character-for-character, applying would create a
> duplicate. The `--check` diff shows mismatches to reconcile first. Same for the
> interface `descr` (`DMZ` / `MONITORING`) vs. what OPT1/OPT2 are actually named live.
