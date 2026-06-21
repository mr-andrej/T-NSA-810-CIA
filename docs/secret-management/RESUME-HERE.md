# Resume Here — Vault deployment

**Branche** : `62-secret-management`

## Où on en est (✅ déjà fait)

- Code complet pushé : rôle `ansible/roles/vault/`, playbook `playbooks/vault.yaml`, policies `policies/*.hcl`, script `scripts/vault-populate.sh`, refactor des 7 playbooks (bastion, managed_vms, netbox, netbox_populate, netbox_sync, netbox_cleanup, proxmox_snapshot), suppression de `vault.yaml`, doc complète sous `docs/secret-management/`.
- Snapshot Proxmox `pre-vault-install` pris (VM 3037).
- Token NetBox initial (commité en clair `16595d47...`) **rotaté** → nouvelle valeur stockée dans Vault sous `secret/netbox/api`. **Jamais en clair dans le repo.**
- Vault déployé sur s2_mt (`https://192.168.20.1:8200`), service systemd actif, TLS interne, backup quotidien programmé.
- Vault **initialisé** (`vault operator init`), 5 clés Shamir + root token générés.
- Vault **unsealed** avec 3 clés.
- KV v2 monté sur `secret/`, audit log activé (`/var/log/vault/audit.log`).
- AppRole + userpass enabled.
- 4 policies chargées : `admin-ops`, `ansible-deploy`, `ansible-netbox`, `audit-read`.
- AppRole `ansible-deploy` créé :
  - `role_id` publié dans `ansible/group_vars/all/vars.yaml` (clé `vault_role_id`)
  - `secret_id` distribué hors-bande aux opérateurs → `~/.ansible/vault-secret-id` (gitignored)
- CA cert publiée à `/etc/ssl/certs/vault-ca.crt` sur s2_mt + `~/.ansible/vault-ca.crt` sur le laptop.
- **Tous les secrets peuplés** dans Vault via `scripts/vault-populate.sh` :
  - `secret/infra/proxmox/site1` + `site2`
  - `secret/infra/ssh/admins/lucas|paul|andrej` (avec `pc_public_key` + `bastion_public_key`)
  - `secret/netbox/db`, `django`, `superuser`, `api`
- Lib Python `hvac` installée sur le laptop (`pip3 install --user --break-system-packages hvac`).

## Ce qui reste (⏳ à faire)

### 1. Ajouter 2 règles firewall pfSense S2-FW
**Sans ça, le test end-to-end depuis le laptop échoue (TCP 8200 bloqué entre VLANs).**

UI pfSense `https://5.196.45.7` (via Admin VPN) → **Firewall → Rules**.

**Sur OPT1 (DMZ/Bastion)** — Add (placer **avant** le Block all final) :
| Action | Protocol | Source | Destination | Port | Description |
| --- | --- | --- | --- | --- | --- |
| Pass | TCP | `192.168.10.10/32` | `192.168.20.1/32` | `8200` | Vault — depuis bastion |

**Sur OpenVPN** — Add (placer avant le Block all) :
| Action | Protocol | Source | Destination | Port | Description |
| --- | --- | --- | --- | --- | --- |
| Pass | TCP | `192.168.100.0/24` | `192.168.20.1/32` | `8200` | Vault — depuis Admin VPN |

Save → **Apply Changes**.

### 2. Test end-to-end (depuis le laptop)

```bash
cd /Users/lucasboillot/Public/www/cloud-project-1/ansible
make snap.create.site2.mt SNAP=post-vault-test
```

Doit passer sans erreur jusqu'à `TASK [Create snapshot]`. Ça valide tout le pipeline : Ansible → AppRole login → Vault KV lookup → Proxmox API.

### 3. Créer les comptes humains userpass + révoquer le root token

Sur s2_mt (SSH via bastion) :

