# Phase 1 — Constats de l'audit n°1 (2026-11-07)

**Cible auditée :** le conteneur d'exécution de l'agent Hermes sur Hostinger — **pas un VPS**.
Exécuté par Hermes en utilisateur non privilégié (uid 337, sans sudo), en mode dégradé.
Intégrité du script vérifiée : SHA-256 `2250db2f…1a3e2ac9`, 138 lignes (identique au dépôt).

## Ce qui est établi
| Élément | Valeur | Interprétation |
|---|---|---|
| Matériel visible | AMD EPYC 9354P, 64 vCPU, 503 Gio RAM, 14 Tio disque | Machine physique **partagée** entre clients, pas vos ressources |
| Mémoire hôte | 445 Gio utilisés, 825 Gio de swap consommés | Hôte saturé, performances imprévisibles |
| Charge | ~17,6 / 64 cœurs | Hôte actif en permanence |
| OS | Debian 13 (trixie), noyau 6.12 | Celui de l'hôte |
| Volume persistant | `/data` = 25 Gio (11 % utilisés) | Seul stockage qui vous appartient |
| Processus | gateway Hermes, server.py, MCP Hostinger, superviseur — ~800 Mo RSS | Environnement géré |
| Absents | systemd, Docker, ip/ss, pare-feu, SSH, serveur web, sudo | Impossible d'y déployer l'architecture SIO prévue |

## Conclusion
Cet environnement **ne peut pas héberger SIO** : pas de Docker, pas de droits root,
pas de ports entrants, pas de PostgreSQL en service, ressources partagées non garanties.

## Décision requise
1. Vérifier dans hPanel s'il existe une offre **VPS (KVM)** distincte.
   - Oui → relancer l'audit sur ce VPS (terminal navigateur hPanel, en root).
   - Non → choisir un VPS (achat soumis à approbation, voir réponse dans la conversation).
2. Hermes peut rester l'assistant d'administration, et rejoindre le VPS par SSH une fois celui-ci prêt.

---

# Audit n°2 (2026-11-08) — lancé depuis le « Hermes CLI » de hPanel

Résultat : **même environnement que l'audit n°1** (conteneur Hermes, pas un VPS).
Preuves : invite `Hermes CLI`, shell restreint `lshell`, uid 337 sans sudo, PID 1 = `tini -- /app/u4s-hermes-agent`,
marqueur `/.dockerenv`, ni systemd ni SSH ni Docker. Le fichier contient deux exécutions (00:07 et 00:12 UTC), identiques.

## Limites réelles mesurées (cgroup v2) — nouvelles
| Ressource | Limite | Utilisé |
|---|---|---|
| RAM | 4 Gio (`memory.max`) | ~0,78 Gio (Hermes) |
| Swap | 4 Gio | ~0,1–0,2 Gio |
| CPU | 2 vCPU (`cpu.max 200000/100000`) | faible |
| Processus | 512 max | ~15 |
| Disque persistant | `/data` 25 Gio | 2,6 Gio |
| Réseau sortant | OK (Telegram, RSS BBC = 200) ; IP sortante variable dans un pool partagé | — |
| Réseau entrant | aucun port visible / non configurable | — |
| Outils | Python 3.14, pip, Node 22, git | pas de PostgreSQL, pas de serveur web |

## Conclusion
Le terminal hPanel ouvert est celui du produit géré Hermes. Il faut confirmer dans hPanel
si un VPS KVM classique (accès root, OS choisi) existe réellement.
