#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MotoGo24 — generátor TRAS z katalogu bodů zájmu (points_of_interest).

Čte body z SQL dávek katalogu v supabase/migrations/ (žádná síť není
potřeba) a skládá z nich trasy typu 'poi' (za body zájmu):
  - TEMATICKÉ: voda / příroda / historie (hrady+památky) / vyhlídky,
  - SMÍŠENÉ „To nejlepší v okolí" z bodů blízko sebe.
Shlukování: greedy — nejslavnější nevyužitý bod jako kotva + nejbližší
body stejného tématu do zadaného rádiusu; pořadí zastávek nearest-neighbor.

Trasy následují konvence stávajících seedů: is_active=false (admin je ve
Velíně zkontroluje a publikuje), status='approved', branch = nejbližší
pobočka ke startu, idempotentní delete dle (name + sort_order pásmo).
Názvy a popisy tras v 8 jazycích (translations jsonb) — šablonově;
route_pois přebírají popisy a překlady přímo z katalogu.

POUŽITÍ:
    python3 tools/generate_routes_from_pois.py
Výstup: supabase/migrations/20260705_routes_from_catalog_batch{N}.sql
"""

import glob
import importlib.util
import json
import math
import re
import sys

# COUNTRY_NAMES (s předložkami, 8 jazyků) sdílíme s generátorem katalogu.
spec = importlib.util.spec_from_file_location("poigen", "tools/generate_poi_batches.py")
poigen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(poigen)
COUNTRY_NAMES = poigen.COUNTRY_NAMES
LANGS = poigen.LANGS

SORT_BASE = 5000          # pásmo sort_order nových tras (idempotence mazání)
ROUTES_PER_FILE = 50
THEMES = {
    # klíč: (kategorie, rádius km, min bodů, max bodů, kvóta tras)
    "water":   (("water",), 45, 5, 7, 120),
    "nature":  (("nature",), 50, 5, 7, 80),
    "history": (("castle", "sights"), 40, 5, 7, 150),
    "lookout": (("lookout",), 60, 4, 7, 25),
    "mixed":   (("water", "castle", "sights", "nature", "lookout", "food", "other"), 30, 5, 8, 175),
}
NAME_TPL = {
    "water":   {"cs": "Vodní krásy: {a} a okolí", "en": "Waterside ride: {a} and around",
                "de": "Wasser-Tour: {a} und Umgebung", "pl": "Wodne piękno: {a} i okolice",
                "nl": "Waterroute: {a} en omgeving", "es": "Ruta del agua: {a} y alrededores",
                "fr": "Balade au fil de l'eau : {a} et environs", "uk": "Водні краси: {a} та околиці"},
    "nature":  {"cs": "Přírodní krásy: {a} a okolí", "en": "Natural wonders: {a} and around",
                "de": "Naturschönheiten: {a} und Umgebung", "pl": "Cuda natury: {a} i okolice",
                "nl": "Natuurpracht: {a} en omgeving", "es": "Bellezas naturales: {a} y alrededores",
                "fr": "Merveilles naturelles : {a} et environs", "uk": "Природні краси: {a} та околиці"},
    "history": {"cs": "Za historií: {a} a okolí", "en": "History ride: {a} and around",
                "de": "Geschichts-Tour: {a} und Umgebung", "pl": "Śladami historii: {a} i okolice",
                "nl": "Historische route: {a} en omgeving", "es": "Ruta histórica: {a} y alrededores",
                "fr": "Sur les traces de l'histoire : {a} et environs", "uk": "Слідами історії: {a} та околиці"},
    "lookout": {"cs": "Vyhlídková jízda: {a} a okolí", "en": "Viewpoint ride: {a} and around",
                "de": "Aussichts-Tour: {a} und Umgebung", "pl": "Trasa widokowa: {a} i okolice",
                "nl": "Uitzichtroute: {a} en omgeving", "es": "Ruta de miradores: {a} y alrededores",
                "fr": "Route des panoramas : {a} et environs", "uk": "Оглядовий маршрут: {a} та околиці"},
    "mixed":   {"cs": "To nejlepší v okolí: {a}", "en": "Highlights around {a}",
                "de": "Highlights rund um {a}", "pl": "Najlepsze w okolicy: {a}",
                "nl": "Hoogtepunten rond {a}", "es": "Lo mejor cerca de {a}",
                "fr": "Les incontournables autour de {a}", "uk": "Найкраще навколо: {a}"},
}
DESC_TPL = {
    "cs": "Vyjížďka za body zájmu {country}: {list}. Celkem {n} zastávek, přibližně {dist} km — pořadí si můžeš v aplikaci upravit a navigovat rovnou z ní.",
    "en": "A points-of-interest ride {country}: {list}. {n} stops over roughly {dist} km — reorder them in the app and navigate right away.",
    "de": "Eine Tour zu Sehenswürdigkeiten {country}: {list}. {n} Stopps auf rund {dist} km — Reihenfolge in der App anpassbar, Navigation direkt aus der App.",
    "pl": "Wycieczka po ciekawych miejscach {country}: {list}. Łącznie {n} przystanków na około {dist} km — kolejność zmienisz w aplikacji i od razu nawigujesz.",
    "nl": "Een rit langs bezienswaardigheden {country}: {list}. {n} stops over zo'n {dist} km — pas de volgorde aan in de app en navigeer direct.",
    "es": "Una ruta por puntos de interés {country}: {list}. {n} paradas en unos {dist} km; reordénalas en la app y navega al instante.",
    "fr": "Une virée entre points d'intérêt {country} : {list}. {n} arrêts sur environ {dist} km — réorganisez-les dans l'app et lancez la navigation.",
    "uk": "Поїздка цікавими місцями {country}: {list}. Загалом {n} зупинок на приблизно {dist} км — порядок можна змінити в застосунку й одразу навігувати.",
}


def esc(s):
    return s.replace("'", "''")


def haversine(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def load_points():
    """Body katalogu ze SQL dávek (curated + wikidata + eu)."""
    pts = []
    files = (glob.glob("supabase/migrations/20260704_poi_catalog_seed_batch*.sql")
             + glob.glob("supabase/migrations/20260704_poi_catalog_wikidata*batch*.sql"))
    row_re = re.compile(
        r"\('(\w+)', '((?:[^']|'')*)', '((?:[^']|'')*)', (-?[\d.]+), (-?[\d.]+), '(\w\w)', "
        r"'[^']*', (\d+)(?:, (null|'(?:[^']|'')*'))?, '(\{.*?\})'::jsonb\)", re.S)
    for f in files:
        sql = open(f, encoding="utf-8").read()
        for m in row_re.finditer(sql):
            img = m.group(8)
            img = None if (img in (None, "null")) else img[1:-1].replace("''", "'")
            pts.append({
                "category": m.group(1),
                "name": m.group(2).replace("''", "'"),
                "desc": m.group(3).replace("''", "'"),
                "lat": float(m.group(4)), "lng": float(m.group(5)),
                "country": m.group(6), "rank": int(m.group(7)),
                "image": img,
                "tr": json.loads(m.group(9).replace("''", "'")),
            })
    return pts


def build_clusters(points):
    routes = []
    for theme, (cats, radius, mn, mx, quota) in THEMES.items():
        pool = sorted([p for p in points if p["category"] in cats], key=lambda p: p["rank"])
        used = set()
        made = 0
        for seed in pool:
            if made >= quota:
                break
            sid = id(seed)
            if sid in used:
                continue
            near = [p for p in pool if id(p) not in used and p["country"] == seed["country"]
                    and haversine((seed["lat"], seed["lng"]), (p["lat"], p["lng"])) <= radius]
            if len(near) < mn:
                continue
            near.sort(key=lambda p: p["rank"])
            members = near[:mx]
            # pořadí zastávek: nearest neighbor od kotvy
            ordered = [seed] if seed in members else [members[0]]
            rest = [p for p in members if p is not ordered[0]]
            while rest:
                last = ordered[-1]
                nxt = min(rest, key=lambda p: haversine((last["lat"], last["lng"]), (p["lat"], p["lng"])))
                ordered.append(nxt)
                rest.remove(nxt)
            road_km = sum(haversine((a["lat"], a["lng"]), (b["lat"], b["lng"]))
                          for a, b in zip(ordered, ordered[1:])) * 1.3
            if road_km < 25:
                continue  # zastávky prakticky na jednom místě
            for p in members:
                used.add(id(p))
            routes.append({"theme": theme, "pois": ordered, "km": road_km,
                           "country": seed["country"], "anchor": ordered[0]["name"]})
            made += 1
        print(f"  {theme}: {made} tras")
    return routes


def route_sql(r, sort_order, name_used):
    theme, pois, country = r["theme"], r["pois"], r["country"]
    anchor = r["anchor"]
    base_name = NAME_TPL[theme]["cs"].format(a=anchor)
    name = base_name
    n_sfx = 2
    while name in name_used:
        name = f"{base_name} {['', 'II', 'III', 'IV', 'V'][min(n_sfx - 1, 4)]}".strip()
        n_sfx += 1
    name_used.add(name)

    dist = int(round(r["km"] / 5) * 5)
    dur = int(dist / 55 * 60 + len(pois) * 15)
    diff = "easy" if dist < 140 else ("medium" if dist < 260 else "hard")
    lst = ", ".join(p["name"] for p in pois[:4]) + ("…" if len(pois) > 4 else "")

    def loc_name(p, lang):
        return (p["tr"].get(lang) or {}).get("name") or p["name"]

    tr = {}
    for lang in LANGS[1:]:
        lst_l = ", ".join(loc_name(p, lang) for p in pois[:4]) + ("…" if len(pois) > 4 else "")
        tr[lang] = {
            "name": NAME_TPL[theme][lang].format(a=anchor),
            "description": DESC_TPL[lang].format(country=COUNTRY_NAMES[lang][country],
                                                 list=lst_l, n=len(pois), dist=dist),
        }
    desc = DESC_TPL["cs"].format(country=COUNTRY_NAMES["cs"][country], list=lst, n=len(pois), dist=dist)

    wps = json.dumps([{"lat": p["lat"], "lng": p["lng"], "label": p["name"]} for p in pois],
                     ensure_ascii=False)
    o, d = pois[0], pois[-1]
    mids = "%7C".join(f"{p['lat']},{p['lng']}" for p in pois[1:-1])
    mapy = (f"https://www.google.com/maps/dir/?api=1&origin={o['lat']},{o['lng']}"
            f"&destination={d['lat']},{d['lng']}&travelmode=driving"
            + (f"&waypoints={mids}" if mids else ""))
    imgs = [p["image"] for p in pois if p["image"]]
    cover = f"'{esc(imgs[0])}'" if imgs else "null"
    imgs_arr = "'{" + ",".join('"' + esc(u).replace('"', '') + '"' for u in imgs) + "}'::text[]" if imgs else "'{}'::text[]"
    alts_arr = "'{" + ",".join('"' + esc(p["name"]).replace('"', '') + '"' for p in pois) + "}'::text[]"

    out = []
    out.append('  -- ' + name.replace("'", ''))  # bez apostrofů (kvůli parserům)
    out.append(f"  delete from public.routes where name = '{esc(name)}' and sort_order >= {SORT_BASE};")
    out.append("  v_route := gen_random_uuid();")
    out.append("  insert into public.routes")
    out.append("    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,")
    out.append("     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status, translations)")
    out.append(f"  values (v_route, null, '{esc(name)}', '{esc(desc)}', 'poi', {dist}, {dur}, '{diff}',")
    out.append(f"     '{esc(wps)}'::jsonb, null, '{esc(mapy)}', {cover}, {imgs_arr}, {alts_arr}, "
               f"'{{\"{country}\"}}'::text[], false, {sort_order}, 'approved', '{esc(json.dumps(tr, ensure_ascii=False))}'::jsonb);")
    out.append("  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order, translations) values")
    rows = []
    for i, p in enumerate(pois):
        img = f"'{esc(p['image'])}'" if p["image"] else "null"
        imgs_p = f"'{{\"{esc(p['image']).replace(chr(34), '')}\"}}'::text[]" if p["image"] else "'{}'::text[]"
        rows.append(f"    (v_route, '{esc(p['name'])}', '{esc(p['desc'])}', {p['lat']}, {p['lng']}, "
                    f"{img}, {imgs_p}, {i}, '{esc(json.dumps(p['tr'], ensure_ascii=False))}'::jsonb)")
    out.append(",\n".join(rows) + ";")
    return "\n".join(out)


def main():
    points = load_points()
    print(f"Načteno bodů z katalogových dávek: {len(points)}")
    if len(points) < 1000:
        sys.exit("Podezřele málo bodů — zkontroluj parser.")
    routes = build_clusters(points)
    print(f"Sestaveno tras: {len(routes)}")

    name_used = set()
    for n in range(0, len(routes), ROUTES_PER_FILE):
        chunk = routes[n:n + ROUTES_PER_FILE]
        bno = n // ROUTES_PER_FILE + 1
        body = []
        for i, r in enumerate(chunk):
            body.append(route_sql(r, SORT_BASE + n + i, name_used))
        sql = (
            f"-- MotoGo24 - trasy z katalogu bodu zajmu, davka {bno} ({len(chunk)} tras)\n"
            f"-- Vygenerovano: tools/generate_routes_from_pois.py\n"
            f"-- Trasy is_active=false (admin ve Velinu zkontroluje a publikuje),\n"
            f"-- status='approved', branch_id = null (poloha jezdce = realna GPS).\n"
            f"-- Hromadna aktivace po kontrole:\n"
            f"--   update public.routes set is_active=true where sort_order >= {SORT_BASE} and is_active=false;\n\n"
            "do $$\ndeclare\n  v_route uuid;\nbegin\n"
            + "\n\n".join(body)
            + "\nend $$;\n"
        )
        path = f"supabase/migrations/20260705_routes_from_catalog_batch{bno}.sql"
        with open(path, "w", encoding="utf-8") as f:
            f.write(sql)
        themes = {}
        for r in chunk:
            themes[r["theme"]] = themes.get(r["theme"], 0) + 1
        print(f"  {path}: {len(chunk)} tras {themes}")


if __name__ == "__main__":
    main()
