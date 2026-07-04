#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MotoGo24 — generátor SQL dávek katalogu bodů zájmu (points_of_interest).

Stáhne z Wikidata REÁLNÁ data (ověřené GPS, názvy a popisy v 8 jazycích,
fotky z Wikimedia Commons) pro kategorie: voda (přehrady/jezera), hrady
a zámky, rozhledny, památky, příroda/rezervace — pro CZ / SK / PL / AT.
Seřadí podle významnosti (počet jazykových verzí Wikipedie) a vygeneruje
SQL soubory po dávkách připravené pro Supabase SQL editor.

POUŽITÍ (na počítači s internetem; potřeba `pip install requests`):

    python3 tools/generate_poi_batches.py --target 5000 --batch-size 500

Výstup: supabase/migrations/20260704_poi_catalog_wikidata_batch{N}.sql
Každá dávka je idempotentní (DELETE dle source='wikidata-batchN' + INSERT).
Dávky nasazuj postupně od 1 — dávka 1 obsahuje nejznámější místa.

Pozn.: fotky hotlinkují Commons Special:FilePath — stejně jako seed tras;
zrcadlení do bucketu `media` řeší stejný mechanismus jako u tras (edge fn
mirror-route-images by šlo rozšířit o tabulku points_of_interest).
"""

import argparse
import json
import re
import sys
import time

try:
    import requests
except ImportError:
    sys.exit("Chybí knihovna requests:  pip install requests")

SPARQL = "https://query.wikidata.org/sparql"
UA = "MotoGo24-POI-import/1.0 (info@motogo24.cz)"
LANGS = ["cs", "en", "de", "pl", "nl", "es", "fr", "uk"]

# Wikidata třídy (P31/P279*) → naše kategorie
CATEGORY_CLASSES = {
    "water":   ["Q131681", "Q23397", "Q12323"],          # přehrada, jezero, hráz
    "castle":  ["Q23413", "Q751876", "Q57821"],          # hrad, zámek, pevnost
    "lookout": ["Q641226"],                               # rozhledna / vyhl. věž
    "sights":  ["Q44613", "Q2977", "Q163687", "Q34627"],  # klášter, katedrála, bazilika, synagoga
    "nature":  ["Q179049", "Q46169", "Q35509", "Q34038"], # rezervace, NP, jeskyně, vodopád
}
COUNTRIES = {"CZ": "Q213", "SK": "Q214", "PL": "Q36", "AT": "Q40"}

# Šablony hezkých popisů — {name} = název, {country} = země v daném jazyce.
COUNTRY_NAMES = {
    "cs": {"CZ": "Česku", "SK": "Slovensku", "PL": "Polsku", "AT": "Rakousku"},
    "en": {"CZ": "Czechia", "SK": "Slovakia", "PL": "Poland", "AT": "Austria"},
    "de": {"CZ": "Tschechien", "SK": "der Slowakei", "PL": "Polen", "AT": "Österreich"},
    "pl": {"CZ": "Czechach", "SK": "Słowacji", "PL": "Polsce", "AT": "Austrii"},
    "nl": {"CZ": "Tsjechië", "SK": "Slowakije", "PL": "Polen", "AT": "Oostenrijk"},
    "es": {"CZ": "Chequia", "SK": "Eslovaquia", "PL": "Polonia", "AT": "Austria"},
    "fr": {"CZ": "Tchéquie", "SK": "Slovaquie", "PL": "Pologne", "AT": "Autriche"},
    "uk": {"CZ": "Чехії", "SK": "Словаччині", "PL": "Польщі", "AT": "Австрії"},
}
CATEGORY_SENTENCES = {
    "water": {
        "cs": "Vodní plocha v {country} — příjemný cíl vyjížďky s výhledy na hladinu.",
        "en": "A body of water in {country} — a pleasant ride destination with waterside views.",
        "de": "Ein Gewässer in {country} — ein schönes Ausflugsziel mit Blick aufs Wasser.",
        "pl": "Akwen w {country} — przyjemny cel wycieczki z widokiem na wodę.",
        "nl": "Een waterpartij in {country} — een fijn ritdoel met uitzicht over het water.",
        "es": "Una masa de agua en {country}: un destino agradable con vistas al agua.",
        "fr": "Un plan d''eau en {country} — une belle destination avec vue sur l''eau.",
        "uk": "Водойма в {country} — приємна мета поїздки з краєвидами на воду.",
    },
    "castle": {
        "cs": "Hrad či zámek v {country} — historická zastávka, která stojí za odbočku.",
        "en": "A castle in {country} — a historic stop worth the detour.",
        "de": "Eine Burg bzw. ein Schloss in {country} — ein historischer Halt, der den Umweg lohnt.",
        "pl": "Zamek w {country} — historyczny przystanek wart zjazdu z trasy.",
        "nl": "Een kasteel in {country} — een historische stop die de omweg waard is.",
        "es": "Un castillo en {country}: una parada histórica que merece el desvío.",
        "fr": "Un château en {country} — une halte historique qui vaut le détour.",
        "uk": "Замок у {country} — історична зупинка, варта об''їзду.",
    },
    "lookout": {
        "cs": "Rozhledna v {country} — výhled do kraje jako odměna za zastávku.",
        "en": "A lookout tower in {country} — sweeping views as a reward for stopping.",
        "de": "Ein Aussichtsturm in {country} — weite Ausblicke als Belohnung für den Stopp.",
        "pl": "Wieża widokowa w {country} — rozległe widoki w nagrodę za postój.",
        "nl": "Een uitkijktoren in {country} — weidse uitzichten als beloning voor de stop.",
        "es": "Un mirador en {country}: amplias vistas como recompensa por la parada.",
        "fr": "Une tour panoramique en {country} — un large panorama en récompense de l''arrêt.",
        "uk": "Оглядова вежа в {country} — широкі краєвиди як нагорода за зупинку.",
    },
    "sights": {
        "cs": "Památka v {country} — kus historie přímo u trasy.",
        "en": "A heritage sight in {country} — a piece of history right on your route.",
        "de": "Ein Denkmal in {country} — ein Stück Geschichte direkt an der Route.",
        "pl": "Zabytek w {country} — kawałek historii tuż przy trasie.",
        "nl": "Een monument in {country} — een stuk geschiedenis vlak aan de route.",
        "es": "Un monumento en {country}: un pedazo de historia junto a la ruta.",
        "fr": "Un monument en {country} — un morceau d''histoire au bord de la route.",
        "uk": "Пам''ятка в {country} — шматочок історії просто на маршруті.",
    },
    "nature": {
        "cs": "Přírodní zajímavost v {country} — místo na protažení nohou uprostřed přírody.",
        "en": "A natural sight in {country} — a spot to stretch your legs amid nature.",
        "de": "Eine Natursehenswürdigkeit in {country} — ein Ort zum Beinevertreten mitten in der Natur.",
        "pl": "Atrakcja przyrodnicza w {country} — miejsce na rozprostowanie nóg pośród natury.",
        "nl": "Een natuurbezienswaardigheid in {country} — een plek om de benen te strekken in de natuur.",
        "es": "Un paraje natural en {country}: un lugar para estirar las piernas en plena naturaleza.",
        "fr": "Un site naturel en {country} — un endroit où se dégourdir les jambes en pleine nature.",
        "uk": "Природна пам''ятка в {country} — місце розім''яти ноги серед природи.",
    },
}

# Hranice zemí pro kontrolu souřadnic (lat_min, lat_max, lng_min, lng_max)
BBOX = {
    "CZ": (48.5, 51.1, 12.0, 18.9),
    "SK": (47.7, 49.7, 16.8, 22.6),
    "PL": (49.0, 54.9, 14.1, 24.2),
    "AT": (46.3, 49.1, 9.5, 17.2),
}


def sparql(query, retries=4):
    for attempt in range(retries):
        try:
            r = requests.get(
                SPARQL,
                params={"query": query, "format": "json"},
                headers={"User-Agent": UA},
                timeout=120,
            )
            if r.status_code == 429:
                wait = int(r.headers.get("Retry-After", "10"))
                time.sleep(wait)
                continue
            r.raise_for_status()
            return r.json()["results"]["bindings"]
        except Exception as e:  # noqa: BLE001
            if attempt == retries - 1:
                raise
            print(f"  ! {e} — retry za {2 ** attempt * 5}s", file=sys.stderr)
            time.sleep(2 ** attempt * 5)
    return []


def fetch_category(cat, classes, iso, country_qid, limit):
    """Stáhne položky jedné kategorie v jedné zemi vč. labelů 8 jazyků."""
    label_vars = " ".join(f"?l_{l}" for l in LANGS)
    label_opts = "\n".join(
        f'  OPTIONAL {{ ?item rdfs:label ?l_{l} . FILTER(lang(?l_{l}) = "{l}") }}'
        for l in LANGS
    )
    desc_opts = "\n".join(
        f'  OPTIONAL {{ ?item schema:description ?d_{l} . FILTER(lang(?d_{l}) = "{l}") }}'
        for l in LANGS
    )
    desc_vars = " ".join(f"?d_{l}" for l in LANGS)
    values = " ".join(f"wd:{q}" for q in classes)
    q = f"""
