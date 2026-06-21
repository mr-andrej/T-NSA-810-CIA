# Politique d'accès

## Qui a accès à quoi

| Rôle | Auth | Policies | Périmètre |
| --- | --- | --- | --- |
| Admin humain (Lucas, Paul, Andrej…) | `userpass` via bastion | `admin-ops` | Lecture/écriture de tous les secrets, gestion des policies et AppRole |
| Ansible (playbooks de l'équipe) | `approle` (`ansible-deploy`) | `ansible-deploy`, `ansible-netbox` | Lecture seule sur `secret/data/infra/*` et `secret/data/netbox/*` |
| Auditeur externe (revue de sécurité) | `userpass` éphémère | `audit-read` | Lecture des metadata d'audit, pas des secrets eux-mêmes |

## Granter un accès à un nouveau membre

1. Admin existant se logue : `vault login -method=userpass username=<admin>`
2. Créer le compte :
   ```bash
   vault write auth/userpass/users/<nouveau> \
       password=<mot-de-passe-initial> \
       policies=admin-ops
   ```
3. Envoyer le mot de passe initial au nouveau hors-bande.
4. Le nouveau se logue et change son mot de passe.
5. Lui transmettre 1 clé Shamir uniquement si on rebalance la distribution
   (sinon il dépendra des autres pour les opérations d'unseal — c'est OK pour
   un membre junior).

## Retirer un accès

1. Désactiver le compte userpass :
   ```bash
   vault delete auth/userpass/users/<partant>
   ```
2. Révoquer toutes ses sessions actives :
   ```bash
   vault token revoke -mode=path auth/userpass/<partant>
   ```
3. Si la personne détenait une clé Shamir → **regénérer toutes les clés
   Shamir** via `vault operator rekey` (procédure dans `disaster-recovery.md`).

## Rotation du `secret_id` AppRole

Par défaut le `secret_id` n'expire pas (`secret_id_ttl=0`). Pour le faire
tourner — par exemple si on suspecte qu'un poste opérateur est compromis :

```bash
vault login -method=userpass username=<admin>
NEW_SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/ansible-deploy/secret-id)
echo $NEW_SECRET_ID
```

Distribuer le nouveau `secret_id` hors-bande à tous les opérateurs ; ils
remplacent leur `~/.ansible/vault-secret-id`. Puis révoquer les anciens :

```bash
vault list auth/approle/role/ansible-deploy/secret-id
# Identifier les anciens secret_id_accessor et :
vault write auth/approle/role/ansible-deploy/secret-id-accessor/destroy \
    secret_id_accessor=<accessor>
```

## Principe du moindre privilège

- Aucun rôle Ansible ne reçoit `admin-ops` — la lecture suffit toujours.
- Les secrets sensibles (clés privées VPN, mots de passe pfSense) ne sont
  lus que par les humains. Si un jour Ansible doit y accéder, créer un
  nouvel AppRole dédié avec sa propre policy.
- Le compte `root` Vault est révoqué à la fin du bootstrap. Il n'existe
  plus de "super-admin" — toute action passe par un compte humain auditable.
