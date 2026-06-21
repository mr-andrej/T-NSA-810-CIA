# group_vars/all/

`vars.yaml` contient les variables non sensibles (endpoints Proxmox, adresse
Vault, role_id AppRole de la collection `community.hashi_vault`).

**Plus aucun secret dans ce répertoire.** Tous les secrets sont stockés dans
HashiCorp Vault sur s2_mt. Voir `docs/secret-management/bootstrap.md` pour
l'initialisation et `docs/secret-management/access-policy.md` pour les accès.

Chaque opérateur doit avoir localement :

- `~/.ansible/vault-ca.crt` — la CA interne qui signe le certificat TLS de
  Vault (fetchée depuis s2_mt au bootstrap).
- `~/.ansible/vault-secret-id` — le `secret_id` AppRole d'Ansible, distribué
  hors-bande.
