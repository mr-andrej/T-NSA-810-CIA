# Ticket 57: Foundational Network Configuration (S1-FW)

## What's this ticket is about

1. VLAN configuration
   Inside pfSense's web UI, create virtual interfaces tagged with VLAN IDs (10 for servers, 20 for database) on top of the physical network card. This is foundational, everything else depends on this being done first.

2. DHCP configuration
   Mapping static IPs

3. Firewall rules
   VLAN 10 <-> VLAN 20

4. DNS forwarding
   Configuring pfSense so that machines on Site 1 can resolve names like `site2.bastion.internal` by forwarding those queries through the VPN tunnel to Site 2's pfSense

5. VPN
   Configuring Site 1's pfSense to connect to Site 2's OpenVPN server as a client

## Steps

### VLAN configuration

1. Create the VLANs

- Log in pfSense GUI
- Go to `Interfaces -> Assignments -> VLANs -> Add`
  For VLAN 10:
  Parent interface: your LAN physical interface (e.g. vtnet1)
  VLAN tag: 10
  Description: SERVERS

  For VLAN 20:
  Parent interface: same LAN physical interface
  VLAN tag: 20
  Description: DATABASE

2. Assign the VLANs

- Go to `Interfaces → Assignments`
- add each VLAN as a new interface, then go into each one and set:
  Enable the interface ✓
  IPv4: Static
  IP address: 10.0.10.254/24 for VLAN 10, 10.0.20.254/24 for VLAN 20

### DHCP configuration

- Go to `Services -> DHCP Server` to enable DHCP per VLAN
- Select each VLAN interface, enable it, and set the range

### Firewall rules

- Go to `Firewall -> Rules`
- Select the VLAN 10 interface tab
- Add
  Action: Pass
  Source: 10.0.10.0/24
  Destination: 10.0.20.1 port 5432
  Description: "App to DB PostgreSQL"

  Action: Block
  Source: 10.0.10.0/24
  Destination: 10.0.20.0/24
  Description: "Deny all other VLAN10 to VLAN20"
