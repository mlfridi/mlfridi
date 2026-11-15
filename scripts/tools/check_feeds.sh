#!/usr/bin/env bash
# SIO – vérifie les flux RSS candidats (lecture seule, réseau sortant uniquement).
# Usage : bash check_feeds.sh sources_candidates.psv > feeds_report.txt
# Sortie : OK / FAIL par source, code HTTP, nombre d'articles, date du plus récent.
set -u
f="${1:-sources_candidates.psv}"
tail -n +2 "$f" | while IFS='|' read -r name lang region type url; do
  tmp=$(mktemp)
  code=$(curl -sL -m 20 -A "SIO-FeedCheck/1.0 (+personal OSINT research)" -o "$tmp" -w '%{http_code}' "$url")
  n=$(grep -oE '<(item|entry)[ >]' "$tmp" | wc -l)
  last=$(grep -oE '<(pubDate|updated|dc:date)>[^<]+' "$tmp" | head -n1 | sed 's/<[^>]*>//')
  st=FAIL; [ "$code" = "200" ] && [ "$n" -gt 0 ] && st=OK
  printf '%-4s | %-24s | %s | items=%-3s | %s\n' "$st" "$name" "$code" "$n" "${last:-?}"
  rm -f "$tmp"; sleep 1
done
