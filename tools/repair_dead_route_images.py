#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MotoGo24 — oprava mrtvých fotek tras (Wikimedia 404).

Starší seedy tras odhadovaly názvy souborů na Commons a část neexistuje
(404) — zrcadlení (mirror-route-images) je trvale přeskakuje a ve Velíně
i appce zůstávají rozbité. Tento skript:
  1. vytáhne všechny wiki URL ze seed souborů tras (route_pois i routes),
  2. ověří u Commons, které jsou mrtvé (404),
  3. pro mrtvé dohledá správnou fotku přes Wikidata (hledání dle názvu
     bodu + kontrola vzdálenosti souřadnic < 10 km, P18),
  4. vygeneruje opravný SQL: UPDATE dle staré URL (route_pois.image_url,
     route_pois.images, routes.cover_image, routes.images); bez náhrady
     se mrtvá URL odstraní (lepší placeholder než věčně rozbitá fotka).
Zrcadlení pak nové URL samo stáhne do bucketu media.

POUŽITÍ (potřeba síť na commons/wikidata):
    python3 tools/repair_dead_route_images.py
Výstup: supabase/migrations/20260705_fix_dead_route_images.sql
"""

import glob
import math
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import requests

UA = {"User-Agent": "MotoGo24-image-repair/1.0 (info@motogo24.cz)"}
WD_API = "https://www.wikidata.org/w/api.php"


def haversine(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def collect_urls():
    """wiki URL → kontext (název + GPS bodu, je-li z route_pois řádku)."""
    ctx = {}
    poi_re = re.compile(
        r"\(v_route, '((?:[^']|'')*)', '(?:[^']|'')*', (-?[\d.]+), (-?[\d.]+), "
        r"'(https?://[^']*(?:wikimedia|wikipedia)[^']*)'", re.S)
    url_re = re.compile(r"https?://[^'\"\s,}]*(?:wikimedia|wikipedia)\.org[^'\"\s,}]*")
    for f in glob.glob("supabase/migrations/*.sql"):
        if "poi_catalog" in f or "fix_dead" in f:
            continue  # katalog má URL přímo z Wikidata (živé) / vlastní výstup
        sql = open(f, encoding="utf-8").read()
        for m in poi_re.finditer(sql):
            ctx.setdefault(m.group(4), {"name": m.group(1).replace("''", "'"),
                                        "lat": float(m.group(2)), "lng": float(m.group(3))})
        for u in url_re.findall(sql):
            ctx.setdefault(u, None)
    return ctx


def is_dead(url):
    """404/415 na miniatuře = mrtvý soubor. 429/403/5xx = neprůkazné (živý)."""
    try:
        sep = "&" if "?" in url else "?"
        r = requests.get(f"{url}{sep}width=64", headers=UA, timeout=30,
                         allow_redirects=True, stream=True)
        r.close()
        return r.status_code in (404, 415)
    except Exception:
        return False  # síťová chyba ≠ mrtvý soubor


def wd_photo(name, lat, lng):
    """Najde P18 fotku entity dle názvu; souřadnice musí sedět (<10 km)."""
    for lang in ("cs", "de", "en", "pl", "sk"):
        try:
            r = requests.get(WD_API, params={
                "action": "wbsearchentities", "search": name, "language": lang,
                "type": "item", "limit": 5, "format": "json"}, headers=UA, timeout=30).json()
            ids = [it["id"] for it in r.get("search", [])]
            if not ids:
                continue
            e = requests.get(WD_API, params={
                "action": "wbgetentities", "ids": "|".join(ids),
                "props": "claims", "format": "json"}, headers=UA, timeout=30).json()
            for qid in ids:
                cl = e["entities"].get(qid, {}).get("claims", {})
                coord = cl.get("P625", [{}])[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                img = cl.get("P18", [{}])[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                if not (coord and img):
                    continue
                if haversine((lat, lng), (coord["latitude"], coord["longitude"])) <= 10:
                    fn = img.replace(" ", "%20")
                    return f"https://commons.wikimedia.org/wiki/Special:FilePath/{fn}"
        except Exception:
            time.sleep(1)
    return None


def esc(s):
    return s.replace("'", "''")


def main():
    ctx = collect_urls()
    urls = list(ctx)
    print(f"Unikátních wiki URL v seedech: {len(urls)}")

    dead = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        for u, d in zip(urls, ex.map(is_dead, urls)):
            if d:
                dead.append(u)
    print(f"Mrtvých (404): {len(dead)}")

    fixes, removals = [], []
    for i, u in enumerate(dead, 1):
        c = ctx.get(u)
        new = wd_photo(c["name"], c["lat"], c["lng"]) if c else None
        (fixes if new else removals).append((u, new))
        if i % 25 == 0:
            print(f"  dohledávání {i}/{len(dead)} (nalezeno {len(fixes)})", flush=True)
        time.sleep(0.3)
    print(f"Náhrada nalezena: {len(fixes)}, k odstranění: {len(removals)}")

    out = ["-- MotoGo24 - oprava mrtvych fotek tras (404 na Commons)",
           "-- Vygenerovano: tools/repair_dead_route_images.py (idempotentni)",
           "-- Nahrady maji overene souradnice entity < 10 km od bodu.", ""]
    for old, new in fixes:
        o, n = esc(old), esc(new)
        out += [
            f"update public.route_pois set image_url = '{n}' where image_url = '{o}';",
            f"update public.route_pois set images = array_replace(images, '{o}', '{n}') where '{o}' = any(images);",
            f"update public.routes set cover_image = '{n}' where cover_image = '{o}';",
            f"update public.routes set images = array_replace(images, '{o}', '{n}') where '{o}' = any(images);",
        ]
    out.append("")
    for old, _ in removals:
        o = esc(old)
        out += [
            f"update public.route_pois set image_url = null where image_url = '{o}';",
            f"update public.route_pois set images = array_remove(images, '{o}') where '{o}' = any(images);",
            f"update public.routes set cover_image = null where cover_image = '{o}';",
            f"update public.routes set images = array_remove(images, '{o}') where '{o}' = any(images);",
        ]
    path = "supabase/migrations/20260705_fix_dead_route_images.sql"
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"Zapsáno: {path} ({len(fixes)} náhrad, {len(removals)} odstranění)")


if __name__ == "__main__":
    main()
