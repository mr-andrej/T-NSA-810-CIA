**Scope:** Complete step-by-step reconstruction of both Proxmox sites (Site 1 on-prem, Site 2 cloud), covering Proxmox setup, network configuration, VM provisioning, firewall rules, VPN, **HashiCorp Vault**, bastion, IPAM, observability, and application deployment.

**Audience:** Infrastructure team (PAR_14). Assumes physical/cloud host access and Proxmox ISOs available.

**Estimated time:**
- **4–6 hours** for an experienced operator running a clean rebuild end-to-end with no surprises.
- **6–10 hours** realistic, accounting for debugging (VPN handshake issues, DNS overrides, firewall rule ordering).

---

## Dependency Map — Build Order

The infrastructure must be built in this order. Each phase depends on the one before it.

```
Phase 0:  Prerequisites & Planning
    │
Phase 0.1: DR Decision Tree (skip phases you don't need)
    │
Phase 1:  Proxmox Hosts (both sites)
    │
Phase 2:  Site 2 — Core (VPN hub, first)
    ├── 2A: S2-FW (pfSense — WAN, VLANs, Admin VPN, S2S VPN server)
    ├── 2B: S2-JS (Bastion VM — networking only)
    └── 2C: S2-MT (Monitoring VM — networking only)
    │
Phase 3:  Site 1 — Core
    ├── 3A: S1-FW (pfSense — VLANs, S2S VPN client)
    ├── 3B: S1-APP (App Server VM)
    └── 3C: S1-DB (Database Server VM — MongoDB)
    │
Phase 4:  Inter-Site Connectivity
    ├── 4A: Site-to-site VPN tunnel verification
    ├── 4B: Inter-site routing
    └── 4C: Inter-site DNS forwarding
    │
Phase 5:  Firewall Hardening (both sites)
    │
Phase 6:  Vault Redeploy (single source of truth for secrets)
    │
Phase 7:  Bastion — SSH Hardening & Access (Vault-driven)
    │
Phase 8:  Observability — JUNKyard
    │
Phase 9:  IPAM — NetBox (secrets from Vault)
    │
Phase 10: Application Deployment
    │
Phase 11: Full Validation
```

---

## Reference — VM Inventory

| VM | Site | VLAN | IP | Role | Gateway |
|---|---|---|---|---|---|
| S1-FW | 1 | WAN / trunk | WAN: public IP, OPT1: `10.0.10.254`, OPT2: `10.0.20.254` | pfSense firewall + VPN client | — |
| S1-APP | 1 | VLAN 10 (Servers) | `10.0.10.1` | Application server | `10.0.10.254` |
| S1-DB | 1 | VLAN 20 (Database) | `10.0.20.1` | Database server (**MongoDB**) | `10.0.20.254` |
| S2-FW | 2 | WAN / trunk | WAN: `5.196.45.7`, OPT1: `192.168.10.1`, OPT2: `192.168.20.254` | pfSense firewall + VPN hub | — |
| S2-JS | 2 | VLAN 10 (DMZ) | `192.168.10.10` | Bastion / jump server | `192.168.10.1` |
| S2-MT | 2 | VLAN 20 (Monitoring) | `192.168.20.1` | Monitoring (JUNKyard), IPAM (NetBox), **Vault**, IaC tools | `192.168.20.254` |

---

## Reference — Network Map

| Network | Subnet | Purpose |
|---|---|---|
| Site 1 VLAN 10 | `10.0.10.0/24` | Application servers |
| Site 1 VLAN 20 | `10.0.20.0/24` | Database servers |
| Site 2 VLAN 10 | `192.168.10.0/24` | DMZ / Bastion |
| Site 2 VLAN 20 | `192.168.20.0/24` | Monitoring / Ops / Vault |
| VPN Tunnel | `172.16.0.0/30` | Site-to-site point-to-point |
| Admin VPN | `192.168.100.0/24` | Remote admin clients |
| Site 1 WAN | `5.196.50.51` (public) | S1-FW WAN |
| Site 2 WAN | `5.196.45.7` (public) | S2-FW WAN |

---

## Phase 0 — Prerequisites & Planning

Before beginning, confirm the following are available:

- [ ] Two Proxmox VE hosts are accessible (one per site), with Proxmox installed from the official ISO
- [ ] pfSense ISO downloaded and uploaded to each Proxmox host's ISO storage
- [ ] Ubuntu 24.04 Server ISO (or cloud-init template) uploaded to each Proxmox host
- [ ] Public IP addresses assigned and confirmed: `5.196.50.51` (Site 1), `5.196.45.7` (Site 2)
- [ ] WAN gateway IPs known for both sites
- [ ] SSH key pairs generated for all team members who need access
- [ ] The `junkyard` source repository is available at https://github.com/mr-andrej/junkyard
- [ ] **Vault recovery materials**:
  - [ ] At least **3 of 5 Shamir unseal keys** physically available (held by 5 different team members)
  - [ ] Vault root token (sealed envelope, offline)
  - [ ] Latest Vault snapshot accessible (default location: `/home/administrator/junkyard/vault-snapshots/` on the lost S2-MT, or off-site copy)
  - [ ] Vault CA cert (`vault-ca.crt`) reachable for distribution to operators
- [ ] **Proxmox API tokens** for both sites (recreated in Phase 1.4 if lost)

**Constraint:** Each site supports a maximum of **3 VMs**. Role assignment must be precise.

---

## Phase 0.1 — DR Decision Tree

This runbook covers a **full rebuild from zero**. For partial failures, jump to the relevant phase.

