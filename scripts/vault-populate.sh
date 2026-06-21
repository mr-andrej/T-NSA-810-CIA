#!/bin/bash
#
# Idempotent script that creates every secret path expected by the
# infrastructure. Re-running is safe — Vault KV v2 versions previous values.
#
# Usage:
#   1. Source your secret values into the environment (file kept OUT of git,
#      e.g. ~/.config/tnsa/vault-secrets.env):
#        export VAULT_ADDR=https://192.168.20.1:8200
#        export VAULT_CACERT=$HOME/.ansible/vault-ca.crt
#        export VAULT_TOKEN=<admin-userpass-token>
#        export PROXMOX_S1_TOKEN_SECRET=...
#        export PROXMOX_S2_TOKEN_SECRET=...
#        export NETBOX_DB_PASSWORD=...
#        export NETBOX_DJANGO_SECRET_KEY=...
#        export NETBOX_SUPERUSER_PASSWORD=...
#        export NETBOX_API_TOKEN=...               # NEW, post-rotation
#        export SSH_LUCAS_PUBKEY="ssh-ed25519 ..."
#        export SSH_PAUL_PUBKEY="ssh-ed25519 ..."
#        export SSH_ANDREJ_PUBKEY="ssh-ed25519 ..."
#        export SSH_BASTION_PRIVKEY_FILE=/path/to/bastion-id_ed25519
#        export SSH_BASTION_PUBKEY="ssh-ed25519 ..."
#        export VPN_SITE2_CA_FILE=/path/to/site2-vpn-ca.crt
#        export VPN_SITE2_CA_KEY_FILE=/path/to/site2-vpn-ca.key
#        export VPN_S2S_CLIENT_CRT_FILE=/path/to/s2s-site1-client.crt
#        export VPN_S2S_CLIENT_KEY_FILE=/path/to/s2s-site1-client.key
#        export VPN_S2S_TLS_AUTH_FILE=/path/to/s2s-tls-auth.key
#        export PFSENSE_SITE1_ADMIN_PASSWORD=...
#        export PFSENSE_SITE2_ADMIN_PASSWORD=...
#
#   2. Run:
#        ./scripts/vault-populate.sh
#
# Any variable left unset causes its entry to be skipped (the script logs it
# but does not fail).

set -euo pipefail

: "${VAULT_ADDR:?VAULT_ADDR is required}"
: "${VAULT_TOKEN:?VAULT_TOKEN is required (admin token from userpass login)}"

