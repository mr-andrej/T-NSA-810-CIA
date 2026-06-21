# Non-Regression Tests

> **Wiki page — operator-facing.** End-to-end functional + security validation
> of the infrastructure. Run it on demand before/after any infra change.

## TL;DR

A single Ansible playbook exercises every documented path of the
infrastructure (Vault auth, inter-VM connectivity, firewall blocks, DNS,
observability, IPAM, database, app) in **~90 seconds** and prints
`FUNCTIONAL REGRESSION` or `SECURITY REGRESSION` for any gap it finds.

```bash
./scripts/non-regression.sh                 # full run, ~90s
./scripts/non-regression.sh --tags firewall # targeted, ~15s
```

Exit code is `0` only if every assertion passes.

## Why this exists

Configuration drift is the silent killer of an infrastructure of this size.
A single forgotten "Apply Changes" in pfSense, an admin who relaxes an SSH
block to debug something, an Ansible role that stops being run — and a path
that used to be tight goes wide open. Non-regression tests turn
"we *think* the firewall blocks X" into "the firewall *demonstrably* blocks
X at this exact second, prove me wrong".

The most valuable checks here are the **negative** ones:
*"the admin VPN must NOT be able to SSH directly to S1-APP"*. If that
assertion ever passes (i.e., direct SSH succeeds), the suite shouts
**SECURITY REGRESSION** and exits non-zero. Positive checks tell you
something is broken; negative checks tell you something is **dangerous**.

## Where the code lives

- Playbook: [`ansible/playbooks/non_regression.yaml`](../../ansible/playbooks/non_regression.yaml)
- Wrapper script: [`scripts/non-regression.sh`](../../scripts/non-regression.sh)
- This doc: [`docs/architecture/non-regression-tests.md`](non-regression-tests.md)
- Test README (operator quick-start): [`tests/README.md`](../../tests/README.md)

No CI hook today — the suite is on-demand only, by design (avoids the cost
of a self-hosted runner inside the Admin VPN, which is the only network
that can reach the targets).

## Prerequisites

Run on an operator workstation that has:

- **Admin VPN connected** (`192.168.100.0/24`) — without it nothing in
  `10.0.0.0/8` or `192.168.20.1` is reachable.
- **Vault CA cert** at `~/.ansible/vault-ca.crt`.
- **AppRole `secret_id`** at `~/.ansible/vault-secret-id`.
- **SSH config** with `Host bastion` defined and `ProxyJump bastion` for the
  managed VMs (see the [Vault wiki](../secret-management/wiki-page-Vault-Implementation.md)
  §Onboarding for the full setup).
- **Ansible + community.hashi_vault collection** installed
  (`ansible-galaxy collection install -r ansible/requirements.yml`).

The wrapper script does a Python-based pre-flight (`/sys/health` over
HTTPS) and refuses to run if Vault isn't reachable.

## Test categories (tags)

The playbook has 10 tagged plays. Run them all (`./scripts/non-regression.sh`)
or any subset (`--tags firewall,bastion`).

| Tag | What it checks | What it catches |
| --- | --- | --- |
| `vault` | `/sys/health` reachable, AppRole login succeeds, KV read on `secret/netbox/api` works | Vault sealed, expired `secret_id`, policy regression |
| `network` | SSH via ProxyJump reaches each managed VM; outbound HTTPS to a public host works | VPN/tunnel down, NAT broken, no internet for system updates |
| `firewall` (allowed) | 7 allowed paths: S1-APP→Postgres :5432, S1-APP→JUNKyard syslog, S1-APP→Vault, Bastion→Vault, Bastion→S1-APP/S1-DB SSH via tunnel, Admin VPN→visitapp HTTP | A rule was removed or reordered, a service stopped listening |
| `firewall_negative` (security) | 8 paths that MUST be denied: Admin VPN direct SSH to S1-APP/S1-DB/S2-MT, S1-DB→S1-APP, pfSense WAN HTTPS on both sites, pfSense WAN SSH on both sites | **A block rule was relaxed** — surfaces as `SECURITY REGRESSION` |
| `bastion` | SSH via ProxyJump reaches every managed VM (positive duplicate of part of `network`, kept for tag isolation) | Bastion users wiped, sshd_config broken, proxy chain broken |
| `dns` | Lookups via `dig +short` against each site's pfSense resolver: `s1_app` resolves its 2 site1 neighbours; bastion (`s2_js`) resolves all 4 names (2 local site2 + 2 cross-site site1 via the OpenVPN forward-zone). External DNS (`google.com`) tested from both. | Host Override missing on pfSense, forward-zone Custom Options dropped on the peer pfSense, `outgoing-interface` re-pinned to WAN IP, tunnel DNS rule deleted |
| `observability` | `junkyard.service` is active on S2-MT, `/health` returns 200, every managed host (5 of them) has at least one log line in JUNKyard | rsyslog config drift, JUNKyard service down, syslog firewall rule removed |
| `netbox` | NetBox UI returns HTTP 200 from Admin VPN, API authenticates with the Vault-stored token, returns ≥6 devices, dynamic inventory `--graph` lists `sites_site1` + `sites_site2` | NetBox install regression, token revoked, dynamic inventory plugin broken |
| `database` | PostgreSQL service is active on S1-DB, `SELECT 1` against `appdb` succeeds, `appuser` role exists | Postgres down, schema regression, role removed by accident |
| `application` | visitapp returns HTTP 200 on `http://10.0.10.1/` with a non-empty body, `visitapp.service` is active on S1-APP | App crashed, listening on wrong port, can't reach the DB |

