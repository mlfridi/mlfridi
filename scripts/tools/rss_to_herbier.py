#!/usr/bin/env python3
"""SIO -> Herbier d'idées : convertit les flux RSS/Atom du registre SIO en fichier d'import.

Lit config/sources_candidates.psv (name|lang|region|type|url), télécharge chaque flux,
garde les articles récents et écrit un fichier JSON à importer dans l'Herbier
(bouton « Import en lot » ou glisser-déposer du fichier sur la zone de collecte).

Bibliothèque standard uniquement. Lecture seule : aucun envoi, aucune clé.

Exemples :
  python3 scripts/tools/rss_to_herbier.py                          # dernières 24 h, tous les flux
  python3 scripts/tools/rss_to_herbier.py --since-hours 72 --region mena --max-per-feed 10
  python3 scripts/tools/rss_to_herbier.py --keyword maroc --keyword hydrogène -o veille.json
  python3 scripts/tools/rss_to_herbier.py --from-file flux.xml     # fichier local (test, hors ligne)
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

UA = "SIO-Herbier/1.0 (+personal OSINT research)"
ROOT = Path(__file__).resolve().parents[2]


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child(el: ET.Element, *names: str) -> ET.Element | None:
    for n in names:
        for c in el:
            if local(c.tag) == n and ((c.text or "").strip() or c.get("href")):
                return c
    return None


def strip_html(s: str) -> str:
    s = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", s or "")
    s = re.sub(r"(?i)<br\s*/?>|</p>|</li>|</h\d>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    s = re.sub(r"[ \t\r\f\v]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n\n", s).strip()


def parse_date(s: str) -> datetime | None:
    s = (s or "").strip()
    if not s:
        return None
    try:
        d = parsedate_to_datetime(s)
    except (TypeError, ValueError):
        try:
            d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except ValueError:
            return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def parse_feed(data: bytes, src: dict) -> list[dict]:
    root = ET.fromstring(data)
    out = []
    for it in root.iter():
        if local(it.tag) not in ("item", "entry"):
            continue
        link_el = None
        for c in it:
            if local(c.tag) == "link" and c.get("rel", "alternate") == "alternate":
                link_el = c
                break
        url = ((link_el.get("href") or link_el.text) if link_el is not None else "") or ""
        if not url.startswith("http"):
            g = child(it, "guid", "id")
            url = (g.text or "").strip() if g is not None and (g.text or "").startswith("http") else ""
        title_el = child(it, "title")
        body_el = child(it, "encoded", "content", "description", "summary")
        date_el = child(it, "pubDate", "published", "updated", "date")
        pub = parse_date(date_el.text if date_el is not None else "")
        out.append({
            "title": strip_html(title_el.text if title_el is not None else "")[:200],
            "text": strip_html(body_el.text if body_el is not None else "")[:20000],
            "url": url.strip(),
            "source": src.get("name", ""),
            "lang": src.get("lang", ""),
            "region": src.get("region", ""),
            "published": pub.isoformat() if pub else "",
            "type": "article",
            "_dt": pub,
        })
    return [e for e in out if e["title"] or e["text"]]


def load_sources(path: Path) -> list[dict]:
    lines = [l for l in path.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]
    head = lines[0].split("|")
    return [dict(zip(head, l.split("|"))) for l in lines[1:]]


def fetch(url: str, timeout: int) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(8_000_000)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sources", default=str(ROOT / "config" / "sources_candidates.psv"))
    ap.add_argument("--from-file", action="append", default=[], help="flux XML local (répétable) au lieu du registre")
    ap.add_argument("-o", "--output", default="herbier-import.json")
    ap.add_argument("--since-hours", type=float, default=24, help="ignorer les articles plus anciens (0 = tous)")
    ap.add_argument("--max-per-feed", type=int, default=15)
    ap.add_argument("--region", action="append", default=[], help="filtrer par région du registre (répétable)")
    ap.add_argument("--lang", action="append", default=[], help="filtrer par langue du registre (répétable)")
    ap.add_argument("--type", dest="types", action="append", default=[], help="filtrer par type de source (répétable)")
    ap.add_argument("--keyword", action="append", default=[], help="garder seulement les articles contenant un de ces mots")
    ap.add_argument("--timeout", type=int, default=20)
    a = ap.parse_args(argv)

    if a.from_file:
        jobs = [({"name": Path(p).stem}, Path(p).read_bytes) for p in a.from_file]
    else:
        srcs = load_sources(Path(a.sources))
        srcs = [s for s in srcs
                if (not a.region or s.get("region") in a.region)
                and (not a.lang or s.get("lang") in a.lang)
                and (not a.types or s.get("type") in a.types)]
        jobs = [(s, (lambda u=s["url"]: fetch(u, a.timeout))) for s in srcs if s.get("url")]

    cutoff = datetime.now(timezone.utc) - timedelta(hours=a.since_hours) if a.since_hours > 0 else None
    kws = [k.lower() for k in a.keyword]
    items, seen, report = [], set(), []
    for i, (src, get) in enumerate(jobs):
        name = src.get("name", "?")
        try:
            entries = parse_feed(get(), src)
        except Exception as e:  # noqa: BLE001 — un flux en échec ne doit pas bloquer les autres
            report.append(f"FAIL  {name}: {type(e).__name__}: {e}")
            continue
        kept = []
        for e in sorted(entries, key=lambda x: x["_dt"] or datetime.min.replace(tzinfo=timezone.utc), reverse=True):
            if cutoff and e["_dt"] and e["_dt"] < cutoff:
                continue
            if kws and not any(k in (e["title"] + " " + e["text"]).lower() for k in kws):
                continue
            key = e["url"] or (name + e["title"])
            if key in seen:
                continue
            seen.add(key)
            kept.append(e)
            if len(kept) >= a.max_per_feed:
                break
        report.append(f"OK    {name}: {len(kept)}/{len(entries)}")
        items.extend(kept)
        if not a.from_file and i < len(jobs) - 1:
            time.sleep(1)

    for e in items:
        e.pop("_dt", None)
    doc = {"format": "herbier-import", "version": 1, "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "origin": "SIO sources_candidates", "items": items}
    Path(a.output).write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print("\n".join(report), file=sys.stderr)
    print(f"{len(items)} article(s) -> {a.output}", file=sys.stderr)
    return 0 if items or not jobs else 1


if __name__ == "__main__":
    sys.exit(main())
