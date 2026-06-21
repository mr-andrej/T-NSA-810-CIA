#!/usr/bin/env bash
# Thin wrapper around the non-regression Ansible playbook.
# Verifies prerequisites locally before invoking ansible-playbook.
#
# Usage:
#   ./scripts/non-regression.sh                 # full run
#   ./scripts/non-regression.sh --tags firewall # targeted
#   ./scripts/non-regression.sh -v              # verbose
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
PLAYBOOK="playbooks/non_regression.yaml"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

# ── Prerequisites ──────────────────────────────────────────────────────
missing=0

for file in "$HOME/.ansible/vault-ca.crt" "$HOME/.ansible/vault-secret-id"; do
  if [[ ! -r "$file" ]]; then
    red "missing: $file"
    missing=1
  fi
done

if ! command -v ansible-playbook >/dev/null 2>&1; then
  red "ansible-playbook not in PATH"
  missing=1
fi

# Vault reachability — Python instead of curl because macOS Secure Transport
# rejects the cert (RFC strictness around single-label SANs). Ansible uses
# OpenSSL via Python so the playbook itself is fine.
if ! python3 -c "
import ssl, urllib.request, sys
ctx = ssl.create_default_context(cafile='$HOME/.ansible/vault-ca.crt')
try:
    urllib.request.urlopen('https://192.168.20.1:8200/v1/sys/health',
                           context=ctx, timeout=5).read()
except Exception as e:
    sys.exit(str(e))
" 2>/dev/null; then
  yellow "warning: Vault not reachable at https://192.168.20.1:8200 — are you on the Admin VPN?"
  yellow "         continuing anyway; the playbook will fail with a clearer message"
fi

if [[ $missing -ne 0 ]]; then
  red "Pre-flight checks failed. See docs/secret-management/wiki-page-Vault-Implementation.md §1–4."
  exit 2
fi

# ── Run ────────────────────────────────────────────────────────────────
# Pin to the static inventory only — the NetBox dynamic inventory triggers
# noisy warnings when NETBOX_TOKEN isn't set, and the non-regression suite
# doesn't need it (the NetBox play fetches the token from Vault itself).
cd "$ANSIBLE_DIR"
export ANSIBLE_INVENTORY="inventory/hosts.yaml"

# macOS fork-safety: Python lookups that touch Objective-C frameworks (hvac,
# urllib3 SSL via SecureTransport, etc.) crash with "worker was found in a
# dead state" without these env vars. No-op on Linux.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export no_proxy='*'

green "running ${PLAYBOOK} $*"
exec ansible-playbook "${PLAYBOOK}" "$@"
