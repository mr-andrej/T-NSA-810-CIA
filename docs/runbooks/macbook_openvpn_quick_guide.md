# MacBook OpenVPN Quick Guide (Beginner-Friendly)

> Audience: team member with limited networking background
> Goal: connect from macOS to project VPN and access pfSense/allowed project resources

---

## 1) Do I need to wait for my teammate?

Short answer: **yes, partially**.

You can install OpenVPN Connect and be ready now, but you cannot fully connect until your teammate gives you your personal VPN material.

Why:

- The server is configured for **SSL/TLS + User Auth**.
- That usually means each person needs their own VPN identity (user + certificate/profile).
- Your teammate already said they would generate certificates per person.

So your work now is "prep + request", then connect immediately when they send your files.

---

## 2) What to ask your teammate for (copy/paste message)

Use this exact message in your team chat:

```text
Can you send me my personal OpenVPN client profile for Site 2 (exported .ovpn from pfSense client export), plus the VPN username/password if needed?

Also please confirm:
1) Which subnets I should be allowed to access via VPN
2) Whether I should reach only pfSense WebUI (192.168.100.1) or also Site 2 VMs and Site 1 VMs
3) Which test IPs/hosts you want me to verify after connection
```

**French version (pour demander à ton coéquipier) :**

```text
Peux-tu me envoyer mon profil OpenVPN client personnel pour Site 2 (exporté depuis pfSense client export), plus le nom d'utilisateur/mot de passe VPN si nécessaire ?

Aussi, confirme-moi :
1) Quels subnets je devrais pouvoir accéder via VPN
2) Si je dois accéder uniquement à l'interface Web de pfSense (192.168.100.1) ou aussi aux VMs de Site 2 et Site 1
3) Quelles adresses IP / hosts tu veux que je teste après la connexion
```

If they do not send a ready `.ovpn` file, ask for:

- CA cert
- client cert
- client key
- TLS static key (if used in profile)
- VPN server public IP/FQDN and port
- exact auth method (user/pass, cert-only, or both)

---

## 3) What OpenVPN is doing in this project

OpenVPN is your **secure door** into the lab network.

Without VPN:

- you are outside the protected network
- firewall can block management access (especially pfSense web UI)

With VPN:

- your Mac gets a VPN IP
- traffic to allowed internal networks is encrypted
- firewall rules decide what you can access

Important mental model:

- "Connected" does not always mean "everything reachable"
- Access depends on:
  1. VPN connection is up
  2. routes are pushed to your laptop
  3. firewall rules allow your source to target

---

## 4) macOS setup steps (OpenVPN Connect)

1. Install/Open OpenVPN Connect on your Mac.
2. Import the `.ovpn` profile from teammate.
3. Click Connect.
4. Enter VPN username/password if prompted.
5. Accept prompts (Keychain/network extension) if macOS asks.

Expected first success:

- Status shows connected
- You can open `https://192.168.100.1` (if teammate enabled VPN-to-WebUI access)

---

## 5) Quick verification after connect

Run in terminal:

```bash
ifconfig | grep -A 4 utun
```

You should see an active `utun` interface after connection.

Then test:

```bash
ping -c 3 192.168.100.1
```

If ping fails but web UI works, this can still be acceptable (ICMP may be blocked by firewall policy).

Then try browser:

- `https://192.168.100.1`

---

## 6) If "Connected" but cannot access targets

Use this order:

1. Confirm profile is your personal one (not another teammate's file).
2. Reconnect once from OpenVPN Connect.
3. Check you got an active `utun` interface.
4. Test pfSense VPN gateway first (`192.168.100.1`).
5. Ask teammate to verify firewall rule on `OpenVPN` interface for your source.
6. Ask teammate whether route/policy to Site 1 subnets is configured for remote users.

Note:

- Some VM-to-VM or ICMP paths are intentionally blocked in your project.
- Use service tests (HTTPS/SSH) instead of only ping.

---

## 7) What you can do now vs what must wait

Do now:

- install OpenVPN Connect
- send the request message
- prepare browser/terminal tests

Must wait for teammate:

- personal cert/profile export
- final firewall permissions for your account
- confirmation of which networks you should access

---

## 8) Minimal success criteria for you

- You can connect VPN from Mac without auth errors.
- You can open pfSense WebUI via VPN address.
- You can reach the exact IPs your teammate says are in-scope for your role.
- You understand that blocked ping does not always mean failure.