The `vault` tag also runs as `always` — even with `--tags database`, Vault
is verified first. Reason: every other check needs the AppRole token, so we
fail fast if Vault is dead.

## How to read the output

### Successful run

```
PLAY RECAP **********
localhost : ok=12  failed=0
s1_app    : ok=3   failed=0
s1_db     : ok=3   failed=0
s2_js     : ok=3   failed=0
s2_mt     : ok=3   failed=0
```

Exit code 0. Every assertion passed.

### Functional regression

```
TASK [Assert every allowed path opened] **********
failed: [localhost] (item=S1-APP → S1-DB PostgreSQL) => {
    "msg": "FUNCTIONAL REGRESSION: S1-APP → S1-DB PostgreSQL did not open
            (10.0.20.1:5432 from s1_app) — firewall rule missing OR service
            not listening"
}
```

Something stopped working. Could be a firewall rule, could be the service
itself. The message says "OR" because the test can't always distinguish
the two — fix by checking the service first (`systemctl status …`) then
the firewall rule.

### Security regression (the high-priority one)

```
TASK [Assert every denied path actually failed] **********
failed: [localhost] (item=S2-FW WAN HTTPS — admin UI must not be exposed) => {
    "msg": "SECURITY REGRESSION: S2-FW WAN HTTPS — admin UI must not be
            exposed on public IP succeeded — firewall rule has been
            weakened or reordered"
}
```

A path that should be blocked is open. **This is a real attack surface**.
Treat as urgent.

## Adding a new check

### Positive check (something must work)

Pick the right play, add a `wait_for` or `uri` or `command` task with an
explicit failure condition. Example, inside the `application` play:

```yaml
- name: visitapp /healthz endpoint returns 200
  ansible.builtin.uri:
    url: http://10.0.10.1/healthz
    status_code: 200
    timeout: 5
```

### Negative check (something must NOT work) — the high-value pattern

Add an entry to the `denied_paths` list in the firewall-denied play:

```yaml
- { src: localhost, dst: <ip>, port: <port>, label: "Description of the boundary" }
```

The loop will probe it with `ignore_errors: true`, then the assert task
will fail with `SECURITY REGRESSION: <label>` if the probe *succeeded*
(meaning the boundary was breached).

### Tag your new check

