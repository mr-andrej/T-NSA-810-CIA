# Vault ‐ Implementation

> **Page wiki technique** — détaille la mise en œuvre concrète de la
> stratégie définie dans la page [[Vault ‐ Secrets Management]]. Mettre à
> jour à chaque changement structurel.

## Vue d'ensemble

HashiCorp Vault sert de **single source of truth** pour tous les secrets de
l'infrastructure (tokens API, mots de passe, clés SSH, certs VPN). Plus
aucun secret n'est commité dans le repo, en clair ou via `ansible-vault`.

- **Localisation** : VM **s2_mt** (`192.168.20.1`), Site 2, VLAN 20 Monitoring.
- **Co-localisé avec** : NetBox (IPAM) et JUNKyard (logs).
- **API** : `https://192.168.20.1:8200` (HTTPS, CA interne auto-signée).
- **Accès** : depuis bastion (humains via `userpass`), depuis postes
  opérateur (Ansible via `approle`). Pas d'exposition WAN.

## Schéma — flux d'authentification

```
┌────────────────────────┐       ┌────────────────────┐
│ Admin (laptop)         │       │ Ansible (laptop)   │
│ ~/.ansible/vault-ca.crt│       │ ~/.ansible/        │
│                        │       │   vault-secret-id  │
└───────────┬────────────┘       └─────────┬──────────┘
            │ userpass login                │ AppRole login
            ▼                               ▼
        Admin VPN  ───►  pfSense S2  ───►  bastion s2_js
                                              │
                                              │ tunnel/route
                                              ▼
                                ┌──────────────────────────┐
                                │  s2_mt 192.168.20.1      │
                                │  ┌────────────────────┐  │
                                │  │ vault.service      │  │
                                │  │  :8200 HTTPS       │  │
                                │  │  storage: file     │  │
                                │  │  audit: file       │  │
                                │  └────────────────────┘  │
                                │  + NetBox, JUNKyard      │
                                └──────────────────────────┘
```

## Choix d'architecture (et pourquoi)

| Décision | Raison |
| --- | --- |
| Vault co-localisé sur s2_mt | Contrainte 3 VMs/site — pas de VM dédiée disponible |
| Storage backend `file` | Plus léger que Raft (~30–50 MB économisés) ; suffisant pour un single-node |
| UI Vault désactivée (`ui = false`) | Économise ~20 MB de RAM ; toutes les ops passent par CLI depuis le bastion |
| `disable_mlock = true` | Swap actif sur s2_mt, mlock impossible |
| `MemoryMax=200M` (systemd) | Borne dure pour protéger NetBox d'une fuite mémoire Vault |
| Unseal Shamir 3-of-5 | Robustesse (perte de 2 clés tolérée), pas d'auto-unseal possible (transit demanderait un 2e Vault) |
| AppRole `secret_id` hors-repo | Aucun secret dans le repo, distribution explicite à chaque opérateur |
| `ansible-vault` retiré | Plus aucun secret dans `group_vars/` ; un seul mécanisme de gestion |

## Inventaire des secrets (chemins KV v2)

| Chemin | Champs | Consommé par |
| --- | --- | --- |
| `secret/infra/proxmox/site1` | `api_user`, `api_token_id`, `api_token_secret` | `playbooks/proxmox_snapshot.yaml` |
| `secret/infra/proxmox/site2` | idem | idem |
| `secret/infra/ssh/admins/lucas` | `public_key` | `bastion.yaml`, `managed_vms.yaml` |
| `secret/infra/ssh/admins/paul` | `public_key` | idem |
| `secret/infra/ssh/admins/andrej` | `public_key` | idem |
| `secret/infra/ssh/bastion` | `private_key`, `public_key` | `managed_vms.yaml` (clé publique uniquement) |
| `secret/netbox/db` | `password` | `netbox.yaml` |
| `secret/netbox/django` | `secret_key` | `netbox.yaml` |
| `secret/netbox/superuser` | `password` | `netbox.yaml` |
| `secret/netbox/api` | `token` | `netbox_populate.yaml`, `netbox_sync.yaml`, `netbox_cleanup.yaml` |
| `secret/vpn/site2-ca` | `cert`, `key` | DR uniquement (pfSense gère en runtime) |
| `secret/vpn/s2s-site1-client` | `cert`, `key`, `tls_auth` | DR uniquement |
| `secret/firewall/pfsense/site1` | `admin_password` | DR uniquement |
| `secret/firewall/pfsense/site2` | `admin_password` | DR uniquement |

## Auth methods & policies

| Auth | Pour | Policies |
| --- | --- | --- |
| `approle` (`ansible-deploy`) | Ansible | `ansible-deploy`, `ansible-netbox` |
| `userpass` (1 compte par membre) | Admins humains | `admin-ops` |

Les policies HCL sont versionnées dans [`policies/`](../../policies/) :

- `ansible-deploy.hcl` — read `secret/data/infra/*`
- `ansible-netbox.hcl` — read `secret/data/netbox/*`
- `admin-ops.hcl` — read/write `secret/data/*` + gestion policies/auth
- `audit-read.hcl` — read metadata audit (lecture sans secrets)

## Règles firewall (s2_fw, UI pfSense)

