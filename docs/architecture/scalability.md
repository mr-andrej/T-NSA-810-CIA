# Infrastructure Scalability

> **Wiki page — defense brief.** Argues and substantiates the claim
> *"The infrastructure is scalable: it is easy and quick to integrate other sites."*
> Update on every structural change.

## TL;DR

The infrastructure is **designed to scale by site replication**. Every
component that a new site touches — secrets, IPAM, host configuration,
firewall rules, logging — is already centralised and declaratively
parameterised. Adding a 3rd site (or 4th, 5th…) does **not** require
inventing new tooling: it requires extending YAML inventory, copying
host_vars, and running the existing playbooks against the new hosts.

What is **not yet automated** is a single one-shot "site bootstrap"
playbook. That gap is operational, not architectural — every step exists,
they are just not yet chained. See [Limitations](#known-limitations)
and [Roadmap](#roadmap).

## What "scalable" means in this project

To avoid arguing on different definitions in front of the jury, this is
the concrete scope of the claim:

| Dimension | In scope | Out of scope |
| --- | --- | --- |
| **Adding a new site** (3rd, 4th, …) | ✅ | — |
| **Adding a new VM inside an existing site** | ✅ | — |
| **Adding a new operator/admin** | ✅ | — |
| **Adding a new consuming service** (Vault-backed) | ✅ | — |
| **High-availability of central services** (Vault, bastion) | ⚠️ partial | full active/active HA — design choice, see DR doc |
| **VM provisioning IaC (Terraform)** | ❌ | Removed from scope; VMs provisioned via Proxmox UI |

The defense is built on the "in scope" rows.

## Architectural pillars enabling scale

### 1. GitOps inventory as the single entry point

`ansible/inventory/hosts.yaml` is the canonical declaration of what
exists. Adding a site is a YAML diff:

```yaml
site3:
  hosts:
    s3_fw: { ansible_host: <wan_ip> }
    s3_app: { ansible_host: 10.0.30.1, ansible_ssh_common_args: '-o ProxyJump=bastion' }
    s3_db:  { ansible_host: 10.0.30.2, ansible_ssh_common_args: '-o ProxyJump=bastion' }
```

No code changes downstream — playbooks already iterate over inventory
groups.

### 2. Reusable, parameterised roles

The 5 populated roles (`bastion`, `firewall`, `managed_vm`, `netbox`,
`vault`) are **site-agnostic**. They read from `group_vars/`,
`host_vars/`, and Vault — never hardcoded references to `site1` or
`site2`. A new site reuses them as-is.

| Role | Reused per site? | What you provide |
| --- | --- | --- |
| `bastion` | Once (central) | New admin keys via Vault path |
| `firewall` | Per site | New `host_vars/s3_fw.yaml` (copy from s1_fw template) |
| `managed_vm` | Per VM | Inventory entry only |
| `netbox` | Once (central) | Register the new site/prefix via API |
| `vault` | Once (central) | New AppRole + policy for the site |

### 3. Vault as a central trust anchor

A new site does not need to re-distribute secrets. The procedure is:

1. Admin creates an AppRole for the new site (`vault write auth/approle/role/site3 …`).
2. The site's operator receives `role_id` + `secret_id` out of band.
3. Playbooks pull whatever they need at runtime.

No secret ever transits the repo, no new vault to manage, no key
ceremony per site.

### 4. NetBox as a central IPAM source of truth

Site addressing is declared in NetBox, not scattered in Ansible vars. The
`netbox_inventory.yaml` dynamic inventory already auto-discovers hosts —
registering a new site in NetBox makes its hosts visible to Ansible
without further config.

### 5. pfSense per site, declarative ruleset

`ansible/inventory/host_vars/s1_fw.yaml` is the **template pattern**:
every interface, VLAN, DHCP scope, DNS resolver, OpenVPN tunnel and
firewall rule is data, not procedure. Copying it to `s3_fw.yaml`,
re-numbering IPs, and running `playbooks/s1_fw.yaml` (renamed to target
the new host) gives a configured firewall.

### 6. Centralised logging with a replicable pattern

The bastion `sync-logs.sh.j2` rsync pattern works for any host that can
reach `s2_mt:/home/administrator/junkyard/`. Adding a new site = adding
a cron + SSH path; no log-pipeline redesign.

## How to integrate a new site (concrete procedure)

This is the procedure a jury can ask you to walk through. Each step is
≤ a few minutes; the long pole is the network plumbing (VPN + firewall
rules), not the code.

### Phase A — Network prerequisites (manual, one-off per site)

1. Allocate a new RFC1918 range (e.g. `10.0.30.0/24` for site3 internal,
   `192.168.30.0/24` for management).
2. Order/provision a Proxmox node.
3. Open site-to-site VPN: pfSense supports hub-and-spoke natively. The
   hub stays at site2 (existing `s2_fw`); the new site is a spoke.
4. Register the prefixes in NetBox (sites, prefixes, VLANs).

### Phase B — Provision the 3 VMs (Proxmox UI)

Following the 3-VM-per-site model: `s3_fw`, `s3_app`, `s3_db`. Create a
Proxmox API token (privilege separation off) for Ansible, store it:

```bash
vault kv put secret/infra/proxmox/site3 \
    api_user=GR37@pve \
    api_token_id=ansible \
    api_token_secret=<token>
```

### Phase C — Wire the new site into Ansible

1. Add the `site3` group to `ansible/inventory/hosts.yaml` (see [pillar 1](#1-gitops-inventory-as-the-single-entry-point)).
2. Copy `host_vars/s1_fw.yaml` → `host_vars/s3_fw.yaml`, adjust IPs/VLANs.
3. Add SSH `ProxyJump=bastion` to every new managed host (one line per host).

### Phase D — Apply

```bash
ansible-playbook playbooks/s1_fw.yaml --limit s3_fw       # configure pfSense
ansible-playbook playbooks/managed_vms.yaml --limit site3 # configure VMs
ansible-playbook playbooks/netbox_sync.yaml               # refresh IPAM
```

### Phase E — Verify

```bash
ssh -J bastion s3_app -- uptime           # bastion proxy works
vault read -format=json sys/health        # central services reachable
ansible site3 -m ping                     # full reachability
```

### Total effort

| Task | Time |
| --- | --- |
| Network plumbing (VPN, IP plan, NetBox entries) | ~1 h |
| Proxmox VM creation (3 VMs) | ~30 min |
| Inventory + host_vars copy | ~15 min |
| Playbook runs | ~20 min |
| Verification | ~10 min |
| **Total** | **~2 h 15** |

For comparison, an unprepared infra (no Vault, no NetBox, no reusable
roles) would take days because every secret distribution, IP allocation
and base config is bespoke.

## Known limitations

We do not pretend the design is perfect — these are the trade-offs and
how they are managed.

| Limitation | Impact | Mitigation / why acceptable |
| --- | --- | --- |
| **Single bastion** (`s2_js` in site2) | All inter-site admin SSH transits it. SPOF for ops. | Bastion failure does not bring down sites, only admin access. Snapshot + reprovision in ~10 min. HA bastion = future work. |
| **Single Vault instance** | Vault outage blocks new playbook runs. | Vault is sealed only after a reboot, snapshots are daily (03:30), 14-day retention. Acceptable for the project SLA. Raft HA possible without architecture change. |
| **VPN is point-to-point today** | Adding a 3rd site requires a brief reconfiguration (hub-and-spoke). | pfSense supports it natively; no Ansible code change required — only `host_vars` data. |
| **No one-shot "site bootstrap" playbook** | Operator runs ~3 playbooks instead of 1. | Each playbook is idempotent and documented. Chaining is a quality-of-life improvement, not an architectural blocker. |
| **Proxmox API token created via UI per site** | One manual step. | Documented in CLAUDE.md. Proxmox provides no IaC alternative without a 3rd-party module that adds dependency weight. |
| **No formalised IP plan document** | Risk of overlap. | NetBox prevents overlap at registration time. A `docs/networking/ip-plan.md` is on the roadmap. |

None of these are **architectural** dead-ends — they are all single-step
improvements on top of the current design.

## Roadmap

Improvements that would harden the scalability story (none are blocking):

1. **`site_bootstrap.yaml` meta-playbook** chaining the Phase D steps.
2. **`docs/networking/ip-plan.md`** with the canonical numbering scheme
   (10.0.X.0/24 internal, 192.168.X.0/24 mgmt, X = site index).
3. **Hub-and-spoke VPN templates** in `roles/firewall/tasks/openvpn.yml`
   parameterised by `site_role: hub|spoke`.
4. **HA Vault** (Raft, 3 nodes) once a 2nd central site exists.
5. **Per-site bastion** if more than ~5 sites — keeps blast radius bounded.

## Defense Q&A — anticipated jury questions

> *"What happens if you need to add a 3rd site tomorrow morning?"*

≈ 2 h of work, ~80 % of which is network plumbing and NetBox data entry.
The Ansible side is a YAML diff plus three playbook runs. See
[procedure](#how-to-integrate-a-new-site-concrete-procedure).

> *"Is the bastion not a bottleneck if you scale to many sites?"*

For up to ~5 sites it is acceptable; it is an ops SPOF, not a runtime
one. Beyond that the design naturally extends to per-site bastions
without changing the role itself.

> *"What if Vault is down?"*

Existing services keep running (they hold their secrets). Only new
deployments are blocked. Recovery is unseal-from-snapshot (~10 min).

> *"You don't have Terraform. Isn't that a scalability red flag?"*

Out of scope by project decision. Proxmox VM creation is a one-time
manual step per VM (~5 min). The configuration of those VMs — which is
where 95 % of recurring work happens — is fully IaC via Ansible.

> *"Show me where in the repo a new site lives."*

`ansible/inventory/hosts.yaml` + `ansible/inventory/host_vars/<site>_fw.yaml`
+ optional `secret/infra/proxmox/<site>` in Vault. That is the surface
area. No other file changes needed.

## References

- Repo conventions: [`CLAUDE.md`](../../CLAUDE.md)
- Ansible inventory: [`ansible/inventory/hosts.yaml`](../../ansible/inventory/hosts.yaml)
- Reference firewall host_vars: [`ansible/inventory/host_vars/s1_fw.yaml`](../../ansible/inventory/host_vars/s1_fw.yaml)
- Vault implementation: [`docs/secret-management/wiki-page-Vault-Implementation.md`](../secret-management/wiki-page-Vault-Implementation.md)
- Access isolation matrix: [`docs/access-isolation-validation.md`](../access-isolation-validation.md)
- Disaster recovery (Vault): [`docs/secret-management/disaster-recovery.md`](../secret-management/disaster-recovery.md)
