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
