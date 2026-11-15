#!/usr/bin/env bash
# SIO – PHASE 3 : préparation et vérification de l'environnement (conteneur Hermes).
# Agit UNIQUEMENT dans $SIO_ROOT (défaut /data/sio). Ne modifie ni Hermes, ni le système.
# Idempotent : peut être relancé sans risque.
# Ne lit, n'écrit et n'affiche aucun secret.
set -u
ROOT="${SIO_ROOT:-/data/sio}"
pass=0; fail=0
ok()  { echo "PASS | $1"; pass=$((pass+1)); }
ko()  { echo "FAIL | $1"; fail=$((fail+1)); }

echo "== SIO phase 3 check — $(date -u '+%Y-%m-%d %H:%M UTC') — user=$(id -un) root=$ROOT"

# 1. Arborescence
umask 077
if mkdir -p "$ROOT"/{app,logs,backups,reports,check} 2>/dev/null; then ok "arborescence $ROOT"; else ko "création $ROOT"; fi

# 2. Python + venv
PY=$(command -v python3 || true)
[ -n "$PY" ] && ok "python: $($PY --version 2>&1)" || ko "python3 introuvable"
if [ -x "$ROOT/venv/bin/python" ] || $PY -m venv "$ROOT/venv" >/dev/null 2>&1; then ok "venv $ROOT/venv"; else ko "création venv"; fi
VPY="$ROOT/venv/bin/python"

# 3. Paquets (installés dans le venv uniquement)
if "$VPY" -m pip install -q --disable-pip-version-check feedparser anthropic >"$ROOT/logs/pip_phase3.log" 2>&1; then
  ok "pip install feedparser anthropic"
  "$VPY" -m pip freeze 2>/dev/null | grep -iE '^(feedparser|anthropic)==' | sed 's/^/     /'
else
  ko "pip install (voir $ROOT/logs/pip_phase3.log)"; tail -n 5 "$ROOT/logs/pip_phase3.log" | sed 's/^/     /'
fi

# 4. SQLite en mode WAL sur /data
if "$VPY" - "$ROOT" <<'PY' 2>&1; then ok "sqlite WAL + écriture/lecture"; else ko "sqlite"; fi
import sqlite3, sys, os
p = os.path.join(sys.argv[1], "check", "wal_test.db")
c = sqlite3.connect(p); mode = c.execute("PRAGMA journal_mode=WAL").fetchone()[0]
c.execute("CREATE TABLE IF NOT EXISTS t(x)"); c.execute("INSERT INTO t VALUES (1)"); c.commit()
n = c.execute("SELECT count(*) FROM t").fetchone()[0]; c.close()
for s in ("", "-wal", "-shm"):
    if os.path.exists(p + s): os.remove(p + s)
print(f"     journal_mode={mode} sqlite={sqlite3.sqlite_version} rows={n}")
assert mode == "wal" and n >= 1
PY

# 5. Fichier secret : permissions 600 possibles ?
t="$ROOT/check/.perm_test"; : > "$t" && chmod 600 "$t"
[ "$(stat -c %a "$t" 2>/dev/null)" = "600" ] && ok "fichiers en mode 600" || ko "chmod 600"
rm -f "$t"

# 6. feedparser sur un vrai flux
if "$VPY" -c "
import feedparser,sys
d=feedparser.parse('https://feeds.bbci.co.uk/news/world/rss.xml', agent='SIO/0.1 (+personal OSINT research)')
print(f'     status={d.get(\"status\")} entries={len(d.entries)}'); sys.exit(0 if d.entries else 1)" 2>&1; then ok "feedparser + réseau sortant"; else ko "feedparser"; fi

# 7. API Anthropic joignable (sans clé : on attend 401, preuve de connectivité)
code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models)
[ "$code" = "401" ] && ok "api.anthropic.com joignable (401 sans clé, attendu)" || ko "api.anthropic.com code=$code"

# 8. Ressources disponibles
echo "INFO | disque: $(df -h "$ROOT" | awk 'NR==2{print $4" libres sur "$2}')"
echo "INFO | mémoire cgroup: $(( $(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0) / 1048576 )) Mo utilisés / $(( $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 0) / 1048576 )) Mo"
echo "INFO | taille venv: $(du -sh "$ROOT/venv" 2>/dev/null | cut -f1)"

# 9. Clé API présente ? (sans jamais l'afficher)
if [ -f "$ROOT/.env" ]; then
  grep -q '^ANTHROPIC_API_KEY=sk-ant-' "$ROOT/.env" && echo "INFO | .env présent, clé au bon format (valeur non affichée)" || echo "INFO | .env présent, clé absente ou format inattendu"
  echo "INFO | droits .env: $(stat -c %a "$ROOT/.env")"
else
  echo "INFO | pas encore de $ROOT/.env (normal à ce stade)"
fi

echo "== RÉSULTAT: $pass PASS / $fail FAIL"