| Scenario | Action | Skip to |
|---|---|---|
| **Full datacenter loss** (both sites gone) | Follow this runbook end-to-end | Phase 1 |
| **Site 2 lost** (cloud), Site 1 intact | Rebuild Site 2 only, restore Vault snapshot | Phase 1 (Site 2 only) → Phase 2 → Phase 4 → Phase 6 |
| **Site 1 lost**, Site 2 intact | Rebuild Site 1, re-establish tunnel | Phase 1 (Site 1 only) → Phase 3 → Phase 4 |
| **S2-MT VM lost** (Vault + NetBox + JUNKyard gone) | Reprovision VM, restore Vault snapshot, redeploy NetBox + JUNKyard | Phase 2C → Phase 6 → Phase 8 → Phase 9 |
| **S2-JS bastion lost** | Reprovision, run `playbooks/bastion.yaml` (pulls users from Vault) | Phase 2B → Phase 7 |
| **S1-APP lost** | Reprovision, redeploy app | Phase 3B → Phase 10 |
| **S1-DB lost** | Reprovision, restore MongoDB backup | Phase 3C |
| **pfSense VM lost** (config XML backup exists) | Reinstall pfSense, import config XML, skip manual UI steps | Phase 2A.1 / 3A.1 + config import |
| **Vault sealed only** (Vault VM healthy) | Unseal procedure (3 Shamir keys) | See [docs/secret-management/disaster-recovery.md](../secret-management/disaster-recovery.md) scenario 1 |
| **NetBox DB corrupted** | Restore Postgres dump, no rebuild needed | Restore from `/home/administrator/junkyard/netbox-snapshots/` |
| **VPN tunnel down** (everything else fine) | Diagnostic, not rebuild | See [Troubleshooting](#troubleshooting-quick-reference) |

> **Rule of thumb:** anything below Phase 6 (Vault) requires Vault to be running. If you are doing a partial recovery, ensure Vault is healthy before running any Ansible playbook.

---

## Phase 1 — Proxmox Host Setup (Both Sites)

Proxmox VE is the virtualization layer. It hosts VMs but does not perform firewall, VPN, or routing functions.

### 1.1 Install Proxmox VE

Follow the official Proxmox installation guide: https://www.proxmox.com/en/products/proxmox-virtual-environment/get-started

Perform a minimal installation on each host. After install:

- Apply all available security updates
- Disable the enterprise repository if no subscription (replace with the no-subscription repo)
- Set the admin password and note it securely
- Confirm web UI access on `https://<host-ip>:8006`

### 1.2 Configure Network Bridges

Network bridges connect VMs to physical/virtual networks. The bridges are **not** VLAN-aware — VLAN segmentation is handled by pfSense inside the VMs.

#### Site 1

| Bridge | Purpose | Connected To |
|---|---|---|
| `vmbr0` | WAN access | Physical NIC / WAN uplink |

> Site 1 uses a single bridge. S1-FW handles VLAN tagging on a trunk interface (`vtnet0`).

#### Site 2

| Bridge | Purpose | Connected To |
|---|---|---|
| `vmbr0` | WAN access | Physical NIC / WAN uplink |
| `vmbr137` | LAN trunk (internal VLANs) | Internal-only (no physical uplink) |

> Site 2 uses two bridges. S2-FW has `vtnet0` (WAN on `vmbr0`) and `vtnet1` (LAN trunk on `vmbr137`). All other Site 2 VMs connect to `vmbr137`.

Create `vmbr137` on the Site 2 Proxmox host:

**Datacenter → Node → Network → Create → Linux Bridge**

| Field | Value |
|---|---|
| Name | `vmbr137` |
| Autostart | ✅ |
| Comment | LAN trunk — internal VLANs |

No IP address or gateway. Apply the configuration.

### 1.3 Upload ISOs

Upload the pfSense ISO and Ubuntu 24.04 ISO to each Proxmox host:

**Datacenter → Node → local → ISO Images → Upload**

### 1.4 Create Proxmox API Tokens (One per Site)

Ansible playbooks (`playbooks/proxmox_snapshot.yaml`, etc.) authenticate to Proxmox via API tokens, not passwords. Tokens must be created **per site** because they cannot be replicated across nodes.

**Datacenter → Permissions → API Tokens → Add**

| Field | Value |
|---|---|
| User | `<admin>@pve` (or a dedicated `ansible@pve`) |
| Token ID | `ansible` |
| Privilege Separation | ❌ disabled (token inherits user perms) |
| Expire | (none) |

Copy the generated secret immediately — it is shown **only once**.

**Store the tokens in Vault** (after Phase 6, but record them now):

```bash
vault kv put secret/infra/proxmox/site1 \
    api_user='<admin>@pve' \
    api_token_id=ansible \
    api_token_secret='<paste-secret>'

vault kv put secret/infra/proxmox/site2 \
    api_user='<admin>@pve' \
    api_token_id=ansible \
    api_token_secret='<paste-secret>'
```

> If you are doing a full rebuild and Vault is not yet up, write the tokens to a temporary encrypted file (e.g. `age`-encrypted) and import them in Phase 6.

---

## Phase 2 — Site 2 Core (Build First — VPN Hub)

Site 2 is built first because it is the VPN hub. Site 1 cannot establish its tunnel until Site 2's VPN server is running.

### 2A — S2-FW (pfSense Firewall + VPN Hub)

#### 2A.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| VM ID | pick one (e.g. 100) |
| Name | `S2-FW` |
| ISO | pfSense ISO |
| CPU | 2 vCPU |
| RAM | 2 GB |
| Disk | 16 GB (virtio-blk) |
| NIC 1 | `vmbr0` (WAN), Model: VirtIO |
| NIC 2 | `vmbr137` (LAN trunk), Model: VirtIO |

Start the VM and complete the pfSense installer. Accept defaults. After reboot, access the console.

#### 2A.2 Assign Interfaces

During pfSense first-boot wizard or via console:

| Interface | Assignment | Device |
|---|---|---|
| WAN | `vtnet0` | `vmbr0` |
| LAN | `vtnet1` | `vmbr137` |

#### 2A.3 Configure WAN Interface

Navigate to: **Interfaces → WAN**

| Field | Value |
|---|---|
| IPv4 Configuration | Static IPv4 |
| IPv4 Address | `5.196.45.7` (with correct subnet mask, typically `/24`) |
| IPv4 Gateway | The WAN gateway provided by the hosting provider |

Uncheck "Block private networks" and "Block bogon networks" only if the WAN IP is in a private range during testing. Re-enable for production.

#### 2A.4 Configure LAN Interface

Navigate to: **Interfaces → LAN**

| Field | Value |
|---|---|
| IPv4 Configuration | Static IPv4 |
| IPv4 Address | `192.168.1.254/24` |
| IPv4 Gateway | None |

> **Note:** the LAN interface itself carries no production VM traffic — VMs live on the OPT1/OPT2 VLAN sub-interfaces below. The LAN IP exists only so pfSense can reach itself via the trunk parent. Anti-Lockout Rule will keep the WebUI reachable from this subnet during initial setup.

#### 2A.5 Create VLANs

Navigate to: **Interfaces → Assignments → VLANs**

| VLAN ID | Parent Interface | Description |
|---|---|---|
| 10 | `vtnet1` (LAN) | DMZ |
| 20 | `vtnet1` (LAN) | Monitoring / IPAM |

Navigate to: **Interfaces → Assignments** and assign:

- VLAN 10 → OPT1
- VLAN 20 → OPT2

#### 2A.6 Configure VLAN Interfaces

**OPT1 (VLAN 10 — DMZ):**

- Enable: ✅
- Static IPv4: `192.168.10.1/24`
- No upstream gateway

**OPT2 (VLAN 20 — Monitoring):**

- Enable: ✅
- Static IPv4: `192.168.20.254/24`
- No upstream gateway

#### 2A.7 Set Up the Certificate Authority

This CA is shared by both the Admin VPN and the site-to-site VPN.

Navigate to: **System → Cert. Manager → CAs → Add**

| Field | Value |
|---|---|
| Method | Create an internal Certificate Authority |
| Descriptive name | `site2-vpn-ca` |
| Key type | RSA, 2048 bit |
| Digest Algorithm | SHA256 |
| Lifetime | 3650 |
| Common Name | `site2-vpn-ca` |

Save.

> **DR note:** if the CA already exists in Vault under `secret/vpn/site2-ca` (cert + key), import it instead via **Method → Import an existing Certificate Authority**. This preserves the existing trust chain so previously-issued certificates remain valid.

#### 2A.8 Set Up the Admin VPN (Port 1194)

This VPN provides remote access for administrators.

**Create the server certificate:**

Navigate to: **System → Cert. Manager → Certificates → Add**

| Field | Value |
|---|---|
| Method | Create an internal Certificate |
| Descriptive name | `site2-vpn-server` |
| Certificate Authority | `site2-vpn-ca` |
| Key type | RSA, 2048 bit |
| Digest Algorithm | SHA256 |
| Lifetime | 398 |
| Common Name | `site2-vpn-server` |
| Certificate Type | Server Certificate |

**Create the OpenVPN server:**

Navigate to: **VPN → OpenVPN → Servers → Add**

| Field | Value |
|---|---|
| Server mode | Remote Access (SSL/TLS + User Auth) |
| Backend | Local Database |
| Device mode | tun |
| Protocol | UDP on IPv4 only |
| Interface | WAN |
| Local port | 1194 |
| TLS Configuration | ✅ Use a TLS Key (auto-generate) |
| Peer Certificate Authority | `site2-vpn-ca` |
| Server certificate | `site2-vpn-server` |
| DH Parameter Length | 2048 bit |
| Data Encryption Algorithms | AES-256-GCM, AES-128-GCM, CHACHA20-POLY1305 |
| Auth digest algorithm | SHA256 |
| IPv4 Tunnel Network | `192.168.100.0/24` |
| IPv4 Local networks | `192.168.1.0/24, 192.168.10.0/24, 192.168.20.0/24, 10.0.0.0/8` |
| Topology | Subnet |

> Including `10.0.0.0/8` in Local Networks allows admin clients to reach Site 1 through the S2S tunnel once it is established later.

**Create a VPN user:**

Navigate to: **System → User Manager → Add**

| Field | Value |
|---|---|
| Username | `<admin-username>-vpn` |
| Password | (strong password) |
| Certificate | ✅ Create a user certificate using `site2-vpn-ca` |

**Install the client export package:**

Navigate to: **System → Package Manager → Available Packages**

Install `openvpn-client-export`.

**Export the .ovpn file:**

Navigate to: **VPN → OpenVPN → Client Export**

Find the user → Export "Most Clients" → download the `.ovpn` file. Distribute to the admin team.

#### 2A.9 Set Up the Site-to-Site VPN Server (Port 1195)

This VPN connects Site 1 to Site 2.

**Create the server certificate:**

Navigate to: **System → Cert. Manager → Certificates → Add**

| Field | Value |
|---|---|
| Method | Create an internal Certificate |
| Descriptive name | `s2s-site2-server` |
| Certificate Authority | `site2-vpn-ca` |
| Key type | RSA, 2048 |
| Digest Algorithm | SHA256 |
| Lifetime | 398 |
| Common Name | `s2s-site2-server` |
| Certificate Type | Server Certificate |

**Create the client certificate (for Site 1):**

Navigate to: **System → Cert. Manager → Certificates → Add**

| Field | Value |
|---|---|
| Method | Create an internal Certificate |
| Descriptive name | `s2s-site1-client` |
| Certificate Authority | `site2-vpn-ca` |
| Key type | RSA, 2048 |
| Digest Algorithm | SHA256 |
| Lifetime | 398 |
| Common Name | `s2s-site1-client` |
| Certificate Type | User Certificate |

**Create the OpenVPN server:**

Navigate to: **VPN → OpenVPN → Servers → Add**

| Field | Value |
|---|---|
| Server mode | Peer to Peer (SSL/TLS) |
| Protocol | UDP on IPv4 only |
| Interface | WAN |
| Local port | 1195 |
| Description | `S2S Site1-Site2` |
| TLS Configuration | ✅ Use a TLS Key (auto-generate) |
| Peer Certificate Authority | `site2-vpn-ca` |
| Server certificate | `s2s-site2-server` |
| DH Parameter Length | 2048 bit |
| Auth digest algorithm | SHA256 |
| IPv4 Tunnel Network | `172.16.0.0/30` |
| IPv4 Local networks | `192.168.1.0/24, 192.168.10.0/24, 192.168.20.0/24, 192.168.100.0/24` |
| IPv4 Remote networks | `10.0.10.0/24, 10.0.20.0/24` |

> `192.168.100.0/24` must be included in Local Networks so S1-FW learns the return route for Admin VPN client traffic.

**Export credentials for Site 1:**

The Client Export Utility does not support Peer-to-Peer servers. Export manually:

1. **System → Cert. Manager → CAs** → export `site2-vpn-ca` certificate → save as `site2-vpn-ca.crt`
2. **System → Cert. Manager → Certificates** → export `s2s-site1-client` certificate and private key → save as `s2s-site1-client.crt` and `s2s-site1-client.key`
3. **VPN → OpenVPN → Servers → Edit** (port 1195) → copy the auto-generated TLS Key

> **After Vault is up (Phase 6)**, store these materials in Vault:
> - `secret/vpn/site2-ca` (fields: `cert`, `key`)
> - `secret/vpn/s2s-site1-client` (fields: `cert`, `key`, `tls_auth`)
>
> Future DR rebuilds can then import directly from Vault instead of regenerating.

Assemble the `.ovpn` file:

```
client
dev tun
proto udp4
remote 5.196.45.7 1195
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
connect-retry 5
connect-retry-max infinite
verb 3

<ca>
... paste site2-vpn-ca.crt contents ...
</ca>

<cert>
... paste s2s-site1-client.crt contents ...
</cert>

<key>
... paste s2s-site1-client.key contents ...
</key>

<tls-auth>
... paste TLS static key ...
</tls-auth>
key-direction 1
```

Store this file securely. It will be used in Phase 3A.

#### 2A.10 Initial S2-FW Firewall Rules (Minimal — Enough to Continue Build)

Apply the minimal rules needed to continue the build. Full hardening happens in Phase 5.

**WAN rules** (Firewall → Rules → WAN):

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Block | any | * | * | * | [EMERGENCY] Kill switch (disabled by default) |
| 2 | Pass | UDP | `5.196.50.51` | WAN address | 1195 | S2S VPN from Site 1 |
| 3 | Pass | UDP | any | WAN address | 1194 | Admin VPN clients |
| 4 | Block | any | * | * | * | Block all other WAN |

**OpenVPN rules** (Firewall → Rules → OpenVPN):

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | any | any | any | any | Allow VPN traffic (temporary — will be tightened in Phase 5) |

#### 2A.11 DNS Resolver Setup

Navigate to: **Services → DNS Resolver → General Settings**

| Option | Value |
|---|---|
| Enable DNS Resolver | ✅ |
| Network Interfaces | All |
| Outgoing Network Interfaces | All |
| DNSSEC | ✅ |
| Register DHCP leases | ✅ |
| Register DHCP static mappings | ✅ |
| Register OpenVPN clients | ✅ |

**Host Overrides** (Services → DNS Resolver → Host Overrides):

| Host | Domain | IP | Description |
|---|---|---|---|
| `bastion` | `site2.internal` | `192.168.10.10` | Bastion VM |
| `ops` | `site2.internal` | `192.168.20.1` | Monitoring / IPAM / Vault VM |
| `vault` | `site2.internal` | `192.168.20.1` | Vault API (same host as ops) |
| `firewall` | `site2.internal` | `192.168.1.254` | pfSense S2-FW |

#### 2A.12 DHCP Server Setup

Navigate to: **Services → DHCP Server**

**OPT1 (VLAN 10 — DMZ):**

| Field | Value |
|---|---|
| Enable | ✅ |
| Range | `192.168.10.100` – `192.168.10.200` |
| Gateway | `192.168.10.1` |
| DNS Server | `192.168.10.1` |
| Domain Name | `site2.internal` |

**OPT2 (VLAN 20 — Monitoring):**

| Field | Value |
|---|---|
| Enable | ✅ |
| Range | `192.168.20.100` – `192.168.20.200` |
| Gateway | `192.168.20.254` |
| DNS Server | `192.168.20.254` |
| Domain Name | `site2.internal` |

> All hosts use static IPs via Netplan. DHCP pools are reserved for future use.

---

### 2B — S2-JS (Bastion VM)

#### 2B.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| Name | `S2-JS` |
| ISO | Ubuntu 24.04 Server |
| CPU | 1 vCPU |
| RAM | 1 GB |
| Disk | 16 GB |
| NIC | `vmbr137` (LAN trunk), Model: VirtIO |

Install Ubuntu with a minimal profile.

#### 2B.2 Configure Networking

Edit `/etc/netplan/50-cloud-init.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: false
  vlans:
    enp6s18.10:
      id: 10
      link: enp6s18
      addresses: [192.168.10.10/24]
      nameservers:
        addresses: [192.168.10.1, 8.8.8.8]
        search: [site2.internal]
      routes:
        - to: default
          via: 192.168.10.1
```

> Do **not** assign an IP directly on `enp6s18` — leave it without an address, just up.

Apply:

```bash
sudo netplan apply
```

Configure systemd-resolved — edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=192.168.10.1
FallbackDNS=8.8.8.8
```

```bash
sudo systemctl restart systemd-resolved
```

#### 2B.3 Add Static Route to Site 1

The bastion needs a route to reach Site 1 networks through the tunnel:

```bash
sudo ip route add 10.0.0.0/8 via 192.168.10.1
```

Make persistent by adding to the netplan config under the VLAN interface:

```yaml
      routes:
        - to: default
          via: 192.168.10.1
        - to: 10.0.0.0/8
          via: 192.168.10.1
```

```bash
sudo netplan apply
```

#### 2B.4 Verify Connectivity

```bash
ping -c 2 192.168.10.1     # pfSense OPT1 gateway
ping -c 2 google.com        # Internet via pfSense
```

> SSH hardening and access configuration happen in Phase 7 (after Vault is up), so user keys are pulled from Vault rather than being pasted manually.

---

### 2C — S2-MT (Monitoring VM)

#### 2C.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| Name | `S2-MT` |
| ISO | Ubuntu 24.04 Server |
| CPU | 2 vCPU |
| RAM | 2–4 GB |
| Disk | 32 GB |
| NIC | `vmbr137` (LAN trunk), Model: VirtIO |

Install Ubuntu with a minimal profile.

#### 2C.2 Configure Networking

Edit `/etc/netplan/50-cloud-init.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: false
  vlans:
    enp6s18.20:
      id: 20
      link: enp6s18
      addresses: [192.168.20.1/24]
      nameservers:
        addresses: [192.168.20.254, 8.8.8.8]
        search: [site2.internal]
      routes:
        - to: default
          via: 192.168.20.254
```

Apply:

```bash
sudo netplan apply
```

Configure systemd-resolved — edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=192.168.20.254
FallbackDNS=8.8.8.8
```

```bash
sudo systemctl restart systemd-resolved
```

#### 2C.3 Verify Connectivity

```bash
ping -c 2 192.168.20.254    # pfSense OPT2 gateway
ping -c 2 google.com         # Internet via pfSense
```

---

## Phase 3 — Site 1 Core

### 3A — S1-FW (pfSense Firewall + VPN Client)

#### 3A.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| Name | `S1-FW` |
| ISO | pfSense ISO |
| CPU | 2 vCPU |
| RAM | 2 GB |
| Disk | 16 GB |
| NIC 1 | `vmbr0` (WAN), Model: VirtIO |

> Site 1 uses a single NIC. pfSense handles VLAN trunking on the same interface as WAN (`vtnet0`).

Install pfSense. After first boot:

#### 3A.2 Assign Interface

| Interface | Assignment |
|---|---|
| WAN | `vtnet0` |

#### 3A.3 Configure WAN

Navigate to: **Interfaces → WAN**

| Field | Value |
|---|---|
| IPv4 Configuration | Static IPv4 |
| IPv4 Address | `5.196.50.51` (with correct mask) |
| IPv4 Gateway | WAN gateway provided by hosting |

#### 3A.4 Create VLANs

Navigate to: **Interfaces → Assignments → VLANs**

| VLAN ID | Parent Interface | Description |
|---|---|---|
| 10 | `vtnet0` (LAN) | SERVERS |
| 20 | `vtnet0` (LAN) | DATABASE |

Navigate to: **Interfaces → Assignments** and assign:

- VLAN 10 → OPT1
- VLAN 20 → OPT2

#### 3A.5 Configure VLAN Interfaces

**OPT1 (VLAN 10 — Servers):**

- Enable: ✅
- Static IPv4: `10.0.10.254/24`
- No upstream gateway

**OPT2 (VLAN 20 — Database):**

- Enable: ✅
- Static IPv4: `10.0.20.254/24`
- No upstream gateway

#### 3A.6 Import Certificates & Configure VPN Client

**Import the CA:**

Navigate to: **System → Cert. Manager → CAs → Add**

| Field | Value |
|---|---|
| Method | Import an existing Certificate Authority |
| Descriptive name | `site2-vpn-ca` |
| Certificate data | Paste contents of `site2-vpn-ca.crt` (from Phase 2A.9) |

**Import the client certificate:**

Navigate to: **System → Cert. Manager → Certificates → Add**

| Field | Value |
|---|---|
| Method | Import an existing Certificate |
| Descriptive name | `s2s-site1-client` |
| Certificate data | Paste contents of `s2s-site1-client.crt` |
| Private key data | Paste contents of `s2s-site1-client.key` |

**Configure the OpenVPN client:**

Navigate to: **VPN → OpenVPN → Clients → Add**

| Field | Value |
|---|---|
| Server mode | Peer to Peer (SSL/TLS) |
| Protocol | UDP on IPv4 only |
| Interface | WAN |
| Server host | `5.196.45.7` |
| Server port | 1195 |
| Description | `S2S Site1-Site2` |
| TLS Configuration | ✅ Use a TLS Key — ❌ uncheck "Automatically generate" |
| TLS Key | Paste the static key from the `.ovpn` file |
| Peer Certificate Authority | `site2-vpn-ca` |
| Client certificate | `s2s-site1-client` |
| Data Encryption Algorithms | AES-256-GCM |
| Auth digest algorithm | SHA256 |
| IPv4 Tunnel Network | `172.16.0.0/30` |
| IPv4 Remote networks | `192.168.1.0/24, 192.168.10.0/24, 192.168.20.0/24, 192.168.100.0/24` |

Save.

#### 3A.7 Initial S1-FW Firewall Rules

**WAN rules:**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Block | any | * | * | * | [EMERGENCY] Kill switch (disabled by default) |
| 2 | Pass | UDP | `5.196.45.7` | WAN address | 1195 | S2S VPN from S2-FW |
| 3 | Block | any | * | * | * | Block all other WAN |

**OpenVPN rules (temporary — tightened in Phase 5):**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | any | any | any | any | Allow tunnel traffic (temporary) |

#### 3A.8 DNS Resolver Setup

Navigate to: **Services → DNS Resolver → General Settings**

| Option | Value |
|---|---|
| Enable DNS Resolver | ✅ |
| Network Interfaces | All |
| Outgoing Network Interfaces | All |
| DNSSEC | ✅ |
| Register DHCP leases | ✅ |
| Register DHCP static mappings | ✅ |
| DNS Query Forwarding | ❌ **(must be disabled for Domain Overrides)** |

**Host Overrides** (Services → DNS Resolver → Host Overrides):

| Host | Domain | IP | Description |
|---|---|---|---|
| `app` | `site1.internal` | `10.0.10.1` | App Server |
| `db` | `site1.internal` | `10.0.20.1` | Database Server (MongoDB) |
| `firewall` | `site1.internal` | `10.0.10.254` | pfSense S1-FW |

#### 3A.9 DHCP Server Setup

**OPT1 (VLAN 10 — Servers):**

| Field | Value |
|---|---|
| Enable | ✅ |
| Range | `10.0.10.100` – `10.0.10.200` |
| Gateway | `10.0.10.254` |
| DNS Server | `10.0.10.254` |
| Domain Name | `site1.internal` |

**OPT2 (VLAN 20 — Database):**

| Field | Value |
|---|---|
| Enable | ✅ |
| Range | `10.0.20.100` – `10.0.20.200` |
| Gateway | `10.0.20.254` |
| DNS Server | `10.0.20.254` |
| Domain Name | `site1.internal` |

#### 3A.10 Verify VPN Tunnel

Navigate to: **Status → OpenVPN**

The client `S2S Site1-Site2` should show **Connected** with a valid virtual address (`172.16.0.2`).

If status shows "Waiting for response from peer":

1. Restart OpenVPN on Site 1: **Status → OpenVPN** → click restart
2. Restart OpenVPN on Site 2: same
3. Verify WAN firewall rules allow UDP 1195 on both sides

```
ping 172.16.0.1    # from S1-FW — should reach S2-FW tunnel endpoint
```

---

### 3B — S1-APP (Application Server)

#### 3B.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| Name | `S1-APP` |
| ISO | Ubuntu 24.04 Server |
| CPU | 2 vCPU |
| RAM | 2–4 GB |
| Disk | 32 GB |
| NIC | Proxmox LAN bridge (`vmbr0` trunk), Model: VirtIO |

Install Ubuntu with a minimal profile.

#### 3B.2 Configure Networking

Edit `/etc/netplan/00-installer-config.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: false
  vlans:
    enp6s18.10:
      id: 10
      link: enp6s18
      addresses:
        - 10.0.10.1/24
      nameservers:
        addresses:
          - 10.0.10.254
          - 8.8.8.8
        search:
          - site1.internal
      routes:
        - to: default
          via: 10.0.10.254
```

> Do **not** assign an IP on `enp6s18`. The VLAN sub-interface handles all tagged traffic.

Apply:

```bash
sudo netplan apply
```

Configure systemd-resolved — edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=10.0.10.254
FallbackDNS=8.8.8.8
```

```bash
sudo systemctl restart systemd-resolved
```

Verify:

```bash
ip a                 # enp6s18.10 should show 10.0.10.1/24
ip route             # default via 10.0.10.254
resolvectl status    # Current DNS should be 10.0.10.254
ping -c 2 10.0.10.254
ping -c 2 google.com
```

---

### 3C — S1-DB (Database Server — MongoDB)

#### 3C.1 Create the VM in Proxmox

| Setting | Value |
|---|---|
| Name | `S1-DB` |
| ISO | Ubuntu 24.04 Server |
| CPU | 2 vCPU |
| RAM | 2–4 GB |
| Disk | 32+ GB |
| NIC | Proxmox LAN bridge (`vmbr0` trunk), Model: VirtIO |

Install Ubuntu with a minimal profile.

#### 3C.2 Configure Networking

Edit `/etc/netplan/50-cloud-init.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: false
  vlans:
    enp6s18.20:
      id: 20
      link: enp6s18
      addresses:
        - 10.0.20.1/24
      nameservers:
        addresses:
          - 10.0.20.254
          - 8.8.8.8
        search:
          - site1.internal
      routes:
        - to: default
          via: 10.0.20.254
```

Apply:

```bash
sudo netplan apply
```

Configure systemd-resolved — edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=10.0.20.254
FallbackDNS=8.8.8.8
```

```bash
sudo systemctl restart systemd-resolved
```

Verify:

```bash
ip a                 # enp6s18.20 should show 10.0.20.1/24
ip route             # default via 10.0.20.254
ping -c 2 10.0.20.254
ping -c 2 google.com
```

> If any VM shows `NO-CARRIER` after config changes, a full VM reboot via the Proxmox UI resolves it.

> MongoDB itself is installed via the `mongodb` Ansible role in Phase 10.

---

## Phase 4 — Inter-Site Connectivity

At this point, both pfSense instances are running and the VPN tunnel should be established. This phase ensures traffic can flow correctly between sites.

### 4A — Verify and Configure Inter-Site Routing

**On S2-FW (VPN → OpenVPN → Servers → edit port 1195), confirm:**

| Field | Value |
|---|---|
| IPv4 Local networks | `192.168.1.0/24, 192.168.10.0/24, 192.168.20.0/24, 192.168.100.0/24` |
| IPv4 Remote networks | `10.0.10.0/24, 10.0.20.0/24` |

**On S1-FW (VPN → OpenVPN → Clients → edit), confirm:**

| Field | Value |
|---|---|
| IPv4 Remote networks | `192.168.1.0/24, 192.168.10.0/24, 192.168.20.0/24, 192.168.100.0/24` |

After saving any changes, restart the OpenVPN client on Site 1: **Status → OpenVPN → restart**.

**Verify routes on S1-FW** (Diagnostics → Routes):

| Destination | Gateway | Interface |
|---|---|---|
| `192.168.10.0/24` | `172.16.0.1` | ovpnc1 |
| `192.168.20.0/24` | `172.16.0.1` | ovpnc1 |

**Test cross-site connectivity:**

From S1-DB:

```bash
ping -c 2 192.168.20.1     # S2-MT via VPN tunnel
```

Expected: 0% packet loss.

### 4B — Configure Inter-Site DNS Forwarding

**On S1-FW — Domain Override:**

Navigate to: **Services → DNS Resolver → Domain Overrides**

| Domain | Lookup Server | Description |
|---|---|---|
| `site2.internal` | `172.16.0.1` | Forward Site 2 queries to S2-FW via tunnel |

**On S2-FW — Domain Override:**

Navigate to: **Services → DNS Resolver → Domain Overrides**

| Domain | Lookup Server | Description |
|---|---|---|
| `site1.internal` | `172.16.0.2` | Forward Site 1 queries to S1-FW via tunnel |

> DNS Query Forwarding **must be disabled** on both pfSense instances for Domain Overrides to work. If it is enabled, pfSense forwards all queries to upstream DNS and ignores overrides entirely.

**Firewall rules for DNS forwarding on S1-FW (OpenVPN interface):**

Two rules must allow DNS queries to reach S1-FW from Site 2:

| Source | Destination | Port | Description |
|---|---|---|---|
| `192.168.0.0/16` | This Firewall | `53 TCP/UDP` | DNS from Site 2 VMs via tunnel |
| `172.16.0.0/30` | This Firewall | `53 TCP/UDP` | DNS from S2-FW resolver via tunnel |

> The second rule is critical — when S2-FW processes a Domain Override, the query originates from `172.16.0.1` (the tunnel IP), not from a VM IP.

**Verify DNS forwarding:**

From S2-JS (bastion):

```bash
nslookup app.site1.internal 192.168.10.1      # → 10.0.10.1
nslookup db.site1.internal 192.168.10.1       # → 10.0.20.1
```

From S1-APP:

```bash
nslookup bastion.site2.internal 10.0.10.254   # → 192.168.10.10
nslookup ops.site2.internal 10.0.10.254       # → 192.168.20.1
```

---

## Phase 5 — Firewall Hardening (Both Sites)

Replace the temporary "allow all" OpenVPN rules with least-privilege rules. All interfaces follow deny-by-default with an explicit `Block all` rule at the bottom.

> pfSense is a stateful firewall — rules only need to allow the initiating direction. Return traffic is automatically permitted.

> **Rule ordering is critical.** Block rules for direct SSH must appear **before** broader inter-site allow rules.

### 5.1 Site 2 Firewall — Full Rule Set

**Firewall Alias** (Firewall → Aliases → Ports):

| Name | Type | Ports | Description |
|---|---|---|---|
| HTTPS_HTTP | Port | 80, 443 | HTTP and HTTPS ports |

**WAN Rules** (Firewall → Rules → WAN):

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Block | any | * | * | * | [EMERGENCY] Kill switch (disabled) |
| 2 | Pass | UDP | `5.196.50.51` | WAN address | 1195 | S2S VPN from S1-FW |
| 3 | Pass | UDP | any | WAN address | 1194 | Admin VPN clients |
| 4 | Block | any | * | * | * | Block all other WAN |

**LAN Rules** (Firewall → Rules → LAN):

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | any | * | LAN address | 443, 80 | Anti-Lockout Rule (system) |
| 2 | Pass | TCP/UDP | `192.168.1.0/24` | This Firewall | 53 | DNS from LAN |
| 3 | Block | any | * | * | * | Block all other LAN |

**OPT1 Rules (VLAN 10 — DMZ / Bastion):**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | `192.168.10.0/24` | any | 53 | DNS |
| 2 | Pass | TCP | `192.168.10.0/24` | `192.168.20.0/24` | 22 | SSH bastion → Monitoring |
| 3 | Pass | TCP | `192.168.10.0/24` | `192.168.20.1/32` | 8200 | Vault API from bastion |
| 4 | Pass | TCP | `192.168.10.0/24` | `10.0.0.0/8` | 22 | SSH bastion → Site 1 VMs via tunnel |
| 5 | Pass | TCP | `192.168.10.0/24` | any | HTTPS_HTTP | System updates |
| 6 | Pass | TCP | `192.168.10.0/24` | `192.168.20.1/32` | 5514 | Syslog to JUNKyard |
| 7 | Block | any | * | * | * | Block all other DMZ |

**OPT2 Rules (VLAN 20 — Monitoring):**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | `192.168.20.0/24` | any | 53 | DNS |
| 2 | Pass | ICMP | `192.168.20.0/24` | This Firewall | * | Ping gateway |
| 3 | Pass | TCP | `192.168.20.0/24` | `10.0.0.0/8` | 22 | SSH Ansible → Site 1 |
| 4 | Pass | TCP | `192.168.20.0/24` | any | HTTPS_HTTP | System updates |
| 5 | Block | any | * | * | * | Block all other Monitoring |

**OpenVPN Rules** (applies to both VPN instances):

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP | `192.168.100.0/24` | This Firewall | 443 | Admin VPN → pfSense WebUI |
| 2 | Pass | TCP | `172.16.0.0/30` | This Firewall | 443 | Tunnel → pfSense WebUI |
| 3 | Block | TCP | `192.168.100.0/24` | `192.168.20.0/24` | 22 | Block direct SSH Admin → Monitoring |
| 4 | Pass | TCP | `192.168.100.0/24` | `192.168.20.0/24` | 80 | HTTP — NetBox access from Admin VPN |
| 5 | Pass | TCP | `192.168.100.0/24` | `192.168.20.1/32` | 8200 | Vault API from Admin VPN |
| 6 | Pass | TCP | `192.168.100.0/24` | `192.168.10.0/24` | 22 | Admin VPN → bastion SSH |
| 7 | Pass | TCP/UDP | `10.0.0.0/8` | `192.168.0.0/16` | * | Inter-site: S1 → S2 via tunnel |
| 8 | Pass | TCP/UDP | `172.16.0.0/30` | `192.168.20.1/32` | 5514 | Syslog S1-FW → JUNKyard |
| 9 | Pass | TCP | `192.168.100.0/24` | `10.0.0.0/8` | 443 | Admin VPN → S1 pfSense WebUI |
| 10 | Block | any | * | * | * | Block all other tunnel traffic |

---

### 5.2 Site 1 Firewall — Full Rule Set

**Firewall Alias** (Firewall → Aliases → Ports):

| Name | Type | Ports | Description |
|---|---|---|---|
| HTTPS_HTTP | Port | 80, 443 | HTTP and HTTPS ports |

**WAN Rules:**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Block | any | * | * | * | [EMERGENCY] Kill switch (disabled) |
| 2 | Pass | UDP | `5.196.45.7` | WAN address | 1195 | S2S VPN from S2-FW |
| 3 | Block | any | * | * | * | Block all other WAN |

**LAN Rules:**

> The default pfSense LAN interface on Site 1 carries no production traffic — Site 1 VMs live on the OPT1/OPT2 VLAN sub-interfaces, not the parent LAN. Leave only the system Anti-Lockout Rule in place; remove the auto-created "Allow LAN to any" rule to enforce deny-by-default.

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | any | * | LAN address | 443, 80 | Anti-Lockout Rule (system) |
| 2 | Block | any | * | * | * | Block all other LAN |

**OPT1 Rules (VLAN 10 — Servers / S1-APP):**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | `10.0.10.0/24` | This Firewall | 53 | DNS |
| 2 | Pass | ICMP | `10.0.10.0/24` | This Firewall | * | Ping gateway |
| 3 | Pass | TCP | `10.0.10.0/24` | `10.0.20.0/24` | 27017 | App → Database (MongoDB) |
| 4 | Pass | TCP | `10.0.10.0/24` | `192.168.20.1/32` | 5514 | Syslog to JUNKyard |
| 5 | Pass | TCP | `10.0.10.0/24` | `192.168.20.1/32` | 8200 | Vault API |
| 6 | Pass | TCP | `10.0.10.0/24` | any | HTTPS_HTTP | System updates |
| 7 | Block | any | * | * | * | Block all other OPT1 |

**OPT2 Rules (VLAN 20 — Database / S1-DB):**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP | `10.0.10.0/24` | `10.0.20.0/24` | 27017 | App → Database (inbound, MongoDB) |
| 2 | Pass | TCP/UDP | `10.0.20.0/24` | This Firewall | 53 | DNS |
| 3 | Pass | ICMP | `10.0.20.0/24` | This Firewall | * | Ping gateway |
| 4 | Pass | TCP | `10.0.20.0/24` | `192.168.20.1/32` | 5514 | Syslog to JUNKyard |
| 5 | Pass | TCP | `10.0.20.0/24` | `192.168.20.1/32` | 8200 | Vault API |
| 6 | Pass | TCP | `10.0.20.0/24` | any | HTTPS_HTTP | System updates |
| 7 | Block | any | * | * | * | Block all other OPT2 |

**OpenVPN Rules:**

| # | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP | `172.16.0.0/30` | This Firewall | 443 | Tunnel → pfSense WebUI |
| 2 | Pass | TCP | `192.168.100.0/24` | This Firewall | 443 | Admin VPN → pfSense WebUI |
| 3 | Block | TCP | `192.168.100.0/24` | `10.0.10.0/24` | 22 | Block direct SSH Admin → S1-APP |
| 4 | Block | TCP | `192.168.100.0/24` | `10.0.20.0/24` | 22 | Block direct SSH Admin → S1-DB |
| 5 | Pass | TCP | `192.168.10.10/32` | `10.0.0.0/8` | 22 | Bastion SSH → Site 1 VMs |
| 6 | Pass | TCP/UDP | `192.168.0.0/16` | `10.0.0.0/8` | * | Inter-site: S2 → S1 via tunnel |
| 7 | Pass | TCP/UDP | `172.16.0.0/30` | `192.168.20.1/32` | 5514 | Syslog S1-FW → JUNKyard |
| 8 | Pass | TCP/UDP | `192.168.0.0/16` | This Firewall | 53 | DNS from Site 2 via tunnel |
| 9 | Pass | TCP/UDP | `172.16.0.0/30` | This Firewall | 53 | DNS from S2-FW resolver via tunnel |
| 10 | Block | any | * | * | * | Block all other tunnel traffic |

> **Rule ordering matters.** The SSH blocks (#3, #4) must appear before the inter-site allow (#6). All SSH to Site 1 must pass through the bastion.

---

## Phase 6 — Vault Redeploy (Single Source of Truth for Secrets)

HashiCorp Vault is the canonical secret store for the whole infrastructure (Proxmox API tokens, NetBox creds, admin SSH pubkeys, VPN certs). It runs on S2-MT alongside NetBox and JUNKyard.

**No Ansible playbook beyond this point works without Vault being healthy** — bastion users, NetBox secrets, etc. all pull from it at runtime.

### 6.1 Deployment Method

Because the bastion is not yet hardened at this stage, **run the Vault playbook from the S2-MT console** (Proxmox VM console — bypasses the SSH/bastion chain entirely):

1. Open the S2-MT console via Proxmox UI.
2. Clone the infrastructure repository:
   ```bash
   git clone https://github.com/mr-andrej/T-NSA-810-CIA.git
   cd T-NSA-810-CIA/ansible
   ansible-galaxy collection install -r requirements.yml
   ```
3. Run the Vault playbook **locally** (against `localhost`):
   ```bash
   ansible-playbook playbooks/vault.yaml -c local -i 'localhost,'
   ```

The role installs Vault, generates the TLS material under `/etc/vault.d/tls/`, deploys the systemd unit (`MemoryMax=200M`, `disable_mlock=true`), and starts the service in a sealed state.

### 6.2 Initialise OR Restore

**Two paths:**

#### 6.2.a Fresh init (first ever deployment, no snapshot)

```bash
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/vault.d/tls/ca.crt

vault operator init -key-shares=5 -key-threshold=3
# Outputs 5 Shamir keys + initial root token.
# IMPORTANT: distribute the 5 keys to 5 different team members IMMEDIATELY.
# Store the root token in a sealed envelope offline.
```

#### 6.2.b Restore from snapshot (DR scenario — preserves all existing secrets)

```bash
# Copy the snapshot from off-site backup (or junkyard if surviving)
scp <backup-host>:vault-snapshot-YYYYMMDD.snap /tmp/

vault operator raft snapshot restore -force /tmp/vault-snapshot-YYYYMMDD.snap
# Note: existing Shamir keys remain valid after restore.
```

> The role's daily snapshot writes to `/home/administrator/junkyard/vault-snapshots/` with 14-day retention. Off-site copies must be configured separately (out of scope here).

### 6.3 Unseal

Three of the five Shamir-key holders must each run:

```bash
vault operator unseal <key>
```

After the 3rd key, `vault status` should show `Sealed: false`.

### 6.4 Bootstrap Auth Methods and Policies (fresh init only)

Skip this if you restored from a snapshot — auth methods, policies, and KV data come back with the restore.

```bash
vault login <initial-root-token>

# Enable KV v2 at secret/
vault secrets enable -version=2 -path=secret kv

# Enable auth methods
vault auth enable userpass
vault auth enable approle

# Load policies from the repo
cd /root/T-NSA-810-CIA
vault policy write admin-ops      policies/admin-ops.hcl
vault policy write ansible-deploy policies/ansible-deploy.hcl
vault policy write ansible-netbox policies/ansible-netbox.hcl
vault policy write audit-read     policies/audit-read.hcl

# Create the Ansible AppRole
vault write auth/approle/role/ansible-deploy \
    token_policies=ansible-deploy,ansible-netbox \
    token_ttl=1h secret_id_ttl=720h

# Get role_id and secret_id for distribution
vault read auth/approle/role/ansible-deploy/role-id
vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id

# Create one userpass account per human admin
for admin in lucas paul andrej; do
  vault write auth/userpass/users/$admin \
      password=changeme-temporary policies=admin-ops
done
```

### 6.5 Populate Required Secrets

If you did a fresh init (not a restore), populate the secrets used by later phases:

```bash
# Bootstrap from a script if available
sudo bash /root/T-NSA-810-CIA/scripts/vault-populate.sh

# Otherwise, write each path manually. Minimum set required for subsequent phases:
vault kv put secret/infra/proxmox/site1 api_user=... api_token_id=... api_token_secret=...
vault kv put secret/infra/proxmox/site2 api_user=... api_token_id=... api_token_secret=...

vault kv put secret/infra/ssh/admins/lucas   public_key="ssh-ed25519 AAAA..."
vault kv put secret/infra/ssh/admins/paul    public_key="ssh-ed25519 AAAA..."
vault kv put secret/infra/ssh/admins/andrej  public_key="ssh-ed25519 AAAA..."
vault kv put secret/infra/ssh/bastion        public_key="ssh-ed25519 AAAA..." private_key=@bastion_key

vault kv put secret/netbox/db        password='<strong-password>'
vault kv put secret/netbox/django    secret_key='<50-char-random>'
vault kv put secret/netbox/superuser password='<strong-password>'
vault kv put secret/netbox/api       token='<generated-after-Phase-9>'

vault kv put secret/vpn/site2-ca         cert=@site2-vpn-ca.crt key=@site2-vpn-ca.key
vault kv put secret/vpn/s2s-site1-client cert=@s2s-site1-client.crt key=@s2s-site1-client.key tls_auth=@tls_auth.key
```

### 6.6 Distribute Credentials to Operators

Each operator needs three things on their workstation:

| File / value | How |
|---|---|
| `~/.ansible/vault-ca.crt` | Copy `/etc/vault.d/tls/ca.crt` from S2-MT |
| `~/.ansible/vault-secret-id` | One per operator, from `vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id` |
| `VAULT_ADDR`, `VAULT_CACERT` env vars | Add to shell rc — see [docs/secret-management/wiki-page-Vault-Implementation.md](../secret-management/wiki-page-Vault-Implementation.md) §1–4 |

### 6.7 Open the Firewall Port (if not done in Phase 5)

Phase 5's OPT1 rule #3 and OpenVPN rule #5 must already allow `*.0.0/* → 192.168.20.1:8200`. Verify with:

```bash
# From bastion (after Phase 7) or laptop on Admin VPN
vault status
# Should return Sealed: false, Initialized: true
```

### 6.8 Verify

```bash
vault status            # Sealed: false, Initialized: true
vault kv list secret/   # Lists all populated paths
vault audit list        # Audit device enabled
```

---

## Phase 7 — Bastion — SSH Hardening & Access

> **All user accounts and SSH keys on the bastion (and all managed VMs) are driven from Vault.** No `useradd` is run manually anymore. Edit the `admin_users` list in `ansible/playbooks/bastion.yaml` and add each user's pubkey under `secret/infra/ssh/admins/<name>` in Vault.

### 7.1 Run the Bastion Playbook

From your workstation (Admin VPN connected, Vault `secret_id` in place):

```bash
cd ansible/
ansible-playbook playbooks/bastion.yaml
```

The `bastion` role performs:

1. Hardens `sshd_config`:
   - `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`
   - `AllowUsers` populated from `admin_users`
   - `MaxAuthTries 3`, `LoginGraceTime 30`, `PerSourceMaxStartups 1`
   - Modern crypto only: `curve25519-sha256`, `aes256-gcm@openssh.com`, `chacha20-poly1305@openssh.com`, `hmac-sha2-512-etm`, `ssh-ed25519`
   - `ClientAliveInterval 300`, `ClientAliveCountMax 2`, `LogLevel VERBOSE`, `X11Forwarding no`
2. Removes the weak ECDSA host key.
3. Creates one local user per entry in `admin_users` (UID stable across reboots).
4. Fetches each user's SSH public key from `secret/infra/ssh/admins/<name>` and writes `~/<user>/.ssh/authorized_keys`.
5. Templates `~/<user>/.ssh/config` with jump targets (`s1-app`, `s1-db`, `s2-mt`).
6. Installs the rsyslog forwarding config (handled in Phase 8).
7. Installs the log-sync cron (`templates/sync-logs.sh.j2`) which rsyncs `/var/log/` to S2-MT every minute.

### 7.2 Validate

```bash
ssh-audit --skip-rate-test 192.168.10.10
```

Target: no `[fail]`, no `[warn]`.

### 7.3 Deploy User Keys to Managed VMs

Run the managed-VM playbook — same Vault-backed mechanism, applied to S1-APP, S1-DB, S2-MT:

```bash
ansible-playbook playbooks/managed_vms.yaml
```

This:
- Creates the same set of users on each managed VM (UID-consistent).
- Pulls each user's pubkey from Vault.
- Configures `sshd_config` to only accept connections from the bastion's source IP (`192.168.10.10`) — enforced at the application level as well as the firewall.

### 7.4 Admin Workstation SSH Config

Each admin adds these entries to their **local** `~/.ssh/config`:

```
Host bastion
    HostName 192.168.10.10
    User <username>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host s1-app
    HostName 10.0.10.1
    User <username>
    ProxyJump bastion
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host s1-db
    HostName 10.0.20.1
    User <username>
    ProxyJump bastion
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host s2-mt
    HostName 192.168.20.1
    User <username>
    ProxyJump bastion
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

**Connection workflow:**

1. Connect to Admin VPN (import `.ovpn`, connect to `5.196.45.7:1194`)
2. `ssh bastion` — connects to the bastion
3. `ssh s1-app` — connects to App Server via bastion (ProxyJump)

### 7.5 Adding / Removing Operators (Day-2 Procedure)

To add a new admin:

1. `vault kv put secret/infra/ssh/admins/<new> public_key="<pubkey>"`
2. Append `<new>` to `admin_users` in `playbooks/bastion.yaml`
3. `vault write auth/userpass/users/<new> password=changeme policies=admin-ops`
4. `ansible-playbook playbooks/bastion.yaml playbooks/managed_vms.yaml`

To remove:

1. Remove `<name>` from `admin_users`, delete the Vault path, delete the userpass account
2. Re-run both playbooks (will remove the user, archive the home directory)

---

## Phase 8 — Observability — JUNKyard

JUNKyard is a Go-based log aggregation system deployed on S2-MT. It collects syslog from all VMs across both sites.

### 8.1 Deploy JUNKyard on S2-MT

SSH into S2-MT (via bastion):

```bash
ssh s2-mt
```

Install Go (if not present):

```bash
sudo apt update && sudo apt install -y golang-go
```

Clone and build:

```bash
git clone https://github.com/mr-andrej/junkyard.git
cd junkyard
go build -o bin/junkyard-server ./cmd/junkyard-server
```

> **DR note:** building from source at recovery time creates a hard dependency on GitHub reachability. For a hardened DR posture, publish a prebuilt binary in the [releases](https://github.com/mr-andrej/junkyard/releases) of the repo and pin the version, or keep a copy in `services/junkyard/` of this repo.

Deploy using the provided script:

```bash
sudo bash scripts/deploy-s2-mt.sh
```

Verify:

```bash
sudo systemctl status junkyard.service
junk health
```

JUNKyard listens on:

- TCP port `5514` — for rsyslog (Linux VMs)
- UDP port `5514` — for pfSense syslog
- HTTP port `8080` — Web UI and REST API

### 8.2 Configure Log Forwarding — Linux VMs

On **each Linux VM** (S1-APP, S1-DB, S2-JS):

```bash
sudo tee /etc/rsyslog.d/99-junkyard.conf > /dev/null <<'EOF'
*.* @@192.168.20.1:5514
EOF

sudo systemctl restart rsyslog
```

Verify:

```bash
sudo netstat -tn | grep 5514
# Should show ESTABLISHED
```

> The double `@@` means TCP. A single `@` would use UDP.

### 8.3 Configure Log Forwarding — pfSense VMs

On **each pfSense** (S1-FW, S2-FW):

Navigate to: **Status → System Logs → Settings → Remote Logging**

| Field | Value |
|---|---|
| Enable Remote Logging | ✅ |
| Remote log servers | `192.168.20.1:5514` |
| Remote Syslog Contents | ✅ Everything (or at minimum: System Events, Firewall Events, General Authentication Events) |

Save.

> pfSense always sends syslog over UDP regardless of port. JUNKyard's UDP listener handles this natively.

### 8.4 Firewall Rules for Log Forwarding

These rules should already be in place from Phase 5. Verify:

**On S1-FW:**

- OPT1: `10.0.10.0/24 → 192.168.20.1/32` TCP 5514 (S1-APP syslog)
- OPT2: `10.0.20.0/24 → 192.168.20.1/32` TCP 5514 (S1-DB syslog)
- OpenVPN: `172.16.0.0/30 → 192.168.20.1/32` TCP/UDP 5514 (S1-FW syslog via tunnel)

**On S2-FW:**

- OPT1: `192.168.10.0/24 → 192.168.20.1/32` TCP 5514 (S2-JS syslog)
- OpenVPN: `172.16.0.0/30 → 192.168.20.1/32` TCP/UDP 5514 (S1-FW tunnel syslog)

### 8.5 Verify Log Collection

Access the Web UI at `http://192.168.20.1:8080` (VPN required).

Check that all 5 sources are reporting:

| Host | Expected |
|---|---|
| `s1-app` | ✅ Logs appearing |
| `s1-db` | ✅ Logs appearing |
| `s1-fw` | ✅ Logs appearing |
| `s2-fw` | ✅ Logs appearing |
| `s2-js` | ✅ Logs appearing |

CLI verification from S2-MT:

```bash
junk logs --host s1-app --limit 5
junk logs --host s2-js --source sshd --limit 10
```

---

## Phase 9 — IPAM — NetBox

NetBox is the authoritative source of truth for the network infrastructure. It runs on S2-MT alongside JUNKyard and Vault, and tracks sites, VLANs, prefixes, IP addresses, and devices across both sites.

The setup uses a **hybrid model**: structural data (sites, VLANs, prefixes, pfSense IPs) is populated declaratively via Ansible, while the 4 managed Linux VMs have their real IPs auto-discovered and synced. NetBox then serves as a dynamic Ansible inventory, closing the loop.

| Component | Value |
|---|---|
| Host | S2-MT (`192.168.20.1`, VLAN 20) |
| NetBox version | 4.2 |
| Database | PostgreSQL (local, for NetBox only — the project DB is MongoDB on S1-DB) |
| Cache / queue | Redis (local) |
| WSGI server | Gunicorn (`127.0.0.1:8001`) |
| Reverse proxy | Nginx (port 80) |
| URL | `http://192.168.20.1` (Admin VPN only) |

> Port 8080 is occupied by JUNKyard. NetBox is served on port 80 via Nginx.

### 9.1 Prerequisites — Ansible Collections

On the Ansible control node (S2-MT):

```bash
ansible-galaxy collection install netbox.netbox ansible.utils

# Use a venv to avoid --break-system-packages
python3 -m venv ~/.venvs/netbox
~/.venvs/netbox/bin/pip install pynetbox netaddr
# Then point ANSIBLE_PYTHON_INTERPRETER at it for the netbox playbooks
```

### 9.2 Deploy NetBox

NetBox is deployed via a custom Ansible role (`roles/netbox`). **All credentials are pulled from Vault at runtime** — no defaults are hardcoded anymore.

```bash
ansible-playbook playbooks/netbox.yaml --ask-become-pass
```

The role performs the following in order:

1. Logs into Vault using the AppRole stored at `~/.ansible/vault-secret-id`
2. Installs dependencies (PostgreSQL, Redis, Python venv build deps, Nginx)
3. Creates the PostgreSQL database and user, **password from `secret/netbox/db.password`**
4. Creates the `netbox` system user
5. Clones the NetBox repository at the pinned version
6. Deploys `configuration.py` — **secret key from `secret/netbox/django.secret_key`**, DB creds from Vault, allowed hosts
7. Runs the official `upgrade.sh` (venv + migrations + static files)
8. Creates the superuser — **password from `secret/netbox/superuser.password`**
9. Deploys Gunicorn + two systemd services (`netbox`, `netbox-rq`)
10. Deploys the Nginx reverse proxy config

Verify all three services are running:

```bash
sudo systemctl status netbox       # Gunicorn / web
sudo systemctl status netbox-rq    # background task worker
sudo systemctl status nginx        # reverse proxy
```

> **Disk:** S2-MT has a small 7.6 GB root volume. Monitor usage with `df -h /`.

If the superuser login fails after deploy (masked by `|| true` in the playbook), recreate manually using the password from Vault:

```bash
VAULT_PW=$(vault kv get -field=password secret/netbox/superuser)
sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py createsuperuser
# Use the password above when prompted
```

### 9.3 Firewall Rule for NetBox Access

NetBox must not be reachable from the WAN. Add this rule on S2-FW if not already present:

**Firewall → Rules → OpenVPN:**

| Source | Destination | Port | Description |
|---|---|---|---|
| `192.168.100.0/24` | `192.168.20.0/24` | 80 | HTTP — NetBox access from Admin VPN |

Validate:

```bash
# From Admin VPN (connected) — should return HTTP 200
curl -I http://192.168.20.1

# From WAN — blocked (no rule, dropped by default deny)
```

### 9.4 Generate the NetBox API Token & Store in Vault

After first login to the NetBox UI:

1. Top-right user menu → **API Tokens → Add Token**
2. Copy the token
3. Store in Vault for the populate/sync playbooks:
   ```bash
   vault kv put secret/netbox/api token='<paste-token>'
   ```

### 9.5 Populate Declarative Data

Structural data that Ansible cannot discover (pfSense firewalls, WAN IPs, tunnel endpoints) is populated declaratively:

```bash
ansible-playbook playbooks/netbox_populate.yaml
```

This creates:

| Category | Items |
|---|---|
| Sites | Site 1 - Internal, Site 2 - Cloud |
| VLANs | Servers (10), Database (20) @ Site 1 · DMZ (10), Monitoring (20) @ Site 2 |
| Prefixes | All subnets (LAN, VLANs, Admin VPN, tunnel) |
| Device roles | Firewall, Server |
| Manufacturer / type | Generic / Virtual Machine |
| Devices | S1-FW, S1-APP, S1-DB, S2-FW, S2-JS, S2-MT |
| Static IPs | pfSense gateways, public WAN IPs, tunnel endpoints |

This playbook is **idempotent** — safe to re-run. It deliberately does **not** create interfaces or IPs for the 4 managed Linux VMs; those are handled by the sync playbook below.

### 9.6 Sync Real Infrastructure → NetBox

The 4 managed Linux VMs (S1-APP, S1-DB, S2-JS, S2-MT) have their real IPs discovered and pushed to NetBox:

```bash
ansible-playbook playbooks/netbox_sync.yaml
```

How it works:

1. Ansible connects to each VM (via bastion ProxyJump) and gathers facts
2. Extracts the primary interface and real IP from `ansible_facts['default_ipv4']`
3. For each VM, ensures in NetBox: the interface exists (e.g. `enp6s18.10`), the IP is assigned to it, and the IP is set as the device's primary IPv4
4. Synced IPs are tagged with the description "Auto-synced from real infrastructure"

> **Why only 4 VMs?** Ansible can only discover IPs on hosts it can SSH into. pfSense firewalls (BSD), WAN IPs, and tunnel endpoints are not Ansible-managed, so they stay declarative.

Validate the sync captures real changes:

```bash
# 1. Add a temporary IP on a test VM
ssh s1-app
sudo ip addr add 10.0.10.99/24 dev enp6s18.10

# 2. Re-run the sync
ansible-playbook playbooks/netbox_sync.yaml

# 3. Check NetBox — the new IP should appear (proves real discovery)
```

### 9.7 NetBox as Dynamic Ansible Inventory

Once populated, NetBox feeds Ansible's inventory directly, so the IPAM becomes the operational source of truth.

Inventory file (`inventory/netbox_inventory.yaml`):

```yaml
plugin: netbox.netbox.nb_inventory
api_endpoint: http://192.168.20.1
token: !vault |    # fetched from secret/netbox/api at runtime
validate_certs: false

group_by:
  - sites
  - device_roles

compose:
  ansible_host: primary_ip4.address | default('') | ansible.utils.ipaddr('address')
```

Verify:

```bash
ansible-inventory -i inventory/netbox_inventory.yaml --graph
```

Expected output groups devices by site and role:

```
@all:
  |--@sites_site1:
  |  |--S1-APP
  |  |--S1-DB
  |  |--S1-FW
  |--@sites_site2:
  |  |--S2-FW
  |  |--S2-JS
  |  |--S2-MT
  |--@device_roles_server: ...
  |--@device_roles_firewall: ...
```

If a device is added in NetBox, it appears automatically in the Ansible inventory — no static `hosts.yaml` edit needed.

### 9.8 NetBox Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Duplicate IP address found in global table` | IP exists on a different (fictive) interface | Remove fictive `eth0` interfaces; let sync own VM IPs |
| `assigned_object.interface` unsupported | Wrong key in `netbox_ip_address` | Use `name:` (not `interface:`) inside `assigned_object` |
| `ansible_host` is a dict, SSH fails | `primary_ip4` returns full object | Use `primary_ip4.address \| ansible.utils.ipaddr('address')` |
| IP column empty in Devices table | Primary IP not set on device | Add the "set primary IP" task in sync playbook |
| Prefix becomes `/32` | Netmask conversion error | Use `ansible_facts['default_ipv4']['prefix']` directly |
| Superuser login fails after deploy | `createsuperuser` masked by `\|\| true` | Recreate manually with password from `secret/netbox/superuser` |

---

## Phase 10 — Application Deployment

> The application stack (web service on S1-APP, MongoDB on S1-DB) is provisioned via Ansible roles. Application code itself is deployed via a separate runbook outside this document.

### 10.1 S1-DB — MongoDB

Run the database playbook:

```bash
ansible-playbook playbooks/db.yaml
```

The `mongodb` role:

1. Installs MongoDB from the official repository
2. Configures `bindIp` to listen on `10.0.20.1`
3. Enables authentication (initial root password from `secret/db/mongo.root_password` in Vault)
4. Creates the application user and database
5. Enables the `mongod` systemd service

Verify:

```bash
ssh s1-db
sudo systemctl status mongod
mongosh --host 10.0.20.1 -u <app_user> -p
```

### 10.2 S1-APP — Application Server

Firewall posture (already in place from Phase 5):

- Outbound TCP **27017** to `10.0.20.0/24` (MongoDB on S1-DB)
- Outbound HTTP/HTTPS for system updates
- Outbound TCP 5514 to `192.168.20.1` (syslog to JUNKyard)
- Outbound TCP 8200 to `192.168.20.1` (Vault API)
- Inbound SSH from bastion (`192.168.10.10`) only

Deploy the application stack according to the application-specific runbook. The app should connect to the database at `db.site1.internal` or `10.0.20.1` on port `27017`, using the credentials stored in `secret/db/mongo.app_user`.

---

## Phase 11 — Full Validation

Run through these checks to confirm the entire infrastructure is operational. For automated validation, see the **non-regression test playbook** referenced at the end of this document.

### 11.1 VPN & Tunnel

- [ ] Admin VPN: connect with `.ovpn` file, receive IP in `192.168.100.0/24`
- [ ] Site-to-site tunnel: **Status → OpenVPN** shows "Connected" on both S1-FW and S2-FW
- [ ] Tunnel survives pfSense restart on both sides (auto-reconnect)
- [ ] VPN encryption: AES-256-GCM / SHA256 confirmed in **Status → OpenVPN**

### 11.2 Firewall & Segmentation

- [ ] WAN: only UDP 1194 and 1195 accepted on S2-FW; only UDP 1195 accepted on S1-FW
- [ ] Kill switch rules present on both WAN interfaces (disabled by default)
- [ ] S1-APP can reach S1-DB on TCP **27017**
- [ ] S1-DB **cannot** initiate connections to S1-APP
- [ ] S2-MT **cannot** reach S2-JS (inter-VLAN blocked)
- [ ] No direct WAN access from any VM

### 11.3 Bastion & Access Control

- [ ] Admin VPN → bastion SSH: works
- [ ] Admin VPN → S1-APP direct SSH: **blocked**
- [ ] Admin VPN → S1-DB direct SSH: **blocked**
- [ ] Admin VPN → S2-MT direct SSH: **blocked**
- [ ] Bastion → S1-APP via ProxyJump: works
- [ ] Bastion → S1-DB via ProxyJump: works
- [ ] Bastion → S2-MT via ProxyJump: works
- [ ] Idle sessions disconnect after 10 minutes
- [ ] `ssh-audit` shows no `[fail]` or `[warn]`

### 11.4 DNS

- [ ] From S1-APP: `nslookup app.site1.internal` → `10.0.10.1`
- [ ] From S1-APP: `nslookup bastion.site2.internal` → `192.168.10.10` (cross-site)
- [ ] From S2-JS: `nslookup app.site1.internal` → `10.0.10.1` (cross-site)
- [ ] From S2-JS: `nslookup ops.site2.internal` → `192.168.20.1`
- [ ] External DNS (e.g. `google.com`) resolves from all VMs

### 11.5 Vault

- [ ] `vault status` → Sealed: false, Initialized: true
- [ ] AppRole login succeeds: `vault write auth/approle/login role_id=... secret_id=...`
- [ ] `vault kv list secret/` returns the expected paths (`infra/`, `netbox/`, `vpn/`, `firewall/`)
- [ ] Daily snapshot present in `/home/administrator/junkyard/vault-snapshots/`
- [ ] Vault unreachable from WAN (only from VLAN 10 bastion + Admin VPN)

### 11.6 Observability

- [ ] JUNKyard service running on S2-MT: `sudo systemctl status junkyard.service`
- [ ] Web UI accessible at `http://192.168.20.1:8080` via VPN
- [ ] Logs arriving from all 5 sources (s1-app, s1-db, s1-fw, s2-fw, s2-js)
- [ ] CLI works: `junk logs --host s2-js --source sshd --limit 5`

### 11.7 IPAM — NetBox

- [ ] NetBox services running: `systemctl status netbox netbox-rq nginx`
- [ ] Web UI accessible at `http://192.168.20.1` via Admin VPN (HTTP 200)
- [ ] Web UI **not** accessible from WAN or non-VPN networks
- [ ] Declarative data populated: 2 sites, 4 VLANs, all prefixes, 6 devices visible
- [ ] Sync playbook completes: `ansible-playbook playbooks/netbox_sync.yaml`
- [ ] All 4 Linux VMs show correct primary IPs in NetBox Devices table
- [ ] Dynamic inventory works: `ansible-inventory -i inventory/netbox_inventory.yaml --graph`

### 11.8 Application Layer

- [ ] S1-APP application is running and healthy
- [ ] S1-APP can connect to S1-DB MongoDB on port **27017**
- [ ] Application logs appear in JUNKyard

> **Tip:** all of section 11 should also be executable end-to-end via `ansible-playbook playbooks/non_regression.yaml` once that playbook lands. See the project's non-regression test design doc.

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---|---|---|
| VPN tunnel shows "Waiting for response from peer" | Firewall blocking UDP 1195, or cert mismatch | Verify WAN rules on both sides; check cert CA matches |
| VM shows `NO-CARRIER` on interface | Proxmox bridge issue after config change | Full VM reboot via Proxmox UI |
| `NXDOMAIN` for `*.site1.internal` from Site 2 | Missing Domain Override or Forwarding Mode enabled | Add override on S2-FW; disable DNS Query Forwarding on S1-FW |
| `NXDOMAIN` for `*.site2.internal` from Site 1 | Missing Domain Override or Forwarding Mode enabled | Add override on S1-FW; disable DNS Query Forwarding on S2-FW |
| S2-FW resolver can't reach S1-FW DNS | Missing firewall rule for `172.16.0.0/30 → This Firewall:53` | Add rule on S1-FW OpenVPN interface |
| rsyslog not connecting to JUNKyard | Firewall rule missing or wrong port | Verify TCP 5514 rule exists; check `netstat -tn \| grep 5514` |
| pfSense syslog not appearing in JUNKyard | JUNKyard not listening on UDP | Verify JUNKyard has UDP listener on 5514 (custom build required) |
| SSH to bastion times out | Not connected to Admin VPN, or firewall rule missing | Connect to VPN first; verify OPT1 rules on S2-FW |
| Direct SSH to S1-APP works from Admin VPN | Block rules not ordered correctly | Move SSH block rules above the inter-site allow rule |
| Can ping cross-site but SSH fails | OpenVPN firewall rules missing or too restrictive | Check OpenVPN interface rules for SSH from bastion source IP |
| Any playbook fails with `x509: certificate signed by unknown authority` | Missing or wrong Vault CA cert | Refresh `~/.ansible/vault-ca.crt` from `/etc/vault.d/tls/ca.crt` on S2-MT |
| Any playbook fails with `approle: failed to validate SecretID` | `secret_id` expired or revoked | Request a new one: `vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id` |
| Vault sealed after S2-MT reboot | Vault always restarts in a sealed state | Run unseal procedure (3 Shamir keys) — see Phase 6.3 |
| Bastion user missing after `bastion.yaml` run | Pubkey not in Vault under `secret/infra/ssh/admins/<name>` | Add to Vault, re-run playbook |
| MongoDB connection refused from S1-APP | `bindIp` still `127.0.0.1`, or firewall rule missing | Edit `/etc/mongod.conf` (`bindIp: 10.0.20.1`); verify OPT2 rule allows `10.0.10.0/24 → 10.0.20.0/24:27017` |

---

## Architecture Notes

- **Max 3 VMs per site.** This is a hard constraint. Role assignment cannot be changed without re-architecture.
- **Proxmox bridges are NOT VLAN-aware.** VLAN segmentation is enforced by pfSense. Guest VMs must create VLAN sub-interfaces in Netplan to send/receive tagged frames.
- **Site 2 is the VPN hub.** It must be rebuilt first. Site 1 cannot function without the tunnel.
- **Vault is the single source of truth for secrets.** No secret is committed to the repo; no playbook works without Vault healthy. Plan accordingly when sequencing DR steps.
- **All SSH must pass through the bastion.** Direct SSH from Admin VPN to any VM (except the bastion itself) is blocked at the firewall.
- **DNS Forwarding Mode must be disabled.** If enabled on either pfSense, Domain Overrides stop working and inter-site DNS fails.
- **pfSense sends syslog via UDP** even when a custom port is specified. JUNKyard handles this with a custom UDP listener.
- **Project database is MongoDB** (on S1-DB, port 27017). NetBox uses its own local PostgreSQL — do not confuse the two.
- The architecture supports horizontal scaling: new sites reuse `/24` per VLAN, `/30` per tunnel, same hub-and-spoke VPN model. See [`docs/architecture/scalability.md`](scalability.md).

---

**Team PAR_14** | Last updated: June 2026

*T-NSA-810: Deployment and Securing of a Hybrid Infrastructure with Proxmox*
