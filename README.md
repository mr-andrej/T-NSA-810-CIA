# T-NSA-810-CIA: Hybrid Infrastructure with Proxmox

> **Deployment and Securing of a Hybrid Infrastructure with Proxmox**
> A GitOps-driven project for building secure, scalable multi-site infrastructure.

[![Project Status](https://img.shields.io/badge/status-in%20development-yellow)](https://github.com/mr-andrej/T-NSA-810-CIA)

## Table of Contents

- [Overview](#overview)
- [Architecture at a glance](#architecture-at-a-glance)
- [Repository Structure](#repository-structure)
- [Technology Stack](#technology-stack)
- [Getting Started](#getting-started)
- [Documentation](#documentation)
- [Team](#team)
- [Contributing Guidelines](#contributing-guidelines)
- [Grading Criteria & Verification Map](#grading-criteria--verification-map)

## Overview

This project implements a **hybrid infrastructure** spanning two Proxmox sites (Site 1 on-premises, Site 2 remote) connected by a site-to-site VPN, fronted by a bastion for all admin access, with NetBox as IP source of truth, HashiCorp Vault for secrets, and JUNKyard for centralized logging. Built with GitOps principles — every change goes through the repo.

### Key Objectives

- Dual-site Proxmox infrastructure (Site 1 + Site 2)
- Secure site-to-site VPN connectivity (OpenVPN hub-and-spoke)
- Per-site stateful firewalls with documented emergency cut-off
- Bastion host as single admin SSH entry point
- Automated IPAM via NetBox (declarative + real-time sync)
- Centralized logs via JUNKyard (custom Go logger, low footprint)
- Secret management via HashiCorp Vault with Shamir 3-of-5
- Reproducible disaster recovery via documented runbook

## Architecture at a glance

```
                  Internet
                     │
        ┌────────────┼────────────┐
        │            │            │
   ┌────▼───┐   Admin VPN    ┌────▼───┐
   │ S1-FW  │   (UDP 1194)   │ S2-FW  │
   │ pfSense│                │ pfSense│
   └────┬───┘   S2S VPN ─────►│ (hub)  │
        │       (UDP 1195)   └────┬───┘
        │                         │
  ┌─────┼─────┐             ┌─────┼─────┐
  │     │     │             │     │     │
 VLAN10 │   VLAN20         VLAN10 │   VLAN20
 App    │   DB             DMZ    │   Monitoring
 s1_app │   s1_db         s2_js   │   s2_mt
                          (bastion) (Vault/NetBox/JUNKyard)
```

- **Site 1** (`ns3183326`, on-prem) — `s1_fw` / `s1_app` / `s1_db` — never exposed on WAN
- **Site 2** (`ns3050272`, remote) — `s2_fw` / `s2_js` (bastion) / `s2_mt` (Vault + NetBox + JUNKyard) — VPN hub
- All admin access: laptop → Admin VPN → bastion (`s2_js`) → target VM via ProxyJump

## Repository Structure

Mono-repo with the active area being `ansible/`. Other top-level directories are placeholders for future expansion (Terraform, etc.).

```
T-NSA-810-CIA/
├── ansible/                  # 🔥 active — config management
│   ├── ansible.cfg           # forks=1, pinned SSH key, ProxyJump bastion
│   ├── Makefile              # snapshot shortcuts (make snap.create.site1.app)
│   ├── requirements.yml      # collections (community.hashi_vault, netbox.netbox, ...)
│   ├── inventory/
│   │   ├── hosts.yaml        # static inventory
│   │   ├── netbox_inventory.yaml  # dynamic inventory from NetBox
│   │   ├── group_vars/
│   │   └── host_vars/
│   ├── playbooks/            # bastion, managed_vms, vault, netbox.*, proxmox_snapshot, ...
│   └── roles/                # bastion, common, managed_vm, vault, netbox, vpn, firewall, ...
│
├── policies/                 # Vault HCL policies (ansible-deploy, admin, ...)
│
├── docs/                     # project documentation
│   ├── architecture/
│   ├── runbooks/
│   ├── disaster-recovery/
│   ├── secret-management/    # Vault deployment & DR guides
│   ├── access-isolation-validation.md
│   └── keynote-*.md          # oral exam prep
│
├── terraform/                # placeholder (provisioning not yet IaC)
├── networking/, services/,
├── configs/, scripts/        # placeholders
├── tests/                    # validation scripts
│
├── .github/                  # workflows + issue templates
├── CLAUDE.md                 # AI assistant project context
└── README.md
```

See the [Repository Strategy](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy) wiki page for the mono-repo rationale.

## Technology Stack

### Core Infrastructure
- **Proxmox VE 8.x** — virtualization platform, 3 VMs per site
- **pfSense** (FreeBSD) — perimeter firewall + DNS resolver + OpenVPN server/client per site
- **OpenVPN** — site-to-site (UDP 1195, hub at Site 2) + Admin VPN (UDP 1194)

### Automation & Management
- **Ansible** — configuration management (the active IaC layer). Agentless, SSH via ProxyJump bastion. `forks=1` for predictable serial execution.
- **Terraform** — placeholder for future VM provisioning
- **NetBox** — IPAM source of truth on `s2_mt` (deployed and sync'd via Ansible)
- **HashiCorp Vault** — secrets backend on `s2_mt`, AppRole for Ansible, Shamir 3-of-5 unseal

### Observability
- **JUNKyard** — custom Go + SQLite log aggregator, ~95 MB RAM. UI on `:8080`. Receives rsyslog (TCP 5514) from Linux VMs + syslog (UDP 5514) from pfSense + rsync from bastion.

### GitOps & CI/CD
- **GitHub Actions** — Ansible syntax checks
- **Conventional commits**, branches `<issue>-<slug>`, mono-repo

## Getting Started

### Prerequisites

- Proxmox VE 8.x on bare metal (both sites)
- SSH key (`~/.ssh/id_ed25519`) registered on bastion via the `admin_users` playbook flow
- Active Admin VPN profile (issued out of band)
- Vault `secret_id` at `~/.ansible/vault-secret-id` (distributed out of band)
- Vault CA cert at `~/.ansible/vault-ca.crt`

### Common commands

All from `ansible/`:

```bash
# Configure bastion (users, SSH hardening, sync-logs cron)
ansible-playbook playbooks/bastion.yaml

# Configure managed VMs (s1_app, s1_db, s2_mt)
ansible-playbook playbooks/managed_vms.yaml

# Deploy / upgrade Vault
ansible-playbook playbooks/vault.yaml

# NetBox lifecycle
ansible-playbook playbooks/netbox.yaml          # deploy
ansible-playbook playbooks/netbox_populate.yaml # initial data
ansible-playbook playbooks/netbox_sync.yaml     # real infra → NetBox

# Snapshot a VM (wraps proxmox_snapshot.yaml)
make snap.create.site1.app SNAP=before-upgrade
make snap.restore.site1.app SNAP=before-upgrade
make help
```

## Documentation

Most of the operational documentation lives in the **wiki**. Local `docs/` holds prep material and validation artifacts.

- **[Wiki — Home](https://github.com/mr-andrej/T-NSA-810-CIA/wiki)** — full index
- **[Architecture Overview](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview)**
- **[Rebuild Runbook](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide)** — full DR procedure
- **[Vault Implementation](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation)**
- **Local docs**:
  - `docs/secret-management/` — Vault onboarding & DR
  - `docs/keynote-fiches-revision.md` / `docs/keynote-revision-cards.md` — oral exam prep (FR / EN)
  - `docs/access-isolation-validation.md` — access matrix

## Team

**PAR_14**

- [@LuckyShuii](https://github.com/LuckyShuii) — Lucas Boillot
- [@PaulDecauchy](https://github.com/PaulDecauchy) — Paul Decauchy
- [@mr-andrej](https://github.com/mr-andrej) — Andrej

## Contributing Guidelines

GitOps best practices apply to every infrastructure change:

1. Branch from `main` as `<issue>-<short-slug>` (e.g. `67-validate-bastion`)
2. Conventional commits scoped by component: `feat(bastion):`, `fix(vpn):`, `docs(netbox):`
3. PR review by at least one team member
4. Document in the relevant wiki page (and update local `docs/` when needed)
5. Secrets never committed — always pulled from Vault at runtime via AppRole

---

## Grading Criteria & Verification Map

Direct links from each grading criterion to the wiki page (and anchor) that documents the corresponding procedure or evidence.

**Wiki base URL:** `https://github.com/mr-andrej/T-NSA-810-CIA/wiki/`

### 🏗️ Infrastructure

| Criterion | Documentation |
|---|---|
| `infra_delivery` — hybrid infra delivered & functional | [Architecture Overview](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview) · [Rebuild Runbook — Phase 11 Full Validation](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide#phase-11--full-validation) |
| `infra_spec` — required services present | [Architecture Overview → Network Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#network-architecture) · [→ Security Principles Enforced](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#security-principles-enforced) |
| `infra_scalability` — easy to integrate new sites | [Scalability Defense → How to integrate a new site](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Scalability-Defense#how-to-integrate-a-new-site-concrete-procedure) · [→ Defense Q&A](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Scalability-Defense#defense-qa--anticipated-jury-questions) |
| `infra_choices` — stack supported & updated | [IaC Tools → Technology Choice](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-as-code-tools#iac-technology-choice) · [Firewalls → Technology Choice](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Firewalls#firewall-technology-choice) · [VPN → Technology Choice](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Virtual-Private-Network-(VPN)#vpn-technology-choice) · [NetBox → Selected Solution](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Netbox-‐-IPAM-Solution#selected-solution-netbox) |

### 🗺️ Diagram

| Criterion | Documentation |
|---|---|
| `diagram_delivery` — diagram at first review | [Architecture Overview → Network Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#network-architecture) |
| `diagram_quality` — includes 2 sites + control points + VPN + bastion + DNS + IPAM + observability | [→ Site 1 Internal](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#site-1--internal-on-premises) · [→ Site 2 Remote](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#site-2--remote--cloud) · [→ S2S VPN Tunnel](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#site-to-site-vpn-tunnel) · [→ Admin Access Flow](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#administrative-access-flow) · [→ Log Aggregation Flow](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#log-aggregation-flow-all-vms--junkyard) · [→ DNS Forwarding](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#dns-forwarding) |

### ⚙️ IaC

| Criterion | Documentation |
|---|---|
| `iac_delivery` — most resources deployed via IaC | [IaC Tools → Configuration: Ansible](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-as-code-tools#configuration-ansible) · [→ Provisioning: Terraform](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-as-code-tools#provisioning-terraform) |
| `iac_quality` — readable, best practices | [Repository Strategy → Repository Structure](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#repository-structure) · [→ Design Principles](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#design-principles) · [IaC Tools → Note on JUNKyard and Ansible](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-as-code-tools#a-note-on-junkyard-and-ansible) |

### 🌐 Network

| Criterion | Documentation |
|---|---|
| `network_spec1` — on-prem site internal-only | [Site 1 FW → WAN Rules](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site1-‐-Firewall-Configuration#wan-rules) · [Site 1 Network Config](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site-1-‐-Network-Configuration) · [Architecture → Security Properties](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#security-properties) |
| `network_spec2` — remote site externally accessible | [Site 2 FW → WAN Rules](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site2-‐-Firewall-Configuration#wan-rules) · [Site 2 FW → OpenVPN Server Config](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site2-‐-Firewall-Configuration#8-openvpn-server-configuration) |
| `network_vpn` — sites connected via secure VPN | [VPN → S2S Topology](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Virtual-Private-Network-(VPN)#site-to-site-topology-site-1--site-2) · [VPN → Security Aspects](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Virtual-Private-Network-(VPN)#security-aspects) · [Inter-Site Routing → Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Inter‐Site-Routing-via-OpenVPN-(Site-1-↔-Site-2)#architecture) · [→ VPN Encryption Verification](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Inter‐Site-Routing-via-OpenVPN-(Site-1-↔-Site-2)#vpn-encryption-verification) |
| `network_firewall` — FW per site, traffic separation | [Firewalls → Architecture Overview](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Firewalls#firewall-architecture-overview) · [Site 1 FW → Firewall Rules](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site1-‐-Firewall-Configuration#5-firewall-rules) · [Site 2 FW → Firewall Rules](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Site2-‐-Firewall-Configuration#7-firewall-rules) · [Inter-Site → Allowed/Blocked Flow Tests](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Inter‐Site-Routing-via-OpenVPN-(Site-1-↔-Site-2)#test-scenarios) |
| `network_dns` — DNS forwarding between sites | [DNS Forwarding → Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Inter‐Site-DNS-Forwarding#architecture) · [→ Validation](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Inter‐Site-DNS-Forwarding#validation) |
| `network_ip_mngmt` — IPAM auto-updated | [NetBox IPAM → Sync real infra → NetBox](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/NetBox-IPAM:-Deployment,-Population-&-Sync#4-sync-real-infrastructure--netbox) · [→ Dynamic Ansible inventory](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/NetBox-IPAM:-Deployment,-Population-&-Sync#5-netbox-as-a-dynamic-ansible-inventory) · [→ Sync captures real changes](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/NetBox-IPAM:-Deployment,-Population-&-Sync#validating-the-sync-captures-real-changes) |

### 🔐 Security

| Criterion | Documentation |
|---|---|
| `sec_access` — least privilege | [User Management → Access Matrix](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/User-Management-‐-Bastion-&-Managed-VMs#access-matrix) · [→ Sudo Access](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/User-Management-‐-Bastion-&-Managed-VMs#sudo-access) · [Architecture → Security Principles](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#security-principles-enforced) · [Vault → Auth methods & policies](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#auth-methods--policies) |
| `sec_bastion` — access via bastion | [Bastion → Role and Purpose](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Bastion-‐-Jump-Server#bastion-role-and-purpose) · [→ SSH Hardening](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Bastion-‐-Jump-Server#ssh-hardening) · [→ How to Connect](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Bastion-‐-Jump-Server#how-to-connect-to-the-bastion) · [User Management → Connection Flow](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/User-Management-‐-Bastion-&-Managed-VMs#connection-flow) |
| `sec_credentials` — secret management secured | [Vault → Architectural choices](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#architectural-choices-and-why) · [→ Secret inventory](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#secret-inventory-kv-v2-paths) · [→ Operational procedures](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#operational-procedures) · [→ Unseal after s2_mt reboot](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#unseal-after-an-s2_mt-reboot) · [→ Secret rotation](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Implementation#secret-rotation) · [Vault Secrets Management → Authentication and Authorization](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Vault-‐-Secrets-Management#authentication-and-authorization) |

### 🚨 Incident & Recovery

| Criterion | Documentation |
|---|---|
| `incident_killswitch` — emergency shutdown that doesn't prevent recovery | [Emergency VPN Cut-Off → Cut-Off Options](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Emergency-VPN-Cut‐Off-&-Recovery-Procedure#emergency-cut-off) · [→ Recovery](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Emergency-VPN-Cut‐Off-&-Recovery-Procedure#recovery) · [→ Out-of-Band Recovery (noVNC)](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Emergency-VPN-Cut‐Off-&-Recovery-Procedure#out-of-band-recovery) · [Resilience → Kill Switch Mechanisms](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Resilience-&-Availability#kill-switch-mechanisms) · [→ Reversibility and Recovery](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Resilience-&-Availability#reversibility-and-recovery) |
| `incident_recovery` — usable & reproducible DR | [Rebuild Runbook → Phase 0 Prerequisites](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide#phase-0--prerequisites--planning) · [→ Phase 0.1 DR Decision Tree](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide#phase-01--dr-decision-tree) · [→ Dependency Map / Build Order](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide#dependency-map--build-order) · [→ Phase 6 Vault Redeploy](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Rebuild-Runbook-‐-Full-Infrastructure-Reconstruction-Guide#phase-6--vault-redeploy-single-source-of-truth-for-secrets) · [Resilience → Reproducibility](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Resilience-&-Availability#6-configuration-and-infrastructure-reproducibility) |

### 📊 Observability

| Criterion | Documentation |
|---|---|
| `log_centralisation` — logs from all components centralised | [JUNKyard → Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#architecture) · [→ Log Sources and Transport](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#log-sources-and-transport) · [→ Per-VM Configuration](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#per-vm-configuration) · [Architecture → Log Aggregation Flow](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Architecture-Overview#log-aggregation-flow-all-vms--junkyard) |
| `log_observability` — real-time monitoring | [JUNKyard → Architecture](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#architecture) · [→ Verify](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#verify) · [Resilience → Detection and Monitoring](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Infrastructure-Resilience-&-Availability#4-detection-and-monitoring-of-failures) |
| `log_analysis` — telemetry analysis relevant | [JUNKyard → Access](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#access) · [→ JUNKyard Modifications](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#junkyard-modifications) |
| `log_visuals` — visual representations | [JUNKyard → Access (Web UI :8080)](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/JUNKyard#access) |

### 📁 Repository

| Criterion | Documentation |
|---|---|
| `repo_practices` — versioning + branching + commits + gitignore | [Repository Strategy → Repository Structure](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#repository-structure) · [→ GitOps Alignment](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#gitops-alignment) · [→ Justification for Mono-Repo](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#justification-for-mono-repo) |
| `repo_doc` — clear, structured documentation | [Wiki Home](https://github.com/mr-andrej/T-NSA-810-CIA/wiki) · [Context](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Context) · [Repository Strategy → Executive Summary](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#executive-summary) |
| `repo_content` — source code + component configs | [Repository Strategy → Repository Structure](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#repository-structure) · [→ Note on JUNKyard](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy#note-on-junkyard) |

### 📅 Project Management

These three criteria are **not in the wiki** — they live in GitHub Projects and the keynote itself.

| Criterion | Where to find it |
|---|---|
| `proj_subdivision` — GANTT or equivalent | [GitHub Project Board](https://github.com/users/mr-andrej/projects/2) |
| `proj_planning` — backlog + task distribution | [GitHub Issues](https://github.com/mr-andrej/T-NSA-810-CIA/issues) + [Project Board](https://github.com/users/mr-andrej/projects/2) |
| `proj_presentation` — professional presentation | Keynote slides + `docs/keynote-fiches-revision.md` / `docs/keynote-revision-cards.md` |

---

## Links

- **Repository**: https://github.com/mr-andrej/T-NSA-810-CIA
- **Wiki**: https://github.com/mr-andrej/T-NSA-810-CIA/wiki
- **Issues**: https://github.com/mr-andrej/T-NSA-810-CIA/issues
- **Project Board**: https://github.com/users/mr-andrej/projects/2

---

**Project Status**: In Development
