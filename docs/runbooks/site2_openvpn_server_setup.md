# pfSense OpenVPN Setup — Remote Access (SSL/TLS + User Auth)

> Goal: Allow access to pfSense web UI only through VPN.

---

## 1. Create the Certificate Authority (CA)

**System → Cert. Manager → CAs → Add**

| Field            | Value                                    |
| ---------------- | ---------------------------------------- |
| Method           | Create an internal Certificate Authority |
| Descriptive name | `site2-vpn-ca`                           |
| Key type         | RSA, 2048 bit                            |
| Digest Algorithm | SHA256                                   |
| Lifetime         | 3650                                     |
| Common Name      | `site2-vpn-ca`                           |

→ **Save**

---

## 2. Create the Server Certificate

**System → Cert. Manager → Certificates → Add**

| Field                 | Value                                    |
| --------------------- | ---------------------------------------- |
| Method                | **Create an internal Certificate**       |
| Descriptive name      | `site2-vpn-server`                       |
| Certificate Authority | `site2-vpn-ca`                           |
| Key type              | RSA, 2048 bit                            |
| Digest Algorithm      | SHA256                                   |
| Lifetime              | **398** (max accepted by most platforms) |
| Common Name           | `site2-vpn-server`                       |
| Certificate Type      | **Server Certificate**                   |

→ **Save**

---

## 3. Create the OpenVPN Server

**VPN → OpenVPN → Servers → Add**

| Field                      | Value                                       |
| -------------------------- | ------------------------------------------- |
| Server mode                | Remote Access (SSL/TLS + User Auth)         |
| Backend                    | Local Database                              |
| Device mode                | tun                                         |
| Protocol                   | UDP on IPv4 only                            |
| Interface                  | WAN                                         |
| Local port                 | 1194                                        |
| TLS Configuration          | ✅ Use a TLS Key (auto-generate)            |
| Peer Certificate Authority | `site2-vpn-ca`                              |
| Server certificate         | `site2-vpn-server`                          |
| DH Parameter Length        | 2048 bit                                    |
| Data Encryption Algorithms | AES-256-GCM, AES-128-GCM, CHACHA20-POLY1305 |
| Auth digest algorithm      | SHA256                                      |
| IPv4 Tunnel Network        | `192.168.100.0/24`                          |
| IPv4 Local networks        | `192.168.10.0/24, 192.168.20.0/24`          |
| Topology                   | Subnet                                      |

→ **Save**

---

## 4. Create a VPN User

**System → User Manager → Add**

| Field       | Value                                 |
| ----------- | ------------------------------------- |
| Username    | `lucas-vpn`                           |
| Password    | _(strong password)_                   |
| Certificate | ✅ Click to create a user certificate |
| → CA        | `site2-vpn-ca`                        |
| → Key type  | RSA, 2048                             |
| → Lifetime  | 398                                   |

→ **Save**

---

## 5. Open WAN Firewall Rule (port 1194)

**Firewall → Rules → WAN → Add**

| Field            | Value            |
| ---------------- | ---------------- |
| Action           | Pass             |
| Protocol         | UDP              |
| Source           | any              |
| Destination      | WAN address      |
| Destination port | 1194             |
| Description      | `OpenVPN Access` |

→ **Save** → **Apply Changes**

---

## 6. Allow Traffic on OpenVPN Interface

**Firewall → Rules → OpenVPN → Add**

| Field       | Value               |
| ----------- | ------------------- |
| Action      | Pass                |
| Protocol    | any                 |
| Source      | any                 |
| Destination | any                 |
| Description | `Allow VPN traffic` |

→ **Save** → **Apply Changes**

---

## 7. Export Client Configuration

**System → Package Manager → Available Packages**

- Install `openvpn-client-export`

**VPN → OpenVPN → Client Export**

- Find user `lucas-vpn` → Export **Most Clients** → download `.ovpn`

---

## 8. Connect & Test

1. Import `.ovpn` into OpenVPN Connect
2. Connect with `lucas-vpn` credentials
3. Verify assigned IP:

```bash
ifconfig | grep -A 2 utun
# Expected: inet 192.168.100.2 --> 192.168.100.1
```

4. Test connectivity:

```bash
ping -c 3 192.168.100.1
```

5. Access pfSense web UI: `https://192.168.100.1`

---

## 9. (Optional) Restrict Web UI to VPN only

Once VPN access is confirmed working, block the web UI on all other interfaces:

**Firewall → Rules → [each VLAN interface] → Add**

| Field            | Value                     |
| ---------------- | ------------------------- |
| Action           | Block                     |
| Protocol         | TCP                       |
| Destination      | This Firewall             |
| Destination port | 443                       |
| Description      | `Block WebUI outside VPN` |

> ⚠️ Always verify VPN access works **before** applying this rule.  
> Emergency fallback: use Proxmox console to remove the rule if locked out.
