# Disaster Recovery — Vault

## Scénarios couverts

1. Reboot de s2_mt (Vault re-scellé)
2. Perte d'une clé Shamir
3. Restauration depuis snapshot
4. Reconstruction complète (s2_mt totalement perdu)

## Scénario 1 — Reboot de s2_mt

Vault redémarre **scellé** après chaque reboot. Les services NetBox et tout
playbook Ansible qui essaie de lire un secret vont échouer jusqu'au unseal.

**Procédure :**

```bash
ssh s2-mt   # via bastion
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/vault.d/tls/ca.crt

vault status   # Sealed: true
```

Coordonner 3 membres de l'équipe (Slack/Signal) :

```bash
# Membre 1
vault operator unseal <key-1>

# Membre 2
vault operator unseal <key-2>

# Membre 3
vault operator unseal <key-3>
```

Après la 3ème clé, `Sealed: false`. NetBox et les playbooks peuvent à
nouveau lire leurs secrets. **Aucun redémarrage de NetBox nécessaire** —
ses secrets sont lus à l'init Django et restent en mémoire ; seul un
redéploiement Ansible re-pingue Vault.

## Scénario 2 — Perte d'une clé Shamir

Avec 3-of-5, on peut perdre 2 clés et continuer à unseal. Mais il faut
**reconstituer la distribution** au plus vite : si on en perd une 3e, on
peut plus jamais ré-unseal.

**Procédure (`rekey`)** :

```bash
vault operator rekey -init -key-shares=5 -key-threshold=3
# Retourne un nonce + une PGP key request (non utilisée ici)
```

Les 3 membres qui détiennent encore une clé valide la fournissent :

```bash
vault operator rekey -nonce=<nonce> <key-1>
vault operator rekey -nonce=<nonce> <key-2>
vault operator rekey -nonce=<nonce> <key-3>
```

→ Vault sort **5 nouvelles clés**. Les anciennes sont invalidées. Re-distribuer
les nouvelles aux 5 membres (1 chacun, hors-bande). **Ne jamais conserver
les anciennes**.

## Scénario 3 — Restauration depuis snapshot

Les snapshots sont stockés dans `/home/administrator/junkyard/vault-snapshots/`,
rétention 14 jours. Chacun est un tarball de `/var/lib/vault/`.

**Cas d'usage :** corruption du backend `file` Vault, ou besoin de restaurer un
secret accidentellement détruit (rare — KV v2 versionne).

```bash
ssh s2-mt
sudo systemctl stop vault

# Lister
ls -lt /home/administrator/junkyard/vault-snapshots/

# Restaurer
SNAP=/home/administrator/junkyard/vault-snapshots/vault-20260620-033000.tar.gz
sudo tar -xzf "$SNAP" -C /
sudo chown -R vault:vault /var/lib/vault

sudo systemctl start vault
vault status   # Sealed: true → ré-unseal avec 3 clés Shamir
```

> Les clés Shamir restent valides à travers un restore : elles sont liées au
> *master key* qui est stocké dans le backend → restaurer le backend
> ramène le même état.

## Scénario 4 — Reconstruction complète (s2_mt perdu)

Hypothèses : s2_mt est complètement détruite. Vous avez :

- Au moins un snapshot Vault récent (`vault-*.tar.gz`) sauvegardé ailleurs.
- 3 des 5 clés Shamir disponibles.
- Le repo Git.

**Procédure :**

1. Reconstruire s2_mt en suivant le wiki *Rebuild Runbook* (Phase 2C +
   Phase 8 NetBox). Stop avant NetBox.
2. Déployer Vault :
   ```bash
   ansible-playbook playbooks/vault.yaml
   ```
3. **Arrêter Vault et restaurer le snapshot** :
   ```bash
   ssh s2-mt
   sudo systemctl stop vault
   sudo tar -xzf vault-LATEST.tar.gz -C /
   sudo chown -R vault:vault /var/lib/vault
   ```
4. Restaurer la CA et le cert TLS depuis le snapshot s'ils ne sont pas
   regénérables (si on a regénéré une nouvelle CA, les clients devront
   redistribuer `vault-ca.crt`).
5. Redémarrer :
   ```bash
   sudo systemctl start vault
   vault status   # Sealed
   ```
6. Unseal avec 3 clés Shamir.
7. Redéployer NetBox et le reste :
   ```bash
   ansible-playbook playbooks/netbox.yaml
   ansible-playbook playbooks/managed_vms.yaml
   ```

## Scénario 4 bis — Vault perdu **avec** clés Shamir perdues

C'est le scénario catastrophe : Vault ET les clés sont perdus. **Aucune
récupération possible**. Le secret matériel est définitivement chiffré.

**Mitigation pré-incident :**

- Distribution forte des clés Shamir (5 personnes différentes, lieux
  différents).
- Sauvegarde des clés Shamir dans un coffre physique (papier, scellé).
- Documenter qui détient quelle clé, à jour à chaque changement
  d'équipe.

**Remédiation post-incident :** rebuild from scratch — chaque secret doit être
regénéré (nouveaux tokens NetBox, nouveaux mots de passe DB, nouveaux certs
VPN). Le wiki *Rebuild Runbook* couvre la procédure infra.

## Test régulier

Tester le scénario 1 (unseal manuel) **au moins une fois par semestre**.
Idéalement à chaque follow-up du projet, pour s'assurer que la distribution
des clés est encore opérationnelle.

```bash
ssh s2-mt
sudo systemctl restart vault
vault status   # devrait être Sealed
# coordonner les 3 membres pour ré-unseal
```