À ajouter manuellement (s2_fw n'est pas encore IaC) :

**OPT1 (DMZ — bastion)**

| Source | Dest | Port | Description |
| --- | --- | --- | --- |
| `192.168.10.0/24` | `192.168.20.1/32` | `8200/tcp` | Vault from bastion |

**OpenVPN (Admin VPN)**

| Source | Dest | Port | Description |
| --- | --- | --- | --- |
| `192.168.100.0/24` | `192.168.20.1/32` | `8200/tcp` | Vault from Admin VPN |

WAN : aucun changement, Vault jamais exposé.

## Procédures opérationnelles

### Déploiement initial

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbooks/vault.yaml
```

Puis bootstrap manuel : voir
[`docs/secret-management/bootstrap.md`](bootstrap.md).

### Unseal après reboot s2_mt

Coordonner **3 membres** de l'équipe (chacun détient 1 clé Shamir) :

```bash
ssh s2-mt
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/vault.d/tls/ca.crt

vault status                        # Sealed: true
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
vault status                        # Sealed: false ✓
```

### Ajouter un nouveau secret

```bash
vault kv put secret/<path> key1=value1 key2=value2
```

Puis référencer depuis un playbook :

```yaml
pre_tasks:
  - import_tasks: tasks/vault_login.yml
  - name: Fetch secret
    set_fact:
      my_secret: "{{ lookup('community.hashi_vault.vault_kv2_get', '<path>', url=vault_addr, ca_cert=vault_ca_cert, token=vault_token).data.data.key1 }}"
```

### Ajouter un nouveau service consommateur

1. Définir le périmètre de lecture nécessaire.
2. Créer une policy dédiée dans `policies/<service>.hcl`.
3. Charger : `vault policy write <service> policies/<service>.hcl`.
4. Créer un AppRole dédié :
   ```bash
   vault write auth/approle/role/<service> \
       token_policies=<service> token_ttl=1h
   ```
5. Distribuer `role_id` + `secret_id` au service hors-bande.

### Ajouter un admin humain

```bash
vault write auth/userpass/users/<nouveau> \
    password=<initial> policies=admin-ops
```

Puis le nouvel admin se logue et change son mot de passe (voir
[`access-policy.md`](access-policy.md)).

### Retirer un admin

```bash
vault delete auth/userpass/users/<partant>
```

Si la personne détenait une clé Shamir → exécuter `vault operator rekey`
pour regénérer toutes les clés (voir [`disaster-recovery.md`](disaster-recovery.md)
scénario 2).

### Rotation d'un secret

Voir [`rotation.md`](rotation.md) — calendrier et procédures par type.

## Disaster Recovery

Voir [`disaster-recovery.md`](disaster-recovery.md) pour les 4 scénarios :

1. Reboot s2_mt (Vault scellé)
2. Perte d'une clé Shamir
3. Restauration depuis snapshot
4. Reconstruction complète

Snapshots quotidiens automatiques à 03h30 dans
`/home/administrator/junkyard/vault-snapshots/`, rétention 14 jours.

## Troubleshooting

### "x509: certificate signed by unknown authority"

L'opérateur n'a pas la CA cert. Récupérer `vault-ca.crt` depuis
`ansible/files/vault-ca.crt` (généré par le rôle Vault) et le placer dans
`~/.ansible/vault-ca.crt`.

### "approle: failed to validate SecretID"

Le `secret_id` dans `~/.ansible/vault-secret-id` est expiré ou révoqué.
Demander un nouveau secret_id à un admin :

```bash
vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id
```

Le coller dans `~/.ansible/vault-secret-id`.

### Vault est scellé après un playbook qui échoue

Un reboot non documenté de s2_mt a probablement eu lieu (mise à jour, OOM
kill). Voir scénario 1 du DR ci-dessus.

### Audit log saturé

```bash
ssh s2-mt
sudo logrotate -f /etc/logrotate.d/vault    # force la rotation
df -h /var/log
```

Si le disque est plein, réduire la rétention dans `/etc/logrotate.d/vault`
ou pruner manuellement les anciens journaux.

### Cert TLS Vault expiré

Symptôme : tous les clients échouent avec une erreur TLS. Régénérer :

```bash
ansible-playbook ansible/playbooks/vault.yaml --tags tls
```

Le handler "Restart Vault" se déclenche, Vault redémarre → re-unseal manuel.

### "MemoryLimit reached" dans `journalctl -u vault`

Vault tape la limite systemd de 200 MB — soit la charge a augmenté (plus de
clients), soit un memory leak. Augmenter temporairement dans
`/etc/systemd/system/vault.service.d/override.conf` puis investiguer.

## Références

- Page wiki stratégique : [[Vault ‐ Secrets Management]]
- Architecture détaillée : [`docs/secret-management/architecture.md`](architecture.md)
- Bootstrap : [`docs/secret-management/bootstrap.md`](bootstrap.md)
- Politique d'accès : [`docs/secret-management/access-policy.md`](access-policy.md)
- Rotation : [`docs/secret-management/rotation.md`](rotation.md)
- Disaster Recovery : [`docs/secret-management/disaster-recovery.md`](disaster-recovery.md)
- Code Ansible : [`ansible/roles/vault/`](../../ansible/roles/vault/)
- Policies HCL : [`policies/`](../../policies/)
- HashiCorp Vault docs : <https://developer.hashicorp.com/vault/docs>
