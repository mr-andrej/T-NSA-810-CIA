# Access Isolation Validation — Bastion & Internal VMs

**Ticket:** #67 — Validate and Document Access Isolation  
**Date:** 2026-05-10  
**Tester:** Lucas Boillot  
**Infrastructure:** CIA Project — Hybrid Proxmox Infrastructure (Site 1 + Site 2)

---

## Objective

Validate that no internal VM is directly reachable from the WAN or from VPN clients via SSH, and that all SSH administrative access correctly routes through the bastion host (`S2-JS`, `192.168.10.10`).

---

## Test Environment

| Component | Details |
|-----------|---------|
| VPN Client IP | `192.168.100.2` (Admin VPN `192.168.100.0/24`) |
| Bastion Host | `S2-JS` — `192.168.10.10` |
| Admin VPN Server | `S2-FW` — `5.196.45.7:1194` |
| Test date | 2026-05-10 |
| VPN tool | OpenVPN Connect |

---

## Test Matrix

### Legend

| Symbol | Meaning |
|--------|---------|
| ❌ Blocked | Connection timed out or was refused — access correctly denied |
| ✅ Allowed | Connection succeeded — access correctly permitted |

---

### 1 — WAN Direct Access (VPN disconnected)

Test method: SSH attempt from local machine with VPN disconnected.

```bash
ssh administrator@<target_ip>
```

| Target VM | IP | Result | Expected | Notes |
|-----------|----|--------|----------|-------|
| S1-APP | `10.0.10.1` | ❌ Blocked (timeout) | ❌ Blocked | Private IP, not routable from WAN |
| S1-DB | `10.0.20.1` | ❌ Blocked (timeout) | ❌ Blocked | Private IP, not routable from WAN |
| S2-MT | `192.168.20.1` | ❌ Blocked (timeout) | ❌ Blocked | Private IP, not routable from WAN |
| S2-JS (Bastion) | `192.168.10.10` | ❌ Blocked (timeout) | ❌ Blocked | Private IP, not routable from WAN |

**Result: ✅ All passed**

---

### 2 — Direct SSH from VPN Client (VPN connected, no bastion)

Test method: SSH attempt from local machine with VPN connected, ProxyJump explicitly disabled.

```bash
ssh -o ProxyJump=none -o IdentitiesOnly=yes administrator@<target_ip>
```

| Target VM | IP | Result | Expected | Notes |
|-----------|----|--------|----------|-------|
| S1-APP | `10.0.10.1` | ❌ Blocked (timeout) | ❌ Blocked | Firewall rule blocks SSH from `192.168.100.0/24` to `10.0.10.0/24` on S1-FW OpenVPN interface |
| S1-DB | `10.0.20.1` | ❌ Blocked (timeout) | ❌ Blocked | Firewall rule blocks SSH from `192.168.100.0/24` to `10.0.20.0/24` on S1-FW OpenVPN interface |
| S2-MT | `192.168.20.1` | ❌ Blocked (timeout) | ❌ Blocked | Firewall rule blocks SSH from `192.168.100.0/24` to `192.168.20.0/24` on S2-FW OpenVPN interface |

**Result: ✅ All passed**

> **Note:** Direct SSH from VPN to the bastion (`192.168.10.10`) is intentionally **allowed** — it is the controlled entry point. All other internal VMs are blocked.

---

### 3 — SSH via Bastion (VPN connected)

Test method: SSH to bastion first, then SSH to internal VM using pre-configured shortnames.

```bash
ssh lucas@192.168.10.10   # connect to bastion
ssh s1-app                # from bastion to S1-APP
ssh s1-db                 # from bastion to S1-DB
ssh s2-mt                 # from bastion to S2-MT
```

| Target VM | IP | Result | Expected | Notes |
|-----------|----|--------|----------|-------|
| S1-APP | `10.0.10.1` | ✅ Allowed | ✅ Allowed | SSH from bastion (`192.168.10.10`) to Site 1 allowed via S2-FW OPT1 and S1-FW OpenVPN rules |
| S1-DB | `10.0.20.1` | ✅ Allowed | ✅ Allowed | SSH from bastion (`192.168.10.10`) to Site 1 allowed via S2-FW OPT1 and S1-FW OpenVPN rules |
| S2-MT | `192.168.20.1` | ✅ Allowed | ✅ Allowed | SSH from bastion (`192.168.10.10`) to Monitoring VLAN allowed via S2-FW OPT1 rules |

**Result: ✅ All passed**

---

## Summary

| Access Path | S1-APP | S1-DB | S2-MT | Bastion |
|-------------|--------|-------|-------|---------|
| WAN direct | ❌ | ❌ | ❌ | ❌ |
| VPN direct | ❌ | ❌ | ❌ | ✅ (intended) |
| Via bastion | ✅ | ✅ | ✅ | N/A |

**All acceptance criteria met:**
- ✅ No internal VM is reachable directly from WAN
- ✅ No internal VM is reachable directly from VPN client via SSH
- ✅ All internal VMs are reachable via the bastion
- ✅ Bastion is the single controlled SSH entry point

---

## Firewall Rules Enforcing Isolation

### S2-FW — OpenVPN interface

| Rule | Action | Source | Destination | Port | Purpose |
|------|--------|--------|-------------|------|---------|
| Block SSH VPN → Monitoring | Block | `192.168.100.0/24` | `192.168.20.0/24` | 22 | Prevents direct VPN access to S2-MT |
| Allow SSH VPN → Bastion | Pass | `192.168.100.0/24` | `192.168.10.0/24` | 22 | Allows VPN clients to reach the bastion |
| Allow SSH Bastion → Site 1 | Pass | `192.168.10.0/24` | `10.0.0.0/8` | 22 | Allows bastion to reach Site 1 VMs |

### S1-FW — OpenVPN interface

| Rule | Action | Source | Destination | Port | Purpose |
|------|--------|--------|-------------|------|---------|
| Block SSH VPN → S1-APP | Block | `192.168.100.0/24` | `10.0.10.0/24` | 22 | Prevents direct VPN access to App Server |
| Block SSH VPN → S1-DB | Block | `192.168.100.0/24` | `10.0.20.0/24` | 22 | Prevents direct VPN access to Database |
| Allow SSH Bastion → Site 1 | Pass | `192.168.10.10/32` | `10.0.0.0/8` | 22 | Allows bastion to reach Site 1 VMs |

---

## Gaps and Deviations

| Gap | Severity | Status | Justification |
|-----|----------|--------|---------------|
| SSH inter-VM not restricted (e.g. S1-APP → S1-DB via SSH) | Low | Risk accepted | VMs don't have SSH keys for each other, password auth is not configured. Risk is minimal. Will be addressed with explicit firewall rules in a future ticket. |
| `bastion-logs` user has `/bin/bash` shell | Low | Risk accepted | Required for rsync compatibility. Access is restricted via SSH `forced command` in `authorized_keys` — only rsync is allowed. |

---

## Reproducibility

All access controls are implemented via:
- **pfSense firewall rules** on S1-FW and S2-FW (documented in firewall runbooks)
- **Ansible roles** stored in the GitOps repository (`roles/bastion`, `roles/managed_vm`)
- **SSH daemon configuration** managed by Ansible (`sshd_config.j2`)

To reproduce the full access isolation setup from scratch, run:

```bash
ansible-playbook playbooks/bastion.yaml
ansible-playbook playbooks/managed_vms.yaml --ask-become-pass
```

Then apply the pfSense firewall rules as documented in the Site 1 and Site 2 firewall runbooks.
