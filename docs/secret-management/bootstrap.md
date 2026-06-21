# Bootstrap — Initialisation Vault (one-shot)

Procédure à exécuter une seule fois, par un admin avec accès SSH à s2_mt via le
bastion. À chaque étape, les sorties contenant des secrets doivent être
**enregistrées hors-bande** (gestionnaire de mots de passe, papier, etc.) et
**jamais committées**.

## Pré-requis

- Snapshot Proxmox de s2_mt avant tout changement :
  ```bash
  cd ansible
  make snap.create.site2.mt SNAP=pre-vault-install
  ```
- Token NetBox compromis (`16595d4...`) **déjà rotaté** via l'UI NetBox
  (`http://192.168.20.1`). Le nouveau token sera saisi à l'étape de
  peuplement — ne pas l'écrire en clair entre temps.
- Le repo cloné en local, branche `62-secret-management`.
- Anciennes valeurs de `vault.yaml` (ansible-vault) en main pour le
  peuplement initial des secrets.

## Étape 1 — Déployer Vault sur s2_mt

Depuis votre poste, à la racine du repo :

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/vault.yaml
```

Cela installe le paquet Vault, génère la CA interne + cert serveur, déploie
`vault.hcl`, démarre le service, et fetch la CA cert dans `ansible/files/vault-ca.crt`.

Vérifier sur s2_mt :

```bash
ssh s2-mt
sudo systemctl status vault
ss -tlnp | grep 8200
```

## Étape 2 — Distribuer la CA cert

Sur votre poste :

```bash
mkdir -p ~/.ansible
cp ansible/files/vault-ca.crt ~/.ansible/vault-ca.crt
```

Distribuer `vault-ca.crt` aux 4 autres membres de l'équipe (par n'importe
quel canal — la CA est publique par construction). Chacun la place dans son
propre `~/.ansible/vault-ca.crt`.

## Étape 3 — Initialiser Vault

Depuis le bastion, sur s2_mt :

```bash
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/vault.d/tls/ca.crt

vault operator init -key-shares=5 -key-threshold=3
```

**Sortie critique** — 5 clés Shamir + 1 root token. Exemple :

```
Unseal Key 1: <REDACTED>
Unseal Key 2: <REDACTED>
Unseal Key 3: <REDACTED>
Unseal Key 4: <REDACTED>
Unseal Key 5: <REDACTED>

Initial Root Token: <REDACTED>
```

**Actions immédiates :**

1. **Distribuer une clé à chaque membre de l'équipe (hors-bande)**. Personne
   ne doit posséder 2 clés.
2. Conserver le root token temporairement (étapes 4–8) — il sera **révoqué**
   à l'étape 8.
3. **Ne jamais committer ces valeurs**.

## Étape 4 — Unseal initial

3 membres unseal en parallèle :

```bash
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
```

`vault status` → `Sealed: false`.

## Étape 5 — Configurer Vault avec le root token

```bash
export VAULT_TOKEN=<root-token>

# Activer KV v2
vault secrets enable -path=secret kv-v2

# Charger les policies
for f in /path/to/repo/policies/*.hcl; do
  name=$(basename "$f" .hcl)
  vault policy write "$name" "$f"
done

# Activer audit log
sudo install -o vault -g vault -m 0750 -d /var/log/vault
vault audit enable file file_path=/var/log/vault/audit.log

# AppRole
vault auth enable approle
vault write auth/approle/role/ansible-deploy \
    token_policies=ansible-deploy,ansible-netbox \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

# Récupérer role_id et secret_id
ROLE_ID=$(vault read -field=role_id auth/approle/role/ansible-deploy/role-id)
SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id)

echo "ROLE_ID  = $ROLE_ID"
echo "SECRET_ID = $SECRET_ID  # à distribuer hors-bande aux opérateurs"
```

- Coller **ROLE_ID** dans `ansible/group_vars/all/vars.yaml` (variable
  `vault_role_id`) — c'est public, peut être commité.
- Distribuer **SECRET_ID** hors-bande aux 5 opérateurs. Chacun :
  ```bash
  echo -n "<secret-id>" > ~/.ansible/vault-secret-id
  chmod 600 ~/.ansible/vault-secret-id
  ```

## Étape 6 — Comptes admins humains (userpass)

```bash
vault auth enable userpass

for user in lucas paul andrej <autre1> <autre2>; do
  vault write auth/userpass/users/$user \
      password=<mot-de-passe-initial-à-changer-au-1er-login> \
      policies=admin-ops
done
```

Distribuer les mots de passe initiaux aux membres concernés. Chacun se logue
puis change son mot de passe :

```bash
vault login -method=userpass username=lucas
vault write auth/userpass/users/lucas/password password=<nouveau>
```

## Étape 7 — Peupler les secrets

Préparer un fichier `~/.config/tnsa/vault-secrets.env` (gitignored, jamais
sur le repo) avec toutes les valeurs — voir l'en-tête de
`scripts/vault-populate.sh` pour la liste complète des variables.

```bash
source ~/.config/tnsa/vault-secrets.env
export VAULT_TOKEN=$(vault login -token-only -method=userpass username=lucas)
bash scripts/vault-populate.sh
vault kv list secret/
```

Sorties attendues : un secret par ligne pour chaque path peuplé.

## Étape 8 — Révoquer le root token

```bash
vault token revoke <root-token-original>
```

À partir de maintenant, plus aucun accès "root" — tout passe par userpass
(humains) ou AppRole (Ansible).

## Étape 9 — Vérification

```bash
# Côté opérateur : test d'authentification AppRole
ansible-playbook playbooks/netbox.yaml --check

# Vérifier qu'il n'y a plus aucun secret en clair dans le repo
grep -rEi "(password|token|secret).*[:=].*['\"][a-zA-Z0-9]{20,}" ansible/ scripts/ policies/
```

Aucun résultat → bootstrap réussi.
