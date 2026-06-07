# firewall role

Configures a **pfSense** firewall declaratively with the
[`pfsensible.core`](https://galaxy.ansible.com/pfsensible/core) collection.
The modules run *on* the firewall over SSH (as `admin`, which is root — no
`become`), so nothing is installed on the pfSense VM itself.

Implements the Site 1 firewall runbook: VLAN segmentation, OPTx interfaces,
least-privilege rules, DHCP per VLAN, the DNS Resolver (host + domain
overrides), and — opt-in — the OpenVPN site-to-site client.

## Requirements

```bash
ansible-galaxy collection install -r requirements.yml
```

On pfSense: **System > Advanced > Admin Access > Secure Shell** → enable SSH.

## Task files (each is tagged)

| File | Tag | pfSense area |
|------|-----|--------------|
| `setup.yml` | `setup` | hostname / domain |
| `vlans.yml` | `vlans` | Interfaces > Assignments > VLANs |
| `interfaces.yml` | `interfaces` | Interfaces > Assignments (OPTx) |
| `aliases.yml` | `aliases` | Firewall > Aliases |
| `dhcp.yml` | `dhcp` | Services > DHCP Server |
| `dns.yml` | `dns` | Services > DNS Resolver |
| `rules.yml` | `rules` | Firewall > Rules |
| `openvpn.yml` | `openvpn` | VPN > OpenVPN > Clients (opt-in) |

## Variables

All data lives in `inventory/host_vars/s1_fw.yaml`. Key conventions:

- **`fw_lan_parent`** — the trunk NIC that carries the LAN VLANs. Confirm which
  `vtnetX` is your LAN port; WAN is the other one.
- **`fw_rules`** is one ordered list; each rule names its own `interface`. The
  role places each rule `after` the previous one on the same interface, so list
  order == top-to-bottom order in the UI. This is what keeps the OpenVPN SSH
  block rules ahead of the inter-sites allow.
- Rule `destination: "(self)"` means **This Firewall**. A trailing `block any`
  per interface enforces least privilege.
- **OpenVPN client** is gated behind `fw_manage_openvpn_client` (default
  `false`) because editing the existing S2S client needs its CA/cert references.

## Run

```bash
ansible-playbook playbooks/s1_fw.yaml                # everything
ansible-playbook playbooks/s1_fw.yaml --check        # dry run (diff vs live)
ansible-playbook playbooks/s1_fw.yaml --tags rules   # one section
ansible-playbook playbooks/s1_fw.yaml --skip-tags openvpn
```
