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

## Sources d'import
- **Galerie photos** : sélection de une ou plusieurs photos du téléphone (plusieurs photos = une fiche par photo, avec aperçu).
- **Appareil photo** : prise de vue directe (tableau blanc, page de livre, affiche… le texte est lu par Claude).
- **Fichiers** : images, textes, flux RSS/Atom, JSON.
- **Coller** : texte ou image collés dans la zone de saisie.
- **Drive, Gmail, Notion** : recherche dans vos connecteurs claude.ai (Google Drive : documents, PDF, présentations… ; Gmail : syntaxe de recherche Gmail ; Notion : pages). Le contenu complet n'est lu qu'à l'import des éléments cochés. Chaque service demande votre autorisation à la première utilisation.

## Import en lot
- Bouton **Import en lot** : collez plusieurs notes séparées par une ligne `---`, ou choisissez plusieurs fichiers.
- Formats acceptés : images, `.txt`/`.md` (une fiche par fichier), flux RSS/Atom (`.xml`, `.rss`, `.atom`), JSON (`herbier-import.json` ou tableau d'objets `{title, text, url, source}`).
- Aperçu avant import : chaque élément peut être coché ou décoché ; les liens déjà présents dans l'herbier sont décochés d'office.
- Les fiches importées sont marquées « en attente » ; Claude les classe par lots de 12 (bouton **Analyser N fiche(s) en attente**, arrêt possible à tout moment).
- Filtre **Sources** dans la colonne de gauche pour retrouver les fiches d'un flux.

## Relier les flux RSS de SIO
La page publiée ne peut pas télécharger de flux elle-même (réseau bloqué par claude.ai). Le script
`scripts/tools/rss_to_herbier.py` (Python 3, bibliothèque standard) lit `config/sources_candidates.psv`,
télécharge les flux et écrit un fichier à importer dans l'Herbier :

```bash
python3 scripts/tools/rss_to_herbier.py                                   # dernières 24 h
python3 scripts/tools/rss_to_herbier.py --since-hours 72 --region mena --max-per-feed 10 -o veille.json
python3 scripts/tools/rss_to_herbier.py --keyword maroc --keyword sahel
```

Lancez-le là où les flux sont joignables (conteneur Hermes de SIO ou votre ordinateur), puis glissez le
fichier `.json` sur la zone de collecte de l'Herbier. Le résumé par flux (OK/FAIL et nombre d'articles
retenus) s'affiche à la fin de l'exécution.