Either add it inside an existing play (inherits that play's tag) or add a
new play with its own `tags: [my_new_tag]`.

## Design notes

- **Single playbook, multi-play.** No separate role. Easy to read
  end-to-end. Promote to a role only if it grows past ~15 plays.
- **No Python deps beyond Ansible's own.** Everything goes through
  `wait_for`, `uri`, `command`, `assert`.
- **`localhost` plays drive the negative checks.** The whole point of
  "Admin VPN → S1-APP direct SSH must be blocked" is that the controller
  is the would-be attacker — running the check from the would-be-attacker
  side proves the firewall is actually doing its job.
- **`block:` + `always: meta: clear_host_errors`** wraps the positive and
  negative loops, so a `FUNCTIONAL REGRESSION` in one play does not skip
  the subsequent plays. Without this, an early failure on host `localhost`
  causes Ansible to silently skip every subsequent play that targets
  `localhost`.
- **`loop_control.label`** on every loop. Output reads as English
  ("Admin VPN → S1-APP direct SSH") instead of raw dicts.
- **macOS-safe wrapper.** The script exports
  `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` and `no_proxy='*'` to work
  around the classic "A worker was found in a dead state" crash on macOS
  when Ansible uses Python lookups that touch Apple frameworks.
- **NetBox inventory is pinned out.** The wrapper sets
  `ANSIBLE_INVENTORY=inventory/hosts.yaml` so the dynamic NetBox inventory
  plugin (which needs `NETBOX_TOKEN`) doesn't pollute output with parse
  warnings. The NetBox play fetches its own token from Vault internally.

## Real findings on the first run

The first end-to-end run surfaced **two genuine infrastructure gaps** that
no one had noticed:

1. **DNS cross-site looked silently broken; turned out to be a test-side
   trap.** Initial runs failed every cross-site lookup with `NXDOMAIN`
   from `getent hosts`. Six hours of pfSense unbound debug followed
   (verbosity 4 logs, tcpdump on tunnel, Custom Options audit, etc.) before
   the real cause surfaced: the forward-zone **was** working all along.
   Two superposed issues masked it:
   (a) S1-FW had `outgoing-interface: 5.196.50.51` forcing unbound to
   source from the WAN IP — fixed via Services → DNS Resolver → General
   Settings → Outgoing Network Interfaces = "All";
   (b) the test used `getent hosts`, which on Ubuntu 24 goes through
   systemd-resolved with `search site2.internal` in `/etc/resolv.conf`.
   glibc tried `db.site1.internal.site2.internal` *first*, hit `NXDOMAIN`
   from the root, and unbound DNSSEC-cached that negative answer for an
   hour — shadowing the real name in subsequent queries. The fix in the
   test: replace `getent hosts` with `dig +short @<pfsense-gateway>` to
   bypass systemd-resolved entirely. Full forensic in
   [`dns-cross-site-debug.md`](dns-cross-site-debug.md). The takeaway for
   future tests: never use `getent` in a non-regression check against
   resolvers that DNSSEC-validate, and always pin the resolver explicitly
   with `dig @…`.

2. **pfSense WAN HTTPS was exposed on both sites.** The admin UI was
   reachable on the public IPs `5.196.50.51:443` and `5.196.45.7:443` from
   any internet host. The WAN tab default-deny ruleset was correct on
   paper, but a NAT port-forward (or a `Listen Interfaces` setting in
   **System → Advanced → Admin Access** including WAN) was bypassing it.
   Fixed by tightening the WebGUI listen interfaces and re-checking
   port-forwards. The test now keeps watching: any future regression that
   re-exposes :443 on either WAN will fail this check.

The fact that a brand-new test suite immediately found two real
production-grade issues — one of them outright security-critical — is
the strongest possible justification for keeping the suite live.

## Known gaps / TODOs

- **pfSense** (`s1_fw`, `s2_fw`) are not Ansible-managed, so the suite
  cannot SSH them. Their behaviour is asserted indirectly via the
  `firewall` and `firewall_negative` paths.
- **Tunnel-endpoint pings** (`172.16.0.1` / `172.16.0.2`) are not covered.
  Would need to delegate to a pfSense host or use the `ansibleguy.pfsense_diag`
  collection.
- **No timestamp check** on JUNKyard logs (the `junk logs` CLI does not
  have a `--since` flag yet). The suite checks "host has logs at all",
  not "host has *recent* logs". A regression where syslog stops mid-day
  would only surface after the buffer rotates.
- **Matrice DNS asymétrique par design.** `s1_app` only resolves its
  local `*.site1.internal` neighbours — not `*.site2.internal`. Rationale:
  per the isolation matrix, site1 VMs never initiate traffic toward
  site2 VMs; the bastion comes to them via ProxyJump. Testing a resolution
  that has no operational consumer would just add a fragile check for no
  benefit. The bastion (`s2_js`) keeps the full matrix since it must
  resolve everything for its ProxyJump role.

## References

- Vault implementation: [`docs/secret-management/wiki-page-Vault-Implementation.md`](../secret-management/wiki-page-Vault-Implementation.md)
- DR runbook: [`docs/architecture/rebuild-runbook.md`](rebuild-runbook.md)
- Scalability defense: [`docs/architecture/scalability.md`](scalability.md)
- Access isolation matrix: [`docs/access-isolation-validation.md`](../access-isolation-validation.md)
- Ansible inventory: [`ansible/inventory/hosts.yaml`](../../ansible/inventory/hosts.yaml)
