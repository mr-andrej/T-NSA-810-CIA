# Clés Shamir — Distribution et usage

Doc à destination des 5 membres de l'équipe qui reçoivent une clé Shamir
Vault. À lire une fois, puis garder sous la main.

## C'est quoi, une clé Shamir

Vault chiffre tous les secrets avec une **clé maître** unique. Si on la
stocke en clair quelque part, n'importe qui qui y accède peut tout lire.
Si on la perd, on perd tous les secrets définitivement.

Le **Shamir Secret Sharing** résout ce dilemme : on découpe la clé maître
en *N* parts dont seules *K* sont nécessaires pour la reconstruire. Ici on
a choisi **3-of-5** :

- **5 parts** sont générées à l'init de Vault (1 par membre de l'équipe).
- Il en faut **3 sur 5** pour déverrouiller Vault après un reboot.
- Avec moins de 3 parts → mathématiquement impossible de reconstruire la
  clé maître. Aucune attaque par brute force ne marche.

C'est exactement le principe des coffres-forts à plusieurs clés
physiques : il faut plusieurs personnes pour ouvrir.

## Pourquoi 3-of-5 (et pas 1-of-1 ou 5-of-5)

| Schéma | Tolérance perte | Tolérance compromission | Choisi ? |
| --- | --- | --- | --- |
| 1-of-1 (clé unique) | 0 — si je perds ma clé, Vault perdu à jamais | 0 — si on me la vole, tout est ouvert | ❌ |
| 5-of-5 (toutes obligatoires) | 0 — si 1 perd la sienne, Vault perdu | 5 personnes à compromettre | ❌ |
| **3-of-5** | **On peut perdre 2 clés** et continuer à fonctionner | **L'attaquant doit compromettre 3 personnes différentes** | ✅ |

3-of-5 est le sweet spot pour une équipe de 5 : robuste à la perte (2
membres peuvent être absents/indisponibles), robuste à la compromission
(il faut 3 personnes ciblées simultanément).

## Quand on a besoin de ta clé

Tu sors ta clé Shamir uniquement dans **un seul scénario** :

> **Vault est sealed et 3 membres doivent fournir leur clé pour
> l'unseal.**

Ça arrive principalement après :

- Un **reboot de s2_mt** (mise à jour OS, maintenance Proxmox, OOM kill).
- Une **restauration depuis snapshot** Vault.
- Un **rekey** planifié (regen des 5 clés).

Concrètement, Lucas (ou un autre admin) ping dans Signal :

> "Vault sealed, j'ai besoin de 2 autres clés Shamir pour unseal. Qui est dispo ?"

Tu réponds, tu te logues sur s2_mt via bastion :
```bash
ssh bastion
ssh s2-mt
export VAULT_ADDR=https://192.168.20.1:8200
export VAULT_CACERT=/etc/ssl/certs/vault-ca.crt
vault status     # Sealed: true
vault operator unseal <ta-clé>
```

Une fois que 3 membres ont fait ça (dans l'ordre quelconque), Vault est
unsealed et tout reprend.

**Pas besoin de coordination en temps réel** — chaque membre peut unseal
quand il veut, le compteur progresse jusqu'à 3.

## Ce que tu fais avec ta clé MAINTENANT

1. **Reçois ta clé** (Signal de Lucas, voir message ci-dessous).
2. **Stocke-la dans un endroit où toi seul peut accéder** :
   - Gestionnaire de mots de passe (1Password, Bitwarden, KeePass…) → entrée dédiée "Vault Shamir Key — T-NSA-810-CIA"
   - Ou note papier dans un endroit physique sûr (coffre, classeur perso)
3. **Ne JAMAIS** :
   - Coller la clé dans Slack, Discord, email
   - La mettre dans le repo (gitignored ou non — pas dans le repo, point)
   - La partager avec un autre membre (chacun a SA clé, c'est ça qui fait la sécurité)
   - L'envoyer à une AI comme ChatGPT/Claude (ces logs sont stockés)
4. **Accuse réception à Lucas** en Signal : "OK reçu, stockée."

## Si tu perds ta clé

Préviens **immédiatement** Lucas en Signal. Pas de panique : avec 3-of-5
on peut en perdre 2 et continuer. Mais on doit refaire la distribution
pour rester à 5 clés disponibles → procédure `vault operator rekey` (voir
[disaster-recovery.md](disaster-recovery.md) scénario 2).

Plus on attend, plus c'est risqué : si une 3e clé est perdue avant le
rekey, **Vault est perdu définitivement** (tous les secrets chiffrés
deviennent irrécupérables).

## Si ton poste est compromis

Si tu soupçonnes que ta clé a fuité (laptop volé, malware, …) :

1. Préviens Lucas en Signal **immédiatement**.
2. Lucas déclenche un `vault operator rekey` qui invalide les 5 clés
   actuelles et en génère 5 nouvelles.
3. Re-distribution complète. Ton ancienne clé compromise ne sert plus à
   rien.

## Template de message Signal à envoyer aux 4 autres membres

Lucas, copie-colle ce template pour chacun (en remplaçant `<clé-N>` par
la clé attribuée à cette personne) :

```
Salut,

Voici TA clé Shamir Vault (1 sur 5) pour le projet T-NSA-810-CIA :

<clé-N>

Ce que ça veut dire :
- Vault est notre coffre-fort de secrets infra. Pour le déverrouiller
  après un reboot, il faut 3 personnes qui combinent leur clé.
- Tu es 1 des 5 détenteurs. Chacun a une clé différente.
- Quand on aura besoin de toi (Signal "Vault sealed, faut unseal"),
  tu te connecteras à s2_mt via bastion et tu lanceras :
    vault operator unseal <ta-clé>

Ce que tu dois faire MAINTENANT :
1. Stocke cette clé dans ton password manager (entrée dédiée
   "Vault Shamir Key — T-NSA-810-CIA").
2. Supprime ce message Signal après l'avoir stockée.
3. Réponds-moi "OK reçu, stockée".

Ne partage JAMAIS cette clé. Si tu la perds ou si ton poste est
compromis, ping-moi immédiatement, on rekey.

Doc complète : docs/secret-management/shamir-keys.md
```

## Référence rapide

| Quoi | Combien | Source |
| --- | --- | --- |
| Total de clés | 5 | générées à `vault operator init` |
| Clés nécessaires pour unseal | 3 | seuil Shamir |
| Détenteurs | 5 membres équipe, 1 chacun | distribution hors-bande |
| Endroit où Vault attend les clés | `vault operator unseal` sur s2_mt | une à une |
| Doc DR (rekey, perte de clés) | [`disaster-recovery.md`](disaster-recovery.md) | scénarios 2 et 4 |
| Doc principale Vault | [`wiki-page-Vault-Implementation.md`](wiki-page-Vault-Implementation.md) | référence ops |