put() {
    local path="$1"
    shift
    local kv_pairs=("$@")
    if [ ${#kv_pairs[@]} -eq 0 ]; then
        echo "skip  ${path} (no values provided)"
        return 0
    fi
    vault kv put "secret/${path}" "${kv_pairs[@]}" > /dev/null
    echo "ok    secret/${path}"
}

put_file() {
    local path="$1"
    local key="$2"
    local file="${3:-}"
    if [ -z "${file}" ] || [ ! -f "${file}" ]; then
        echo "skip  ${path} (${key} file missing)"
        return 0
    fi
    vault kv put "secret/${path}" "${key}=@${file}" > /dev/null
    echo "ok    secret/${path} (from ${file})"
}

# ── Proxmox ────────────────────────────────────────────────────────────────
put infra/proxmox/site1 \
    "api_user=GR37@pve" \
    "api_token_id=ansible" \
    "api_token_secret=${PROXMOX_S1_TOKEN_SECRET:?}"

put infra/proxmox/site2 \
    "api_user=GR37@pve" \
    "api_token_id=ansible" \
    "api_token_secret=${PROXMOX_S2_TOKEN_SECRET:?}"

# ── SSH admin public keys (two per admin: laptop key + bastion-side key) ──
[ -n "${SSH_LUCAS_PC_PUBKEY:-}${SSH_LUCAS_BASTION_PUBKEY:-}" ] && \
    put infra/ssh/admins/lucas \
        "pc_public_key=${SSH_LUCAS_PC_PUBKEY:-}" \
        "bastion_public_key=${SSH_LUCAS_BASTION_PUBKEY:-}"

[ -n "${SSH_PAUL_PC_PUBKEY:-}${SSH_PAUL_BASTION_PUBKEY:-}" ] && \
    put infra/ssh/admins/paul \
        "pc_public_key=${SSH_PAUL_PC_PUBKEY:-}" \
        "bastion_public_key=${SSH_PAUL_BASTION_PUBKEY:-}"

[ -n "${SSH_ANDREJ_PC_PUBKEY:-}${SSH_ANDREJ_BASTION_PUBKEY:-}" ] && \
    put infra/ssh/admins/andrej \
        "pc_public_key=${SSH_ANDREJ_PC_PUBKEY:-}" \
        "bastion_public_key=${SSH_ANDREJ_BASTION_PUBKEY:-}"

# ── Bastion SSH key pair (for rsync to s2_mt) ──────────────────────────────
if [ -n "${SSH_BASTION_PRIVKEY_FILE:-}" ] && [ -f "${SSH_BASTION_PRIVKEY_FILE}" ]; then
    PRIVKEY_CONTENT=$(cat "${SSH_BASTION_PRIVKEY_FILE}")
    put infra/ssh/bastion \
        "private_key=${PRIVKEY_CONTENT}" \
        "public_key=${SSH_BASTION_PUBKEY:?SSH_BASTION_PUBKEY required when SSH_BASTION_PRIVKEY_FILE is set}"
else
    echo "skip  infra/ssh/bastion (no private key file provided)"
fi

# ── NetBox ─────────────────────────────────────────────────────────────────
put netbox/db        "password=${NETBOX_DB_PASSWORD:?}"
put netbox/django    "secret_key=${NETBOX_DJANGO_SECRET_KEY:?}"
put netbox/superuser "password=${NETBOX_SUPERUSER_PASSWORD:?}"
put netbox/api       "token=${NETBOX_API_TOKEN:?NETBOX_API_TOKEN required (rotated value, not the old 16595d4...)}"

# ── VPN (OpenVPN site-to-site) ─────────────────────────────────────────────
if [ -n "${VPN_SITE2_CA_FILE:-}" ] && [ -f "${VPN_SITE2_CA_FILE}" ]; then
    vault kv put secret/vpn/site2-ca \
        "cert=@${VPN_SITE2_CA_FILE}" \
        "key=@${VPN_SITE2_CA_KEY_FILE:-/dev/null}" > /dev/null
    echo "ok    secret/vpn/site2-ca"
else
    echo "skip  vpn/site2-ca (export VPN_SITE2_CA_FILE to provision)"
fi

if [ -n "${VPN_S2S_CLIENT_CRT_FILE:-}" ] && [ -f "${VPN_S2S_CLIENT_CRT_FILE}" ]; then
    vault kv put secret/vpn/s2s-site1-client \
        "cert=@${VPN_S2S_CLIENT_CRT_FILE}" \
        "key=@${VPN_S2S_CLIENT_KEY_FILE:?}" \
        "tls_auth=@${VPN_S2S_TLS_AUTH_FILE:?}" > /dev/null
    echo "ok    secret/vpn/s2s-site1-client"
else
    echo "skip  vpn/s2s-site1-client (export VPN_S2S_CLIENT_CRT_FILE to provision)"
fi

# ── pfSense admin passwords ────────────────────────────────────────────────
[ -n "${PFSENSE_SITE1_ADMIN_PASSWORD:-}" ] && put firewall/pfsense/site1 "admin_password=${PFSENSE_SITE1_ADMIN_PASSWORD}"
[ -n "${PFSENSE_SITE2_ADMIN_PASSWORD:-}" ] && put firewall/pfsense/site2 "admin_password=${PFSENSE_SITE2_ADMIN_PASSWORD}"

echo
echo "Done. Verify with: vault kv list secret/"
