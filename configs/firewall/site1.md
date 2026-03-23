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

1. DHCP Server for VLAN 10 (Servers)
   Go to `Services → DHCP Server` and click the `LAN` tab.
   Set the following:

Generale Settings -> Enable: ✓ checked Enable DHCP server on LAN interface
Primary Address Pool -> Address Pool Range:
Range from: 10.0.10.10
Range to: 10.0.10.50

Server Options -> DNS Servers
DNS Server 1: 10.0.10.254 (pfSense itself)

Other DHCP Options -> Gateway
Gateway: 10.0.10.254

Then scroll down and click Save -> Apply.

2. DHCP Server for VLAN 20 (Database)
   Still in `Services → DHCP Server`, click the `OPT1` tab.
   Set the following:

Generale Settings -> Enable: ✓ checked Enable DHCP server on OPT1 interface.
Primary Address Pool -> Address Pool Range:
Range from: 10.0.20.10
Range to: 10.0.20.50

Server Options -> DNS Servers
DNS Server 1: 10.0.20.254

Other DHCP Options -> Gateway
Gateway: 10.0.20.254

Then scroll down and click Save -> Apply.

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

## Comme Trouble Shooting

### Timeout error to access the pfsense login page

Description:
Cannot access pf GUI through http://5.196.51.50/, get "took too long to respond" error in browser.

Reason (given by AI of course I know nothing):
pfSense blocks WebGUI access on the WAN interface by default, and since I have restarted/modified things, that rule may have been reset. PfSense has a built-in anti-lockout rule that normally protects you on the LAN side. But your setup only has a WAN interface (vnet0), so you were previously accessing the WebGUI directly over WAN — which pfSense considers a security risk and may block after changes.

Solution (given by AI of course I know nothing):
In the pfSense menu, type 8 to open a shell, then run this command `pfSsh.php playback enableallowallwan` to re-enables WebGUI access on the WAN interface.
And also make sure in WebGUI, go to System → Advanced → Admin Access that "WebGUI redirect" and "Anti-lockout rule" are enabled. This prevents this from happening again after restarts.

### WAN and LAN on seperate physical interfaces

This is something Claude asked me to flag a constrain but I do I understand what Claude actually meant? Of course no.
Notice that vnet0 (your WAN) and vtnet0 (your VLAN parent) look like they might be the same physical interface with different naming. In a real segmented setup you'd want WAN and LAN on separate physical interfaces.
