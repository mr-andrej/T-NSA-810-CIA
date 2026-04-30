> Goal: Configure Site 1 (S1-FW) as the OpenVPN client for the site-to-site tunnel with Site 2.  
> The tunnel runs on port **1195**, connecting to Site 2 WAN IP `5.196.45.7`.

---

## Network Reference

|                 | Site 1         | Site 2            |
| --------------- | -------------- | ----------------- |
| SERVERS VLAN    | `10.0.10.0/24` | —                 |
| DATABASE VLAN   | `10.0.20.0/24` | —                 |
| DMZ VLAN        | —              | `192.168.10.0/24` |
| MONITORING VLAN | —              | `192.168.20.0/24` |
| Tunnel network  | `172.16.0.2`   | `172.16.0.1`      |
| WAN (public IP) | —              | `5.196.45.7`      |

---

## Prerequisites

The following files must be provided by the Site 2 administrator before starting:

- `site2-vpn-ca.crt` — Certificate Authority
- `s2s-site1-client.crt` — Client certificate
- `s2s-site1-client.key` — Client private key
- TLS static key (copied from the `.ovpn` file between `-----BEGIN OpenVPN Static key V1-----` and `-----END OpenVPN Static key V1-----`)

---

## 1. Import the Certificate Authority

**System → Cert. Manager → CAs → Add**

| Field            | Value                                        |
| ---------------- | -------------------------------------------- |
| Method           | **Import an existing Certificate Authority** |
| Descriptive name | `site2-vpn-ca`                               |
| Certificate data | paste content of `site2-vpn-ca.crt`          |

→ **Save**

---

## 2. Import the Client Certificate

**System → Cert. Manager → Certificates → Add**

| Field            | Value                                   |
| ---------------- | --------------------------------------- |
| Method           | **Import an existing Certificate**      |
| Descriptive name | `s2s-site1-client`                      |
| Certificate data | paste content of `s2s-site1-client.crt` |
| Private key data | paste content of `s2s-site1-client.key` |

→ **Save**

---

## 3. Configure the OpenVPN Client

**VPN → OpenVPN → Clients → Add**

| Field                      | Value                                                  |
| -------------------------- | ------------------------------------------------------ |
| Server mode                | **Peer to Peer (SSL/TLS)**                             |
| Protocol                   | UDP on IPv4 only                                       |
| Interface                  | WAN                                                    |
| Server host                | `5.196.45.7`                                           |
| Server port                | `1195`                                                 |
| Description                | `S2S Site1-Site2`                                      |
| TLS Configuration          | ✅ Use a TLS Key — ❌ uncheck "Automatically generate" |
| TLS Key                    | paste the static key from the `.ovpn` file             |
| Peer Certificate Authority | `site2-vpn-ca`                                         |
| Client certificate         | `s2s-site1-client`                                     |
| Data Encryption Algorithms | AES-256-GCM                                            |
| Auth digest algorithm      | SHA256                                                 |
| IPv4 Tunnel Network        | `172.16.0.0/30`                                        |
| IPv4 Remote networks       | `192.168.10.0/24, 192.168.20.0/24`                     |

→ **Save**

---

## 4. Firewall Rules

### Allow tunnel traffic on OpenVPN interface

**Firewall → Rules → OpenVPN → Add**

| Field       | Value                 |
| ----------- | --------------------- |
| Action      | Pass                  |
| Protocol    | any                   |
| Source      | any                   |
| Destination | any                   |
| Description | `Allow Site2 traffic` |

→ **Save** → **Apply Changes**

---

## 5. Verify the Tunnel

**Status → OpenVPN**

The client `S2S Site1-Site2` should show **Connected** with a valid Virtual Address.

If status shows **"Waiting for response from peer"**, restart OpenVPN on both sides:

- Site 1: **Status → OpenVPN** → click restart icon
- Site 2: same

---

## Acceptance Criteria

- [ ] Status shows **Connected** on both Site 1 and Site 2
- [ ] Site 1 can ping Site 2 DMZ gateway: `ping 192.168.10.1`
- [ ] Site 1 can ping Site 2 Monitoring gateway: `ping 192.168.20.1`
- [ ] Tunnel reconnects automatically after pfSense restart
- [ ] No authentication errors in **Status → OpenVPN** logs
