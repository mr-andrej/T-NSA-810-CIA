# Secret Management — Architecture

## Décision

Tous les secrets de l'infrastructure (tokens API, mots de passe, clés SSH,
certificats VPN) sont stockés dans **HashiCorp Vault**, auto-hébergé sur la VM
**s2_mt** (`192.168.20.1`). Plus aucun secret en clair ni chiffré
(`ansible-vault`) dans le repo.

### Pourquoi Vault ?

- Demande explicite du ticket Epic #62 et de la page wiki *Vault ‐ Secrets
  Management*.
- Mitigation directe du risque **R-019** (Credential Management Complexity).
- Audit log natif — chaque lecture/écriture de secret est tracée.
- Rotation et révocation possibles sans toucher au code.
- Policies fine-grained — moindre privilège par rôle (Ansible vs admin
  humain).
- AppRole permet l'automatisation sans `--ask-vault-pass` interactif.

### Pourquoi sur s2_mt et pas sur une VM dédiée ?

Le wiki parle d'une *dedicated service VM*. Contrainte du sujet : **maximum
3 VMs par site**. Sur Site 2 ces 3 VMs sont déjà allouées (s2_fw, s2_js,
s2_mt). Vault est donc co-localisé sur s2_mt qui héberge déjà NetBox et
JUNKyard. Trade-offs assumés :

- Surface d'attaque concentrée sur s2_mt → mitigé par la segmentation
  VLAN 20 (Monitoring) et l'accès via bastion uniquement.
- RAM partagée → bornée par `MemoryMax=200M` sur le service systemd Vault.

## Contraintes ressources

s2_mt à l'installation : 2 GB RAM, ~870 MB utilisés (NetBox, gunicorn,
Redis), ~300 MB libres, ~1 GB buff/cache, 591 MB de swap déjà consommé.
**La RAM ne peut pas être augmentée.**

Configuration Vault choisie pour rester dans l'enveloppe :

| Paramètre | Valeur | Justification |
| --- | --- | --- |
| Storage backend | `file` | Plus léger que Raft, suffisant pour un single-node |
| `disable_mlock` | `true` | Le swap est actif, mlock impossible |
| `ui` | `false` | Économise ~20 MB ; ops via CLI uniquement |
| Telemetry | désactivée | Inutile, économise quelques MB |
| `MemoryMax` systemd | `200M` | Borne dure |
| `MemorySwapMax` systemd | `100M` | Borne dure swap |
| Audit log rotation | 7 jours | Évite que le disque sature |

Cible : Vault ~120 MB RSS en régime de croisière.

## Topologie réseau

```
       Admin VPN client                Bastion (s2_js)
       (192.168.100.0/24)              (192.168.10.10)
              │                                │
              │                                │ ProxyJump SSH
              ▼                                ▼
        ┌──────────────┐                ┌──────────────┐
        │   s2_fw      │ pfSense        │   s2_mt      │
        │ 192.168.X.X  ├───────────────►│ 192.168.20.1 │
        └──────────────┘    8200/tcp    │              │
                                        │  Vault       │
                                        │  NetBox      │
                                        │  JUNKyard    │
                                        └──────────────┘
```

Vault écoute en HTTPS sur `192.168.20.1:8200`, n'est **pas** exposé en WAN.

## Règles firewall (à appliquer sur s2_fw via UI pfSense)

S2-FW n'est pas encore géré par Ansible. À ajouter manuellement (Firewall →
Rules → respective interface) :

**OPT1 (VLAN 10 — DMZ/Bastion)**

| Source | Destination | Port | Description |
| --- | --- | --- | --- |
| `192.168.10.0/24` | `192.168.20.1/32` | `8200/tcp` | Vault — admin via bastion |

**OPT2 (VLAN 20 — Monitoring)**

Aucune règle nouvelle nécessaire : Vault et ses consommateurs (NetBox,
playbooks lancés depuis s2_mt si applicable) sont sur le même VLAN.

**OpenVPN (Admin VPN clients vers Vault)**

| Source | Destination | Port | Description |
| --- | --- | --- | --- |
| `192.168.100.0/24` | `192.168.20.1/32` | `8200/tcp` | Vault — admins via VPN |

**WAN** : aucun changement. Vault n'est jamais exposé sur Internet.

## Auth methods Vault

| Méthode | Pour | Workflow |
| --- | --- | --- |
| `token` (root) | Bootstrap uniquement | Révoqué après init. Ne sert plus jamais. |
| `approle` | Ansible (CI / opérateurs) | `role_id` dans `vars.yaml`, `secret_id` dans `~/.ansible/vault-secret-id` |
| `userpass` | Humains | Login via CLI Vault depuis le bastion pour ops manuelles |

## Policies

Versionnées dans `policies/` à la racine du repo :

- `ansible-deploy.hcl` — read sur `secret/data/infra/*`
- `ansible-netbox.hcl` — read sur `secret/data/netbox/*`
- `admin-ops.hcl` — read/write complet sur `secret/data/*` + gestion policies/auth
- `audit-read.hcl` — lecture seule des metadata audit

## Structure des secrets (KV v2 mount `secret/`)

```
secret/infra/proxmox/site1         {api_user, api_token_id, api_token_secret}
secret/infra/proxmox/site2         {api_user, api_token_id, api_token_secret}
secret/infra/ssh/admins/lucas      {public_key}
secret/infra/ssh/admins/paul       {public_key}
secret/infra/ssh/admins/andrej     {public_key}
secret/infra/ssh/bastion           {private_key, public_key}
secret/netbox/db                   {password}
secret/netbox/django               {secret_key}
secret/netbox/superuser            {password}
secret/netbox/api                  {token}
secret/vpn/site2-ca                {cert, key}
secret/vpn/s2s-site1-client        {cert, key, tls_auth}
secret/firewall/pfsense/site1      {admin_password}
secret/firewall/pfsense/site2      {admin_password}
```

## Sauvegardes

Snapshot tarball quotidien à 03h30 → `/home/administrator/junkyard/vault-snapshots/`,
rétention 14 jours. Les snapshots **ne contiennent pas** les clés Shamir : un
snapshot seul ne permet pas de déverrouiller Vault — il faut combiner snapshot
+ 3 clés Shamir.

## Unseal

Shamir 3-of-5. 5 clés générées à l'init, **distribuées hors-bande** aux 5
membres de l'équipe (1 clé chacun). Après chaque reboot s2_mt, 3 membres
doivent fournir leur clé pour ré-unseal. Voir `disaster-recovery.md`.
