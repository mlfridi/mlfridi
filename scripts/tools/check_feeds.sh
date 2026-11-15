#!/usr/bin/env bash
# SIO – vérifie les flux RSS candidats (lecture seule, réseau sortant uniquement).
# Usage : bash check_feeds.sh sources_candidates.psv > feeds_report.txt
#
# Statuts :
#   OK      HTTP 200, au moins un article, article le plus récent dans le seuil du type
#   STALE   flux valide mais trop ancien pour la veille (voir seuils)
#   NODATE  flux valide mais aucune date lisible (à examiner)
#   FAIL    erreur HTTP, blocage, ou aucun article
#
# Seuils de fraîcheur par type de source (heures) — modifiables par variable d'environnement :
#   media 48 h · agency 48 h · official 168 h (7 j) · think-tank 504 h (21 j) · autre 72 h
set -u
f="${1:-sources_candidates.psv}"
now=$(date -u +%s)

max_age_h() {
  case "$1" in
    media|agency) echo "${SIO_FRESH_MEDIA_H:-48}" ;;
    official)     echo "${SIO_FRESH_OFFICIAL_H:-168}" ;;
    think-tank)   echo "${SIO_FRESH_THINKTANK_H:-504}" ;;
    *)            echo "${SIO_FRESH_DEFAULT_H:-72}" ;;
  esac
}

printf '%-6s | %-24s | %-10s | %-4s | %-5s | %-8s | %s\n' STATUS SOURCE TYPE HTTP ITEMS AGE_H NEWEST_UTC
tail -n +2 "$f" | while IFS='|' read -r name lang region type url; do
  [ -z "${url:-}" ] && continue
  tmp=$(mktemp)
  code=$(curl -sL -m 20 -A "SIO-FeedCheck/1.1 (+personal OSINT research)" -o "$tmp" -w '%{http_code}' "$url")
  n=$(grep -oE '<(item|entry)[ >]' "$tmp" | wc -l)

  # Plus récent = maximum de toutes les dates (pas la première : certains flux ne sont pas triés)
  newest=0
  while IFS= read -r d; do
    e=$(date -u -d "$d" +%s 2>/dev/null) || continue
    [ "$e" -le $((now + 3600)) ] && [ "$e" -gt "$newest" ] && newest=$e
  done < <(grep -oE '<(pubDate|updated|published|dc:date)>[^<]+' "$tmp" | sed 's/<[^>]*>//')

  limit=$(max_age_h "$type")
  if [ "$code" != "200" ] || [ "$n" -eq 0 ]; then
    st=FAIL; age="-"; iso="-"
  elif [ "$newest" -eq 0 ]; then
    st=NODATE; age="-"; iso="-"
  else
    age=$(( (now - newest) / 3600 ))
    iso=$(date -u -d "@$newest" '+%Y-%m-%d %H:%M')
    if [ "$age" -le "$limit" ]; then st=OK; else st=STALE; fi
  fi
  printf '%-6s | %-24s | %-10s | %-4s | %-5s | %-8s | %s\n' "$st" "$name" "$type" "$code" "$n" "$age" "$iso"
  rm -f "$tmp"; sleep 1
done