```bash
# Pré-requis : exports VAULT_ADDR + VAULT_CACERT (déjà dans ton .bashrc si tu l'as fait, sinon refaire)
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/ssl/certs/vault-ca.crt
export VAULT_TOKEN=<root-token-init>   # noté hors-bande à l'init Vault

vault write auth/userpass/users/lucas  password='<mdp-initial-lucas>'  policies=admin-ops
vault write auth/userpass/users/paul   password='<mdp-initial-paul>'   policies=admin-ops
vault write auth/userpass/users/andrej password='<mdp-initial-andrej>' policies=admin-ops

# Test ton login
unset VAULT_TOKEN
vault login -method=userpass username=lucas
vault write auth/userpass/users/lucas/password password='<mdp-fort-perso>'

# Révoque le root token (point of no return — n'avance pas tant que ton login userpass ne marche pas)
vault token revoke <root-token-init>
```

### 4. Distribuer les 5 clés Shamir hors-bande

Distribue 1 clé à chaque membre de l'équipe (Signal/papier). Les 5 clés ont été notées hors-bande à l'init Vault — **jamais en clair dans le repo**. Voir le template de message à envoyer dans `shamir-keys.md`.

⚠️ Ces clés ont été collées dans une conversation Claude → considérées comme exposées. Décision projet académique : on garde. Pour une vraie prod, faire `vault operator rekey` (procédure dans `disaster-recovery.md` scénario 2).

### 5. Copier la page wiki

Le contenu de `docs/secret-management/wiki-page-Vault-Implementation.md` est prêt à coller dans la page wiki GitHub `Vault ‐ Secrets Management` (ou créer une nouvelle page `Vault ‐ Implementation`).

URL wiki : https://github.com/mr-andrej/T-NSA-810-CIA/wiki

### 6. Commit et PR

```bash
cd /Users/lucasboillot/Public/www/cloud-project-1
git status
git add -A
git commit -m "feat(vault): introduce HashiCorp Vault for secret management

- New ansible/roles/vault/ deploys Vault on s2_mt with file backend, TLS,
  systemd MemoryMax=200M, daily snapshots.
- 4 Vault policies in policies/*.hcl (ansible-deploy, ansible-netbox,
  admin-ops, audit-read).
- All playbooks refactored to fetch secrets at runtime via AppRole login
  (community.hashi_vault). Removed ansible-vault entirely.
- Rotated the NetBox API token previously committed in plaintext.
- Full doc in docs/secret-management/ including DR runbook and
  copy-paste-ready wiki page.
- ticket #62"
git push -u origin 62-secret-management
gh pr create --base main --title "feat(vault): HashiCorp Vault for secret management (#62)" --body-file ...
```

## Endpoints / valeurs utiles

| Quoi | Où |
| --- | --- |
| Vault API | `https://192.168.20.1:8200` |
| CA cert sur laptop | `~/.ansible/vault-ca.crt` |
| CA cert sur s2_mt (public) | `/etc/ssl/certs/vault-ca.crt` |
| CA cert sur s2_mt (privé root) | `/etc/vault.d/tls/ca.crt` |
| Vault logs audit | `/var/log/vault/audit.log` sur s2_mt |
| Snapshots quotidiens | `/home/administrator/junkyard/vault-snapshots/` sur s2_mt |
| Env file populate (gitignored) | `~/.config/tnsa/vault-secrets.env` |
| AppRole role_id | `vars.yaml` → `vault_role_id` |
| AppRole secret_id | `~/.ansible/vault-secret-id` |

## Workarounds réseau (si besoin)

Si tu veux tester depuis le laptop AVANT d'ajouter les règles firewall (peu probable) :

```bash
ssh -L 8200:192.168.20.1:8200 -fN bastion
ansible-playbook playbooks/proxmox_snapshot.yaml \
  -e snap_action=create -e site=site2 -e vmid=3037 -e snap_name=post-vault-test \
  -e vault_addr=https://127.0.0.1:8200
# Pour fermer le tunnel :
pkill -f "ssh -L 8200"
```

⚠️ Cela ne contourne PAS la règle firewall — bastion → s2_mt:8200 est aussi bloqué. Le tunnel marche seulement APRÈS avoir ajouté la règle OPT1.
