# Non-regression test suite

Functional end-to-end validation of the infrastructure. Catches breaking
changes by exercising every documented path — including the **negative**
ones (paths that must remain blocked).

The test code itself lives at:
- Playbook: [`ansible/playbooks/non_regression.yaml`](../ansible/playbooks/non_regression.yaml)
- Wrapper: [`scripts/non-regression.sh`](../scripts/non-regression.sh)

Run it manually before/after any infra change. No CI hook today — the suite
is on-demand only, by design (avoids the cost of a self-hosted runner inside
the Admin VPN, which is the only network that can reach the targets).

## Run locally

Prerequisites: connected to Admin VPN, Vault `secret_id` and CA cert in
`~/.ansible/` (see [Vault wiki §1–4](../docs/secret-management/wiki-page-Vault-Implementation.md)).

```bash
# Full run
./scripts/non-regression.sh

# After a firewall change
./scripts/non-regression.sh --tags firewall,bastion

# Verbose
./scripts/non-regression.sh -vv
```

Exit code is 0 only if every assertion passes.

## Categories (tags)

| Tag | What it checks | Catches |
| --- | --- | --- |
| `vault` | `/sys/health` reachable, AppRole login works, known KV path readable | Vault sealed, policy regression, expired secret_id |
| `network` | Per-VM gateway + internet reachability | Routing / VPN regressions |
| `firewall` | Allowed paths actually work (s1-app→postgres, bastion→vault, bastion→site1 SSH, syslog, Admin VPN → visitapp HTTP) | A rule got removed or reordered |
| `firewall_negative` | **Denied** paths actually fail (direct admin SSH bypass, S1-DB initiating to S1-APP, pfSense WAN HTTPS/SSH exposure) | **Security regression** — a block rule was relaxed |
| `bastion` | SSH via `ProxyJump=bastion` reaches every managed VM | Bastion users, sshd, or proxy chain broken |
| `dns` | Local + cross-site lookups resolve | Domain Override missing, Forwarding Mode re-enabled |
| `observability` | `junkyard.service` active, `/health` returns 200, every managed host has at least one log line in JUNKyard | rsyslog config or JUNKyard service regression |
| `netbox` | UI 200, API auth, 6+ devices, dynamic inventory `--graph` returns expected groups | NetBox install, token rotation, or inventory plugin regression |
| `database` | postgresql service active, `SELECT 1` on `appdb`, `appuser` role exists | Postgres down, schema regression, role removed |
| `application` | visitapp HTTP 200, body non-empty, `visitapp.service` active | App crashed, port not bound, DB unreachable from app |

## Adding a new check

1. **Pick the right play** in `non_regression.yaml` based on what's being exercised.
2. For a positive check, add a `wait_for` / `uri` / `command` task with an explicit `failed_when` or `status_code`.
3. **For a security check (negative)**, follow the pattern in play 4: drive a list of `(src, dst, port, label)` entries, run with `ignore_errors: true`, then `assert that: item is failed` with a `fail_msg` that says "SECURITY REGRESSION" + the label. This is what catches broken block rules.
4. Tag the new task so it can be targeted with `--tags`.

## Design notes

- **No separate role.** Single playbook, multi-play. Easy to read end-to-end. Promote to a role only if it grows past ~15 plays.
- **No Python deps beyond Ansible's own.** Everything goes through `wait_for`, `uri`, `command`, `assert`.
- **`localhost` plays drive the negative checks.** The whole point of "Admin VPN → S1-APP direct SSH must be blocked" is that the controller is the would-be attacker — running the check from the source-of-truth side proves the firewall is actually doing its job.
- **`failed_when` on commands** is preferred over `ignore_errors` for positive checks — the failure surfaces in the play recap immediately.
- **Loop labels** (`loop_control.label`) make the output readable: each iteration shows the human label instead of the raw item dict.

## Known gaps

- pfSense (`s1_fw`, `s2_fw`) are not Ansible-managed, so we don't try to SSH them. Their behaviour is asserted indirectly via the `firewall` / `firewall_negative` paths.
- Tunnel-endpoint pings (172.16.0.1 / .2) are not covered yet — would need to delegate to a pfSense host. Add via `ansibleguy.pfsense_diag` if needed.

## Open infra issues caught by the suite

These are real infra gaps the tests have surfaced. Not test bugs.

- **`dns`** — cross-site resolution fails (`*.site2.internal` from Site 1 and vice-versa). Local DNS on each site works. Even with Domain Overrides + DNS Query Forwarding disabled + firewall rule `172.16.0.0/30 → * : 53` + Network Interfaces=All, unbound on each pfSense does not bind to the OpenVPN tunnel IP — so the resolver-to-resolver forward times out, returning SERVFAIL on the originating side. Likely fix: add `server: interface: 172.16.0.x` in DNS Resolver → General Settings → Custom Options on each pfSense (172.16.0.1 on S2-FW, 172.16.0.2 on S1-FW), Save → Apply → restart unbound. Tracked separately.
