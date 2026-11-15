#!/usr/bin/env bash
# SIO – enregistre la clé API Anthropic dans $SIO_ROOT/.env (droits 600).
# À lancer VOUS-MÊME dans le terminal hPanel. La saisie est masquée.
# Ne collez JAMAIS la clé dans Telegram, dans Hermes ou dans une conversation IA.
set -u
ROOT="${SIO_ROOT:-/data/sio}"; ENV="$ROOT/.env"
umask 077; mkdir -p "$ROOT"
read -rsp "Collez la clé API Anthropic (rien ne s'affiche), puis Entrée : " KEY; echo
case "$KEY" in sk-ant-*) ;; *) echo "Format inattendu (doit commencer par sk-ant-). Rien n'a été écrit."; unset KEY; exit 1;; esac
tmp=$(mktemp "$ROOT/.env.XXXX")
[ -f "$ENV" ] && grep -v '^ANTHROPIC_API_KEY=' "$ENV" > "$tmp"
printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" >> "$tmp"; unset KEY
chmod 600 "$tmp" && mv "$tmp" "$ENV"
echo "Clé enregistrée dans $ENV (droits $(stat -c %a "$ENV")). Elle ne sera jamais affichée."
