# Digest du wiki GitHub T-NSA-810-CIA — vu sous l'angle Secret Management

Référence offline du contenu pertinent du wiki, capturée le 2026-06-20 pour
documenter la décision d'architecture de l'Epic #62. Pages d'origine :
<https://github.com/mr-andrej/T-NSA-810-CIA/wiki>.

## Pages lues

- Home
- Context
- Architecture Overview
- **Vault ‐ Secrets Management** (la cible)
- Rebuild Runbook ‐ Full Infrastructure Reconstruction Guide
- Technical Risks
- Repository Strategy
- Infrastructure as code tools
- JUNKyard
- _Sidebar

## Stratégie Vault (page dédiée du wiki)

- **Modèle de déploiement** : HashiCorp Vault auto-hébergé sur une "dedicated
  service VM" sur le Site 2 (remote/cloud). Centralise tous les secrets pour
  les deux sites.
- **Pourquoi Site 2** : Site 2 héberge déjà les services partagés (JUNKyard,
  NetBox), centralisation = exposition réduite côté on-prem, scalabilité
  future.
- **Réseau** : exposition HTTPS interne uniquement. Accès depuis bastion +
  VMs de service autorisées. Pas d'exposition WAN. TLS systématique. Audit
  log Vault activé.
- **Auth** : modèle machine-oriented.
  - Humains : tokens temporaires émis via le bastion.
  - Services : AppRole (role_id + secret_id), credentials short-lived.
- **Autorisation** : policies fine-grained, principe du moindre privilège,
  TTLs définis.
- **Intégrations attendues** :
  - VPN : stockage des clés privées et certificats.
  - NetBox : tokens API stockés en sécurité.
  - Applications : récupération runtime des secrets via API.
  - Automation / IaC : secrets injectés à l'exécution, jamais stockés
    dans le repo.
- **Sécurité** : data chiffrée, unsealing géré explicitement, accès
  auditable, secrets révocables/rotables sans redéploiement.
- **Résumé wiki** : "Vault separates authentication (who you are) from
  authorization (what you can do). Human administrators access Vault through
  the bastion host and use temporary tokens. Services authenticate using
  AppRole, which provides a dedicated machine identity with limited
  privileges."

## Adaptation locale (notre implémentation)

- **Co-localisation** sur s2_mt au lieu d'une VM dédiée → contrainte 3 VMs
  par site du sujet. Trade-off documenté dans `architecture.md`.
- **Storage backend** = `file` (et non Raft) → contrainte RAM (s2_mt à 2 GB
  partagés avec NetBox + JUNKyard).
- **UI Vault désactivée** + télémétrie off + `disable_mlock=true` →
  économie RAM.
- **Unseal Shamir 3-of-5** + 5 clés distribuées aux 5 membres → robustesse
  (perte de 2 clés tolérée) et impossibilité de unsealing par un seul
  individu.
- **Pas d'auto-unseal** (la solution `transit` aurait nécessité un second
  Vault, incompatible avec la contrainte 3 VMs).

## Architecture (Architecture Overview)

- Site 1 (10.0.0.0/8) : VLAN 10 Servers (10.0.10.0/24), VLAN 20 Database
  (10.0.20.0/24). Pas d'exposition WAN.
- Site 2 (192.168.0.0/16) : VLAN 10 DMZ/Bastion (192.168.10.0/24), VLAN 20
  Monitoring (192.168.20.0/24). Seul site exposé.
- VPN Admin clients (192.168.100.0/24) → uniquement bastion accessible.
- Tunnel inter-site OpenVPN (172.16.0.0/30, hub Site 2).
- s2_mt = VLAN 20, IP 192.168.20.1, héberge NetBox + JUNKyard. Reconnu
  comme **destination unique des logs centralisés**.
- Accès admin : Admin VPN (192.168.100.X) → pfSense Site 2 → Bastion
  (192.168.10.10) → tunnel → VMs Site 1.

## Risques (Technical Risks)

| ID | Risque | Niveau | Lien Secret Management |
| --- | --- | --- | --- |
| R-006 | VPN Certificate Expiration or Loss | Medium | Vault stocke certs et CA pour récupération. |
| R-010 | Bastion Host Compromise | High | Audit log Vault + AppRole rotation rapide atténuent. |
| R-019 | **Credential Management Complexity** | **High** | **Ce ticket — Vault est la mitigation directe.** |
| R-020 | Inadequate Documentation | Critical | Cette section `docs/secret-management/` couvre. |

## Rebuild Runbook

Ordre de build :
1. Proxmox hosts → 2. Site 2 core (s2_fw, s2_js, s2_mt) → 3. Site 1 core →
4. Connectivité → 5. Hardening → 6. Bastion → 7. JUNKyard → 8. NetBox → 9. App
→ 10. Validation.

**Vault doit s'insérer entre JUNKyard (7) et NetBox (8)** : NetBox dépend de
secrets stockés dans Vault (DB password, SECRET_KEY, superuser). Modifier le
runbook pour ajouter une phase 7 bis = "Vault deployment + bootstrap".

Le runbook attend pour la reconstruction : ISOs, IPs WAN, clés SSH. Ajouter à
ces prérequis : 3 clés Shamir disponibles + snapshot Vault récent.

## Repository Strategy (mono-repo)

- Mono-repo confirmé, mainline = `main`.
- Vault config (rôle Ansible, policies HCL, docs) vit donc dans le repo
  principal — `ansible/roles/vault/`, `policies/`, `docs/secret-management/`.
- Atomicité des commits respectée : ce PR commit ensemble la config infra,
  la doc et le refactor des playbooks.

## IaC Tools

- **Terraform** = provisioning (VMs, network, NetBox objects). Pas utilisé
  dans ce PR.
- **Ansible** = configuration. C'est là que Vault s'intègre.
- Collection `community.hashi_vault` à ajouter à `requirements.yml`. Fait.

## Questions laissées ouvertes par le wiki (et tranchées dans ce PR)

| Question | Décision |
| --- | --- |
| VM dédiée vs co-localisation | Co-localisation sur s2_mt (3-VM constraint) |
| Mécanisme d'unseal | Shamir manuel 3-of-5 (auto-unseal `transit` nécessiterait un 2e Vault) |
| Stockage des clés Shamir | Distribution hors-bande, 1 clé par membre |
| Politique de rotation | Définie par type dans `rotation.md` |
| Procédure certs VPN | Géré via UI pfSense ; Vault stocke une copie pour DR |
