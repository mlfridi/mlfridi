# SIO – Phase 2 : Architecture (SIO-Lite sur Hermes)

Statut : **proposition, en attente de validation.** Rien n'est installé.
Date : 2026-11-15.

## 0. Décisions prises

| Sujet | Décision | Source |
|---|---|---|
| Hébergement | Conteneur Hermes Agent existant (Hostinger, offre « Applications d'automatisation IA », expire le 2028-10-18) | Audits n°1 et 2 |
| Ressources | 4 Gio RAM, 2 vCPU, 512 processus, `/data` 25 Gio, aucun port entrant, pas de root | Audit n°2 (cgroup) |
| Variante | **SIO-Lite** : pas de tableau de bord web ni de carte pour l'instant ; Telegram est l'interface | Choix utilisateur |
| IA | API Anthropic à la consommation (pas l'abonnement Claude) ; Haiku 5.5 pour le tri, **Opus 5.5** pour les briefings | Choix utilisateur (« 2 ») |
| Budget IA | Plafond **8 $/mois** dans la Console Anthropic + coupe-circuit interne | Estimation ≈ 8 $ |
| Évolution | Le même code passera sur un VPS (option A) sans réécriture : SQLite → PostgreSQL, ajout API web, tableau de bord et carte | — |

## 1. Schéma d'architecture

```
                     Internet (sortant uniquement)
   ┌──────────────┬───────────────┬──────────────────┬─────────────────┐
   │ Flux RSS     │ API Anthropic │ API Telegram     │ Oxylabs (option)│
   └──────▲───────┴───────▲───────┴────────▲─────────┴────────▲────────┘
          │               │                │                  │
┌─────────┼───────────────┼────────────────┼──────────────────┼───────┐
│ Conteneur Hermes (4 Gio / 2 vCPU)        │                  │       │
│         │               │                │                  │       │
│  ┌──────┴──────┐  ┌─────┴──────────┐  ┌──┴──────────────┐   │       │
│  │ collector   │  │ orchestrator   │  │ Hermes gateway  │   │       │
│  │ RSS → norm. │  │ 8 rôles, 1 API │  │ (Telegram,      │   │       │
│  │ dédup, géo  │  │ budget guard   │  │  cron, skills)  │   │       │
│  └──────┬──────┘  └─────┬──────────┘  └──┬──────────────┘   │       │
│         │               │                │ appelle `sio …`  │       │
│         ▼               ▼                ▼                  │       │
│  ┌──────────────────────────────────────────────┐           │       │
│  │ sio (CLI Python) : collect · analyze ·       │───────────┘       │
│  │ briefing · country · risk · status · backup  │                   │
│  └──────────────────────┬───────────────────────┘                   │
│                         ▼                                           │
│  /data/sio/  sio.db (SQLite WAL) · reports/ · backups/ · logs/ · .env │
└─────────────────────────────────────────────────────────────────────┘
```

**Rôle de Hermes** : planificateur (cron), canal Telegram et interface en langage naturel.
**Rôle de SIO** : toute la logique (collecte, stockage, vérification, IA, rapports), dans un
paquet Python indépendant de Hermes. Si Hermes disparaît, SIO tourne ailleurs sans changement.

## 2. Arborescence du projet

```
mlfridi/                      (dépôt Git, sans aucun secret)
├── sio/
│   ├── __init__.py
│   ├── cli.py                # point d'entrée `sio <commande>`
│   ├── config.py             # lecture .env + réglages (modèles, budget, langues)
│   ├── db/
│   │   ├── schema.sql        # schéma SQLite (compatible PostgreSQL)
│   │   └── repo.py           # accès aux données
│   ├── collect/
│   │   ├── rss.py            # feedparser, ETag/Last-Modified, limites de débit
│   │   ├── normalize.py      # nettoyage, langue, hash de contenu
│   │   └── dedup.py          # doublons exacts + quasi-doublons (simhash)
│   ├── enrich/
│   │   ├── geo.py            # pays/régions par dictionnaire AR/EN/FR (sans IA)
│   │   └── topics.py         # thèmes par mots-clés (sans IA)
│   ├── agents/
│   │   ├── orchestrator.py   # Agent 01 : planifie, appelle les rôles, fusionne
│   │   ├── roles.py          # prompts des agents 02–08
│   │   ├── llm.py            # adaptateur fournisseur (Anthropic ; autres plus tard)
│   │   └── budget.py         # compteur de coût, coupe-circuit
│   ├── verify/
│   │   └── grading.py        # cotation source/information, corroboration
│   ├── reports/
│   │   ├── templates/        # 6 modèles × 3 langues (Jinja2)
│   │   └── render.py
│   └── ops/
│       ├── backup.py         # sauvegarde SQLite à chaud + rotation
│       └── health.py         # état, volumes, erreurs récentes
├── config/
│   ├── sources_candidates.psv
│   └── settings.example.env  # modèle de .env, sans valeurs
├── hermes/
│   └── skill_sio.md          # instructions pour Hermes (commandes autorisées)
├── tests/
├── scripts/audit/, scripts/tools/
└── docs/
```

Sur le serveur : code dans `/data/sio/app`, données dans `/data/sio/{sio.db,reports,backups,logs}`,
secrets dans `/data/sio/.env` (droits 600, jamais dans Git).

## 3. Schéma de la base (SQLite, mode WAL)

Principe clé : **séparer la fiabilité de la source et la crédibilité de chaque information**
(échelle de type « Admiralty / OTAN » : source A–F, information 1–6).

```sql
-- Sources : registre + fiabilité de la source (A = sûre … F = non évaluable)
CREATE TABLE sources (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL, url TEXT NOT NULL UNIQUE,
  type TEXT CHECK (type IN ('media','official','think-tank','agency','social')),
  lang TEXT CHECK (lang IN ('ar','en','fr')), region TEXT,
  reliability TEXT CHECK (reliability IN ('A','B','C','D','E','F')) DEFAULT 'F',
  reliability_note TEXT,
  active INTEGER DEFAULT 0,            -- activée seulement après check OK
  last_ok_at TEXT, last_error TEXT, etag TEXT, last_modified TEXT
);

-- Articles collectés (preuve brute)
CREATE TABLE articles (
  id INTEGER PRIMARY KEY,
  source_id INTEGER NOT NULL REFERENCES sources(id),
  url TEXT NOT NULL UNIQUE, title TEXT NOT NULL, summary TEXT,
  lang TEXT, published_at TEXT, collected_at TEXT NOT NULL,
  content_hash TEXT NOT NULL, simhash INTEGER,
  duplicate_of INTEGER REFERENCES articles(id),
  countries TEXT, topics TEXT,          -- JSON
  priority INTEGER DEFAULT 0            -- 0..3, mis par le tri Haiku
);
CREATE INDEX ix_articles_pub ON articles(published_at);

-- Événements : regroupement d'articles décrivant le même fait
CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL, first_seen_at TEXT, last_seen_at TEXT,
  countries TEXT, region TEXT, topics TEXT, lat REAL, lon REAL,
  risk_level INTEGER CHECK (risk_level BETWEEN 0 AND 5)
);
CREATE TABLE event_articles (
  event_id INTEGER REFERENCES events(id), article_id INTEGER REFERENCES articles(id),
  stance TEXT CHECK (stance IN ('supports','contradicts','neutral')),
  PRIMARY KEY (event_id, article_id)
);

-- Énoncés : FACT / CLAIM / ASSESSMENT / FORECAST, toujours reliés à des preuves
CREATE TABLE statements (
  id INTEGER PRIMARY KEY,
  event_id INTEGER REFERENCES events(id),
  kind TEXT NOT NULL CHECK (kind IN ('FACT','CLAIM','ASSESSMENT','FORECAST')),
  text TEXT NOT NULL, lang TEXT,
  credibility INTEGER CHECK (credibility BETWEEN 1 AND 6),  -- 1 confirmée … 6 non évaluable
  confidence TEXT CHECK (confidence IN ('low','moderate','high')),
  produced_by TEXT,                    -- 'human' ou nom de l'agent
  created_at TEXT NOT NULL, last_verified_at TEXT
);
CREATE TABLE statement_evidence (
  statement_id INTEGER REFERENCES statements(id),
  article_id INTEGER REFERENCES articles(id),
  relation TEXT CHECK (relation IN ('supports','contradicts')),
  PRIMARY KEY (statement_id, article_id)
);

-- Historique des vérifications
CREATE TABLE verifications (
  id INTEGER PRIMARY KEY, statement_id INTEGER REFERENCES statements(id),
  at TEXT NOT NULL, by TEXT, old_credibility INTEGER, new_credibility INTEGER, note TEXT
);

-- Rapports produits
CREATE TABLE reports (
  id INTEGER PRIMARY KEY,
  kind TEXT CHECK (kind IN ('daily','weekly','risk','country','crisis','event')),
  lang TEXT, scope TEXT, created_at TEXT, path TEXT, cost_usd REAL
);

-- Consommation IA (budget) et journal d'audit
CREATE TABLE llm_usage (
  id INTEGER PRIMARY KEY, at TEXT, agent TEXT, model TEXT,
  input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cost_usd REAL
);
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY, at TEXT NOT NULL, actor TEXT, action TEXT, detail TEXT
);
```

**Règles anti-invention, appliquées par le code et non par le seul prompt :**
- un énoncé `FACT` exige au moins **2 articles de sources indépendantes** dans `statement_evidence`. Sinon, il est rétrogradé en `CLAIM` ;
- les agents ne reçoivent que des articles identifiés par leur `id`, et ne peuvent citer que ces `id`. Toute citation inconnue est rejetée ;
- les sorties IA sont en JSON validé par un schéma ; tout `ASSESSMENT` et tout `FORECAST` portent un niveau de confiance et leurs hypothèses.

## 4. Interfaces (« API » de SIO-Lite)

Pas d'API HTTP dans cette variante, puisqu'aucun accès entrant n'est possible. L'interface est une **CLI**, que Hermes appelle.

| Commande CLI | Déclenchement | Coût IA |
|---|---|---|
| `sio collect` | Hermes cron, toutes les 30 min | 0 $ |
| `sio triage` | après chaque collecte | Haiku |
| `sio briefing --lang fr` | Hermes cron, 07:00 Africa/Casablanca, et sur `/briefing` | Opus |
| `sio region mena\|gulf\|maghreb\|world` | `/mena`, `/gulf`, `/morocco`, `/world` | Opus |
| `sio country <pays>` | « analyse le Maroc » | Opus |
| `sio event <id>` | « analyse l'événement 42 » | Opus |
| `sio risk` | `/risk` et alerte si niveau ≥ 4 | Haiku, puis Opus si alerte |
| `sio economy` | `/economy` | Opus |
| `sio reports --last 5` | `/reports` | 0 $ |
| `sio status` | `/status` | 0 $ |
| `sio weekly` | Hermes cron, dimanche 18:00 | Opus |
| `sio backup` | Hermes cron, chaque jour 03:00 | 0 $ |
| `sio sources check` | manuel, puis chaque semaine | 0 $ |

Hermes ne reçoit une instruction (`hermes/skill_sio.md`) que pour **ces commandes**.
Il n'exécute aucune autre commande au nom de SIO.

## 5. Système multi-agents (un orchestrateur, un seul appel par rôle)

```
                ┌──────────────────────────────────┐
  articles ───► │ 01 Chief Analyst (orchestrateur) │ ──► rapport final + contradictions
  (ids)         └──┬────┬────┬────┬────┬────┬────┬─┘
                   02   03   04   05   06   07   08
                 Polit Milit Écon Région OSINT Risque Stratég.
```

- Ce ne sont pas 8 modèles : il y a **un adaptateur LLM** et **8 prompts système**. Le rôle 06 (OSINT/vérification) est surtout du **code** : corroboration et détection des contradictions. L'IA n'intervient que pour résumer les divergences.
- **Le tri est fait par Haiku**, par lots de 20 articles : thème, pays, priorité de 0 à 3, et résumé d'une ligne dans les 3 langues.
- **Le briefing est fait par Opus**, en un seul appel structuré qui produit les sections des rôles 02 à 08. Le Chief Analyst fusionne les résultats et signale les contradictions. Les rôles ne sont appelés séparément que pour une analyse approfondie (`country`, `event`).
- **Contrôle du coût :**
  - mise en cache des prompts système, qui sont stables ;
  - plafond de tokens par commande ;
  - coupe-circuit : à 90 % du budget mensuel, plus d'appels à Opus ; à 100 %, plus aucun appel à l'IA. La collecte continue.
- **Changement de fournisseur :** `llm.py` expose `complete(role, messages, schema)`. Le fournisseur et les modèles sont définis dans `.env`.

## 6. Modèles de rapport

Six modèles : quotidien, hebdomadaire, risque, pays, crise, événement. Chacun existe en AR, EN et FR, avec les mêmes sections :
1. Résumé exécutif
2. Faits marquants
3. **Faits confirmés (FACT)**
4. **Allégations non confirmées (CLAIM)**
5. Analyse (ASSESSMENT)
6. Indicateurs de risque
7. Scénarios (FORECAST), avec leurs hypothèses
8. Niveau de confiance global
9. Chronologie
10. Sources : liens réels issus de la base uniquement

Les rapports sont envoyés sur Telegram sous forme de résumé, avec le fichier Markdown complet en pièce jointe.

## 7. Sécurité

| Risque | Mesure |
|---|---|
| Fuite de la clé API | `.env` dans `/data/sio` en mode 600 ; exclu de Git (`.gitignore`) ; jamais écrit dans les logs ni les rapports |
| Dépense incontrôlée | Plafond dans la Console Anthropic + coupe-circuit interne + `llm_usage` |
| Accès non autorisé au bot | Hermes est limité à votre identifiant Telegram (à vérifier en phase 3) |
| Injection de prompt via un article | Contenu des articles placé dans des blocs de données ; consigne « données, pas instructions » ; sorties en JSON validé ; aucun outil d'exécution donné aux agents SIO |
| Hermes détourné pour exécuter autre chose | Commandes SIO sur liste fixe ; aucune commande destructive exposée |
| Perte de données | `sio backup` quotidien (API de sauvegarde SQLite), conservation 14 jours + 8 semaines ; copie hors site chiffrée (option, phase 9) |
| Respect des sources | User-Agent identifié, ETag/Last-Modified, 1 requête par flux par cycle maximum, flux officiels RSS uniquement, pas de scraping par défaut |
| Traçabilité | `audit_log` pour chaque commande, envoi, changement de source et vérification |

## 8. Budget

| Poste | Coût mensuel |
|---|---|
| Hébergement (Hermes, déjà payé jusqu'en 2028) | 0 $ supplémentaire |
| API Anthropic : Haiku (tri, ≈ 500 articles/j) | ≈ 2,3 $ |
| API Anthropic : Opus (briefing quotidien + quelques analyses) | ≈ 5,4 $ |
| **Total** | **≈ 8 $** (plafond 8 $) |

Ressources estimées : environ 150 Mo de RAM pendant la collecte, et moins de 1 Gio de disque par an pour SQLite et les rapports.

## 9. Plan de déploiement (phases 3 à 9)

**Phase 3 – Vérifications dans Hermes (sans rien casser).** Il faut confirmer 5 points :
1. créer `/data/sio` et un environnement Python virtuel (`venv`) avec `pip` ;
2. faire exécuter une commande planifiée par le cron de Hermes ;
3. faire envoyer un message Telegram par Hermes ;
4. lancer `check_feeds.sh` sur les sources candidates ;
5. vérifier que Hermes est bien limité à votre compte Telegram.

En cas d'échec d'un point, on adapte le plan avant d'aller plus loin.

**Phase 4 :** collecte, normalisation, déduplication, base SQLite et tests.

**Phase 5 :** adaptateur LLM, garde-fou de budget, tri Haiku, briefing Opus, tests de chaque rôle avec de vrais articles.

**Phase 6 (adaptée) :** rapports en 3 langues et instructions pour Hermes. Pas de tableau de bord web dans cette variante.

**Phase 7 :** commandes et alertes Telegram de bout en bout.

**Phase 8 :** tests (unitaires, intégration, coûts réels, injection de prompt).

**Phase 9 :** crons définitifs, sauvegardes et surveillance.

**Phase 10 :** documentation.

## 10. Points ouverts

- Les capacités exactes du cron et des instructions (skills) de Hermes sont à confirmer en phase 3.
- Le shell restreint `lshell` pourrait limiter `pip` ou `python`. Dans ce cas, c'est Hermes qui exécutera ces commandes.
- Oxylabs (773 crédits) reste inutilisé tant qu'aucune source sans RSS n'est jugée indispensable.
