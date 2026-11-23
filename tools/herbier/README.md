# Herbier d'idées

Outil de collecte et d'organisation de notes, idées, articles, citations, tâches et images.

- **Page en ligne (privée)** : https://claude.ai/artifact/LYV8g49dTJCtET9GPuKv2P
- **Source** : `herbier.html` (page autonome, publiée comme Artifact claude.ai)

## Fonctions
- **Collecte** : texte collé, lien, fichier texte (.txt/.md/.csv/.json), image (bouton, glisser-déposer ou Ctrl+V).
- **Analyse automatique** (Claude) : titre, type, catégorie, sujets, mots-clés, résumé, suggestions ; lecture du texte des images.
- **Organisation** : regroupement par catégorie, filtres par type et sujet, recherche plein texte, édition manuelle.
- **Réorganiser les catégories** : Claude relit toutes les fiches et propose une taxonomie ; rien n'est appliqué sans validation.
- **Synthèses & suggestions** : synthèse, pistes et idées, plan d'action, connexions entre fiches, brief d'une page — sur tout l'herbier, une catégorie, un type ou un sujet. Enregistrables et exportables en Markdown.
- **Export** complet en Markdown.

## Stockage
Les fiches sont enregistrées dans l'espace privé de l'utilisateur connecté (capability `db`, chemin `data/users/<id>`), invisible des autres personnes, propriétaire compris.
Hors claude.ai, la page fonctionne en mode local (navigateur) avec un classement simple par mots-clés.