SELECT ?item ?lat ?lon ?sl ?img {label_vars} {desc_vars} WHERE {{
  VALUES ?cls {{ {values} }}
  ?item wdt:P31/wdt:P279* ?cls ;
        wdt:P17 wd:{country_qid} ;
        p:P625 [ psv:P625 [ wikibase:geoLatitude ?lat ; wikibase:geoLongitude ?lon ] ] ;
        wikibase:sitelinks ?sl .
  OPTIONAL {{ ?item wdt:P18 ?img }}
{label_opts}
{desc_opts}
}}
ORDER BY DESC(?sl)
LIMIT {limit}
"""
    rows = sparql(q)
    out = {}
    for b in rows:
        qid = b["item"]["value"].rsplit("/", 1)[-1]
        if qid in out:
            continue
        lat, lon = float(b["lat"]["value"]), float(b["lon"]["value"])
        lo = BBOX[iso]
        if not (lo[0] <= lat <= lo[1] and lo[2] <= lon <= lo[3]):
            continue  # souřadnice mimo zemi → data jsou podezřelá, přeskoč
        labels = {l: b.get(f"l_{l}", {}).get("value") for l in LANGS}
        descs = {l: b.get(f"d_{l}", {}).get("value") for l in LANGS}
        name = labels["cs"] or labels["en"] or labels["de"]
        if not name or re.match(r"^Q\d+$", name):
            continue  # bez použitelného názvu nemá v katalogu smysl
        out[qid] = {
            "qid": qid,
            "category": cat,
            "country": iso,
            "name": name,
            "lat": round(lat, 5),
            "lng": round(lon, 5),
            "sitelinks": int(b["sl"]["value"]),
            "image": b.get("img", {}).get("value"),
            "labels": labels,
            "descs": descs,
        }
    return list(out.values())


def esc(s):
    return s.replace("'", "''")


def build_description(item, lang):
    """Hezký popis: šablona kategorie + (je-li) popis z Wikidata."""
    tpl = CATEGORY_SENTENCES[item["category"]][lang]
    country = COUNTRY_NAMES[lang][item["country"]]
    sentence = tpl.replace("{country}", country).replace("''", "'")
    wd = item["descs"].get(lang)
    if wd:
        wd = wd[0].upper() + wd[1:]
        if not wd.endswith("."):
            wd += "."
        return f"{wd} {sentence}"
    return sentence


def to_sql_row(item):
    name = esc(item["name"])
    desc_cs = esc(build_description(item, "cs"))
    tr = {}
    for l in LANGS[1:]:
        tr[l] = {
            "name": item["labels"].get(l) or item["name"],
            "description": build_description(item, l),
        }
    tr_json = esc(json.dumps(tr, ensure_ascii=False))
    img = f"'{esc(item['image'])}'" if item["image"] else "null"
    return (
        f"('{item['category']}', '{name}', '{desc_cs}', "
        f"{item['lat']}, {item['lng']}, '{item['country']}', "
        f"'{{SOURCE}}', {{SORT}}, {img}, '{tr_json}'::jsonb)"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=int, default=5000, help="celkem bodů")
    ap.add_argument("--batch-size", type=int, default=500)
    ap.add_argument("--outdir", default="supabase/migrations")
    ap.add_argument("--per-query-limit", type=int, default=3000)
    args = ap.parse_args()

    items = {}
    for cat, classes in CATEGORY_CLASSES.items():
        for iso, qid in COUNTRIES.items():
            print(f"Stahuji {cat} / {iso} …", flush=True)
            for it in fetch_category(cat, classes, iso, qid, args.per_query_limit):
                # při kolizi kategorií vyhrává specifičtější (první výskyt)
                items.setdefault(it["qid"], it)
            time.sleep(2)  # ohleduplnost k WDQS

    ranked = sorted(items.values(), key=lambda x: -x["sitelinks"])[: args.target]
    print(f"Celkem kandidátů: {len(items)}, vybráno: {len(ranked)}")

    for n in range(0, len(ranked), args.batch_size):
        batch_no = n // args.batch_size + 1
        chunk = ranked[n : n + args.batch_size]
        source = f"wikidata-batch{batch_no}"
        rows = []
        for i, it in enumerate(chunk):
            row = to_sql_row(it)
            row = row.replace("{SOURCE}", source).replace("{SORT}", str(1000 + n + i))
            rows.append(row)
        body = ",\n".join(rows)
        sql = (
            f"-- MotoGo24 - katalog bodu zajmu z Wikidata, davka {batch_no}"
            f" ({len(chunk)} bodu, razeno dle vyznamnosti)\n"
            f"-- Vygenerovano: tools/generate_poi_batches.py (idempotentni)\n\n"
            f"delete from public.points_of_interest where source = '{source}';\n\n"
            f"insert into public.points_of_interest\n"
            f"  (category, name, description, lat, lng, country, source, sort_order, image_url, translations)\n"
            f"values\n{body};\n"
        )
        path = f"{args.outdir}/20260704_poi_catalog_wikidata_batch{batch_no}.sql"
        with open(path, "w", encoding="utf-8") as f:
            f.write(sql)
        cats = {}
        for it in chunk:
            cats[it["category"]] = cats.get(it["category"], 0) + 1
        print(f"  {path}: {len(chunk)} bodů {cats}")

    print("Hotovo. Dávky nasazuj v Supabase postupně od 1.")


if __name__ == "__main__":
    main()
