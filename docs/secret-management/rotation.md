# Rotation des secrets

Vault n'impose pas de TTL sur les KV — la rotation est manuelle et
planifiée. Cette doc décrit la procédure par type de secret.

## Calendrier recommandé

| Secret | Fréquence | Déclencheur ad-hoc |
| --- | --- | --- |
| AppRole `secret_id` Ansible | 90 jours | Départ d'un opérateur, poste compromis |
| Token API NetBox | 180 jours | Fuite, départ |
| Mot de passe NetBox superuser | 365 jours | Départ admin |
| Mot de passe DB NetBox | 365 jours | Fuite |
| `SECRET_KEY` Django NetBox | 730 jours (long, rotation = invalidation des sessions) | Compromission |
| Tokens API Proxmox | 365 jours | Départ admin |
| Certificats CA OpenVPN | 5 ans (cf wiki) | Perte de la CA |
| Cert client OpenVPN site-à-site | 1 an (`lifetime: 398j` dans le wiki) | Avant expiration |
| Mots de passe admin pfSense | 365 jours | Départ |
| Clés SSH admins | 365 jours ou à la demande | Perte/fuite |
| Cert TLS Vault | 825 jours (généré par le rôle) | Avant expiration |
| CA TLS Vault | 3650 jours | Compromission |

## Procédure générique

1. Générer la nouvelle valeur.
2. La mettre dans Vault : `vault kv put secret/<path> <key>=<new-value>`.
   KV v2 conserve l'ancienne version (rollback possible).
3. Tester avec un playbook concerné : `ansible-playbook playbooks/<...>.yaml --check`.
4. Sur le système destinataire (NetBox, pfSense…), basculer pour utiliser
   la nouvelle valeur.
5. Une fois validé, détruire les anciennes versions :
   ```bash
   vault kv metadata delete secret/<path>     # détruit toutes les versions
   # OU plus granulaire :
   vault kv destroy -versions=1,2 secret/<path>
   ```

## Cas spécifiques

### Token API NetBox

```bash
# 1. Générer un nouveau token dans l'UI NetBox (Admin → API Tokens → Add)
# 2. Stocker dans Vault
vault kv put secret/netbox/api token=<nouveau>
# 3. Tester
ansible-playbook playbooks/netbox_sync.yaml --check
# 4. Révoquer l'ancien token dans l'UI NetBox
```

### Mot de passe DB NetBox

Plus délicat : NetBox lit le mot de passe à l'init Postgres et le tape dans
`configuration.py`. Rotation = redéploiement du rôle `netbox`.

```bash
# 1. Générer
NEW=$(openssl rand -base64 32)
# 2. Stocker dans Vault
vault kv put secret/netbox/db password="$NEW"
# 3. Sur s2_mt, mettre à jour le mot de passe Postgres
sudo -u postgres psql -c "ALTER USER netbox WITH PASSWORD '$NEW';"
# 4. Redéployer NetBox (template configuration.py re-rendu avec nouvelle valeur)
ansible-playbook playbooks/netbox.yaml
# 5. Redémarrer netbox.service + netbox-rq.service (handlers du rôle)
```

### `SECRET_KEY` Django

**Attention** : changer cette clé invalide toutes les sessions utilisateur
NetBox et tous les CSRF tokens. À faire en heure creuse.

```bash
NEW=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
vault kv put secret/netbox/django secret_key="$NEW"
ansible-playbook playbooks/netbox.yaml
```

### Tokens API Proxmox

Tokens créés dans l'UI Proxmox (Datacenter → Permissions → API Tokens). Pour
chaque site :

```bash
# 1. Dans l'UI Proxmox, créer un nouveau token sur GR37@pve!ansible
#    avec privilège-separation OFF, copier le secret affiché.
# 2. Stocker dans Vault
vault kv put secret/infra/proxmox/site1 \
    api_user=GR37@pve api_token_id=ansible api_token_secret=<nouveau>
# 3. Tester
make snap.create.site1.fw SNAP=test-rotation
# 4. Supprimer l'ancien token dans l'UI Proxmox
```

### Cert client OpenVPN site-à-site

Annuellement avant expiration :

```bash
# 1. Dans l'UI pfSense Site 2 : System → Cert. Manager → générer un nouveau
#    cert client `s2s-site1-client` signé par la CA `site2-vpn-ca`.
# 2. Exporter cert + key + tls-auth.
# 3. Stocker dans Vault
vault kv put secret/vpn/s2s-site1-client \
    cert=@s2s-site1-client.crt \
    key=@s2s-site1-client.key \
    tls_auth=@s2s-tls-auth.key
# 4. Dans l'UI pfSense Site 1 : remplacer le cert sur le client OpenVPN.
# 5. Tester le tunnel : ping 172.16.0.1 depuis S1-FW.
# 6. Révoquer l'ancien cert dans l'UI Site 2.
```

### Cert TLS Vault

Avant expiration (825 jours après l'install) :

```bash
ansible-playbook playbooks/vault.yaml --tags tls
# Le handler "Restart Vault" se déclenche → resealing automatique
# → 3 membres doivent ré-unseal.
```

### CA TLS interne (Vault)

3650 jours. Très rare. Si compromission, il faut tout regénérer + redistribuer
le nouveau `vault-ca.crt` à tous les opérateurs. Procédure complète dans
`disaster-recovery.md`.

### Clé SSH admin

L'admin génère une nouvelle paire sur son poste, distribue la nouvelle clé
publique, puis :

```bash
vault kv put secret/infra/ssh/admins/<nom> public_key="ssh-ed25519 AAAA..."
ansible-playbook playbooks/bastion.yaml
ansible-playbook playbooks/managed_vms.yaml
```

L'ancienne clé est automatiquement remplacée par le rôle `bastion` (qui
remplace `authorized_keys`, ne fait pas d'append).

### Mots de passe admin pfSense

Changés via l'UI pfSense, puis :

```bash
vault kv put secret/firewall/pfsense/site1 admin_password=<nouveau>
vault kv put secret/firewall/pfsense/site2 admin_password=<nouveau>
```

Ces secrets ne sont consommés par aucun playbook automatisé pour l'instant
— ils sont stockés pour disaster recovery.
