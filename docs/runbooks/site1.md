# Base Proxmox Network Configuration (S1-APP) Ticket # 54

## What this ticket is actually about

S1-APP is a plain Ubuntu VM. Unlike pfSense which has a GUI, here you're just telling Ubuntu "your IP address is this, your gateway is pfSense, and your DNS is pfSense." That's it. No VLAN configuration needed on this side — pfSense already handles the VLAN tagging, the VM just needs to know where it lives.

---

## What you need before starting

log into Proxmox, find the S1-APP VM, and open its console.

---

## Step by step

**Step 1 — Check the current network state**

Once you're in the terminal, run:

bash

```bash
ip addr show
```

This lists all network interfaces and their current IPs. You're looking for the interface name — on Proxmox VMs it's usually `ens18` or `eth0`. Note it down.

After running `ip addr show`, I got:
1: lo: <LOOPBACK, UP, LOWER_UP> mtu 65536 qdisc noqueue state unknown group default qlen 1000
link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
inet 127.0.0.1/8 scope host lo
valid_lft forever preferred-lft forever
inet6 ::1/128 scope host noprefixroute
valid_lft forever preferred_lft forever
2: enp6s18: <BROADCAST, MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000 link/ether bc:24:11:c9:99:52 brd ff:ff:ff:ff:ff:ff

**Step 2 — Edit the network configuration file**

Ubuntu 20.04+ uses Netplan for network configuration. The config file is here:

bash

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Replace its contents with this :

yaml

```yaml
network:
  version: 2
  ethernets:
    enp6s18:
      addresses:
        - 10.0.10.1/24
      gateway4: 10.0.10.254
      nameservers:
        addresses:
          - 10.0.10.254
        search:
          - site1.internal
```

The key values here:

- `10.0.10.1` — static IP for the App Server (matches the architecture diagram)
- `10.0.10.254` — gateway pointing to pfSense on VLAN 10
- `10.0.10.254` — also used as DNS, so pfSense resolves names for this VM
- `site1.internal` — the local domain so you can use `db.site1.internal` instead of IPs

**Step 3 — Apply the configuration**

bash

```bash
sudo netplan apply
```

**Step 4 — Verify it worked**

bash

```bash
ip addr show enp6s18
```

You should see `10.0.10.1/24` assigned.

Then test the gateway is reachable:

bash

```bash
ping 10.0.10.254
```

And test DNS resolution:

bash

```bash
ping firewall.site1.internal
```

## Known-good matrix

Use this matrix to verify that each interface, VLAN, and IP assignment is aligned before deeper troubleshooting.

| Node                       | Proxmox Bridge             | VLAN Tag (Proxmox NIC)          | Interface in Guest             | IP/CIDR                       | Gateway         | DNS              | Expected Result                                                       |
| -------------------------- | -------------------------- | ------------------------------- | ------------------------------ | ----------------------------- | --------------- | ---------------- | --------------------------------------------------------------------- |
| pfSense WAN                | WAN bridge (not vmbr137)   | none                            | WAN NIC                        | Upstream/public addressing    | Upstream router | Upstream DNS     | WAN reachability only                                                 |
| pfSense LAN parent (trunk) | vmbr137                    | none                            | Parent NIC (example: vtnet1)   | No VLAN host subnet on parent | n/a             | n/a              | Carries VLAN 10 and VLAN 20 traffic                                   |
| pfSense VLAN 10            | Logical VLAN on LAN parent | 10 (set in pfSense VLAN config) | Assigned and enabled interface | 10.0.10.254/24                | n/a             | Resolver enabled | Replies to ARP and ping from S1-APP                                   |
| pfSense VLAN 20            | Logical VLAN on LAN parent | 20 (set in pfSense VLAN config) | Assigned and enabled interface | 10.0.20.254/24                | n/a             | Resolver enabled | Replies to ARP and ping from S1-DB                                    |
| S1-APP VM                  | vmbr137                    | 10                              | enp6s18                        | 10.0.10.1/24                  | 10.0.10.254     | 10.0.10.254      | Ping to 10.0.10.254 succeeds and DNS resolves firewall.site1.internal |
| S1-DB VM                   | vmbr137                    | 20                              | VM NIC (example: enp6s18)      | 10.0.20.1/24                  | 10.0.20.254     | 10.0.20.254      | Ping to 10.0.20.254 succeeds and DNS resolves db.site1.internal       |

Validation commands (single pass):

```bash
# S1-APP
ip addr show enp6s18
ip route
ip neigh show
ping -c 4 10.0.10.254
ping -c 4 firewall.site1.internal

# S1-DB
ip addr show
ip route
ip neigh show
ping -c 4 10.0.20.254
ping -c 4 db.site1.internal
```

Quick failure map:

- If neighbor entry stays INCOMPLETE for 10.0.10.254, check Proxmox VLAN tag and bridge alignment first.
- If ARP resolves but ping fails, check pfSense firewall rules.
- If gateway ping works but DNS fails, check DNS Resolver and host overrides on pfSense.

---

## Deliverable for the ticket

Your documentation should be a simple markdown note containing:

- Interface name found on the VM
- The Netplan config you applied
- Confirmation that `ip addr`, gateway ping, and DNS ping all succeeded
- A one-line rationale: "S1-APP is statically assigned to 10.0.10.1/24 on VLAN 10, with pfSense as both gateway and DNS resolver, ensuring all traffic is routed and filtered centrally."

---

Once S1-APP is done, S1-DB (#38) is identical — just different IP (`10.0.20.1/24`) and gateway (`10.0.20.254`). You can knock both out in one sitting. Want to start?
