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
# Pořadí = priorita při kolizi (bod padne do PRVNÍ kategorie, která ho stáhne)
# — specifické kategorie cílovky (moto/aviation/military/tech) proto stojí
# před obecnými. POZOR: pro military NEpoužívat Q57821 (fortification) —
# hrad (Q23413) je jeho podtřída a ukradl by celou kategorii castle.
CATEGORY_CLASSES = {
    "moto":     ["Q1777138", "Q787934"],                  # závodní okruh, automobilové/moto muzeum
    "aviation": ["Q4828724", "Q62447"],                   # letecké muzeum, letiště/aerodrom
    "military": ["Q2772772", "Q91122", "Q1785071",        # vojenské muzeum, bunkr, fort
                 "Q4895508"],                             # bojiště
    "tech":     ["Q2398990", "Q18704634", "Q819426",      # technické, železniční, hornické muzeum
                 "Q820477", "Q420962", "Q2516357"],       # důl, nostalgická železnice, muzeum dopravy
    "water":   ["Q131681", "Q23397", "Q12323"],          # přehrada, jezero, hráz
    "castle":  ["Q23413", "Q751876", "Q57821"],          # hrad, zámek, pevnost
    "lookout": ["Q1440300", "Q2075301", "Q6017969"],      # rozhledna, výhled, vyhlídkové místo
    "sights":  ["Q44613", "Q2977", "Q163687", "Q34627",   # klášter, katedrála, bazilika, synagoga
                "Q33506", "Q756102", "Q43501"],           # muzeum, skanzen, zoo
    "nature":  ["Q179049", "Q46169", "Q35509", "Q34038",  # rezervace, NP, jeskyně, vodopád
                "Q133056", "Q23790", "Q167346"],          # průsmyk, přírodní památka, botanická zahrada
}
# Všechny podporované země (ISO → Wikidata QID). Výběr přes --countries.
ALL_COUNTRIES = {
    "CZ": "Q213", "SK": "Q214", "PL": "Q36", "AT": "Q40",
    "DE": "Q183", "FR": "Q142", "IT": "Q38", "ES": "Q29", "GB": "Q145",
    "NL": "Q55", "BE": "Q31", "CH": "Q39", "SI": "Q215", "HR": "Q224",
    "HU": "Q28", "RO": "Q218", "RS": "Q403", "GR": "Q41", "PT": "Q45",
    "IE": "Q27", "DK": "Q35", "SE": "Q34", "NO": "Q20", "FI": "Q33",
}

# Šablony hezkých popisů — {name} = název, {country} = země v daném jazyce.
COUNTRY_NAMES = {
    "cs": {"CZ": "v Česku", "SK": "na Slovensku", "PL": "v Polsku", "AT": "v Rakousku",
           "DE": "v Německu", "FR": "ve Francii", "IT": "v Itálii", "ES": "ve Španělsku",
           "GB": "ve Velké Británii", "NL": "v Nizozemsku", "BE": "v Belgii", "CH": "ve Švýcarsku",
           "SI": "ve Slovinsku", "HR": "v Chorvatsku", "HU": "v Maďarsku", "RO": "v Rumunsku",
           "RS": "v Srbsku", "GR": "v Řecku", "PT": "v Portugalsku", "IE": "v Irsku",
           "DK": "v Dánsku", "SE": "ve Švédsku", "NO": "v Norsku", "FI": "ve Finsku"},
    "en": {"CZ": "in Czechia", "SK": "in Slovakia", "PL": "in Poland", "AT": "in Austria",
           "DE": "in Germany", "FR": "in France", "IT": "in Italy", "ES": "in Spain",
           "GB": "in the United Kingdom", "NL": "in the Netherlands", "BE": "in Belgium",
           "CH": "in Switzerland", "SI": "in Slovenia", "HR": "in Croatia", "HU": "in Hungary",
           "RO": "in Romania", "RS": "in Serbia", "GR": "in Greece", "PT": "in Portugal",
           "IE": "in Ireland", "DK": "in Denmark", "SE": "in Sweden", "NO": "in Norway",
           "FI": "in Finland"},
    "de": {"CZ": "in Tschechien", "SK": "in der Slowakei", "PL": "in Polen", "AT": "in Österreich",
           "DE": "in Deutschland", "FR": "in Frankreich", "IT": "in Italien", "ES": "in Spanien",
           "GB": "in Großbritannien", "NL": "in den Niederlanden", "BE": "in Belgien",
           "CH": "in der Schweiz", "SI": "in Slowenien", "HR": "in Kroatien", "HU": "in Ungarn",
           "RO": "in Rumänien", "RS": "in Serbien", "GR": "in Griechenland", "PT": "in Portugal",
           "IE": "in Irland", "DK": "in Dänemark", "SE": "in Schweden", "NO": "in Norwegen",
           "FI": "in Finnland"},
    "pl": {"CZ": "w Czechach", "SK": "na Słowacji", "PL": "w Polsce", "AT": "w Austrii",
           "DE": "w Niemczech", "FR": "we Francji", "IT": "we Włoszech", "ES": "w Hiszpanii",
           "GB": "w Wielkiej Brytanii", "NL": "w Holandii", "BE": "w Belgii", "CH": "w Szwajcarii",
           "SI": "w Słowenii", "HR": "w Chorwacji", "HU": "na Węgrzech", "RO": "w Rumunii",
           "RS": "w Serbii", "GR": "w Grecji", "PT": "w Portugalii", "IE": "w Irlandii",
           "DK": "w Danii", "SE": "w Szwecji", "NO": "w Norwegii", "FI": "w Finlandii"},
    "nl": {"CZ": "in Tsjechië", "SK": "in Slowakije", "PL": "in Polen", "AT": "in Oostenrijk",
           "DE": "in Duitsland", "FR": "in Frankrijk", "IT": "in Italië", "ES": "in Spanje",
           "GB": "in het Verenigd Koninkrijk", "NL": "in Nederland", "BE": "in België",
           "CH": "in Zwitserland", "SI": "in Slovenië", "HR": "in Kroatië", "HU": "in Hongarije",
           "RO": "in Roemenië", "RS": "in Servië", "GR": "in Griekenland", "PT": "in Portugal",
           "IE": "in Ierland", "DK": "in Denemarken", "SE": "in Zweden", "NO": "in Noorwegen",
           "FI": "in Finland"},
    "es": {"CZ": "en Chequia", "SK": "en Eslovaquia", "PL": "en Polonia", "AT": "en Austria",
           "DE": "en Alemania", "FR": "en Francia", "IT": "en Italia", "ES": "en España",
           "GB": "en el Reino Unido", "NL": "en los Países Bajos", "BE": "en Bélgica",
           "CH": "en Suiza", "SI": "en Eslovenia", "HR": "en Croacia", "HU": "en Hungría",
           "RO": "en Rumanía", "RS": "en Serbia", "GR": "en Grecia", "PT": "en Portugal",
           "IE": "en Irlanda", "DK": "en Dinamarca", "SE": "en Suecia", "NO": "en Noruega",
           "FI": "en Finlandia"},
    "fr": {"CZ": "en Tchéquie", "SK": "en Slovaquie", "PL": "en Pologne", "AT": "en Autriche",
           "DE": "en Allemagne", "FR": "en France", "IT": "en Italie", "ES": "en Espagne",
           "GB": "au Royaume-Uni", "NL": "aux Pays-Bas", "BE": "en Belgique", "CH": "en Suisse",
           "SI": "en Slovénie", "HR": "en Croatie", "HU": "en Hongrie", "RO": "en Roumanie",
           "RS": "en Serbie", "GR": "en Grèce", "PT": "au Portugal", "IE": "en Irlande",
           "DK": "au Danemark", "SE": "en Suède", "NO": "en Norvège", "FI": "en Finlande"},
    "uk": {"CZ": "в Чехії", "SK": "у Словаччині", "PL": "у Польщі", "AT": "в Австрії",
           "DE": "в Німеччині", "FR": "у Франції", "IT": "в Італії", "ES": "в Іспанії",
           "GB": "у Великій Британії", "NL": "в Нідерландах", "BE": "у Бельгії",
           "CH": "у Швейцарії", "SI": "у Словенії", "HR": "у Хорватії", "HU": "в Угорщині",
           "RO": "в Румунії", "RS": "в Сербії", "GR": "у Греції", "PT": "в Португалії",
           "IE": "в Ірландії", "DK": "в Данії", "SE": "у Швеції", "NO": "в Норвегії",
           "FI": "у Фінляндії"},
}
CATEGORY_SENTENCES = {
    "water": {
        "cs": "Vodní plocha {country} — příjemný cíl vyjížďky s výhledy na hladinu.",
        "en": "A body of water {country} — a pleasant ride destination with waterside views.",
        "de": "Ein Gewässer {country} — ein schönes Ausflugsziel mit Blick aufs Wasser.",
        "pl": "Akwen {country} — przyjemny cel wycieczki z widokiem na wodę.",
        "nl": "Een waterpartij {country} — een fijn ritdoel met uitzicht over het water.",
        "es": "Una masa de agua {country}: un destino agradable con vistas al agua.",
        "fr": "Un plan d''eau {country} — une belle destination avec vue sur l''eau.",
        "uk": "Водойма {country} — приємна мета поїздки з краєвидами на воду.",
    },
    "castle": {
        "cs": "Hrad či zámek {country} — historická zastávka, která stojí za odbočku.",
        "en": "A castle {country} — a historic stop worth the detour.",
        "de": "Eine Burg bzw. ein Schloss {country} — ein historischer Halt, der den Umweg lohnt.",
        "pl": "Zamek {country} — historyczny przystanek wart zjazdu z trasy.",
        "nl": "Een kasteel {country} — een historische stop die de omweg waard is.",
        "es": "Un castillo {country}: una parada histórica que merece el desvío.",
        "fr": "Un château {country} — une halte historique qui vaut le détour.",
        "uk": "Замок {country} — історична зупинка, варта об''їзду.",
    },
    "lookout": {
        "cs": "Rozhledna {country} — výhled do kraje jako odměna za zastávku.",
        "en": "A lookout tower {country} — sweeping views as a reward for stopping.",
        "de": "Ein Aussichtsturm {country} — weite Ausblicke als Belohnung für den Stopp.",
        "pl": "Wieża widokowa {country} — rozległe widoki w nagrodę za postój.",
        "nl": "Een uitkijktoren {country} — weidse uitzichten als beloning voor de stop.",
        "es": "Un mirador {country}: amplias vistas como recompensa por la parada.",
        "fr": "Une tour panoramique {country} — un large panorama en récompense de l''arrêt.",
        "uk": "Оглядова вежа {country} — широкі краєвиди як нагорода за зупинку.",
    },
    "sights": {
        "cs": "Památka {country} — kus historie přímo u trasy.",
        "en": "A heritage sight {country} — a piece of history right on your route.",
        "de": "Ein Denkmal {country} — ein Stück Geschichte direkt an der Route.",
        "pl": "Zabytek {country} — kawałek historii tuż przy trasie.",
        "nl": "Een monument {country} — een stuk geschiedenis vlak aan de route.",
        "es": "Un monumento {country}: un pedazo de historia junto a la ruta.",
        "fr": "Un monument {country} — un morceau d''histoire au bord de la route.",
        "uk": "Пам''ятка {country} — шматочок історії просто на маршруті.",
    },
    "nature": {
        "cs": "Přírodní zajímavost {country} — místo na protažení nohou uprostřed přírody.",
        "en": "A natural sight {country} — a spot to stretch your legs amid nature.",
        "de": "Eine Natursehenswürdigkeit {country} — ein Ort zum Beinevertreten mitten in der Natur.",
        "pl": "Atrakcja przyrodnicza {country} — miejsce na rozprostowanie nóg pośród natury.",
        "nl": "Een natuurbezienswaardigheid {country} — een plek om de benen te strekken in de natuur.",
        "es": "Un paraje natural {country}: un lugar para estirar las piernas en plena naturaleza.",
        "fr": "Un site naturel {country} — un endroit où se dégourdir les jambes en pleine nature.",
        "uk": "Природна пам''ятка {country} — місце розім''яти ноги серед природи.",
    },
    "military": {
        "cs": "Vojenská historie {country} — opevnění, technika a příběhy, které stojí za zastávku.",
        "en": "Military history {country} — fortifications, hardware and stories worth the stop.",
        "de": "Militärgeschichte {country} — Befestigungen, Technik und Geschichten, die den Halt lohnen.",
        "pl": "Historia wojskowa {country} — fortyfikacje, sprzęt i historie warte postoju.",
        "nl": "Militaire geschiedenis {country} — vestingwerken, materieel en verhalen die de stop waard zijn.",
        "es": "Historia militar {country}: fortificaciones, material y relatos que merecen la parada.",
        "fr": "Histoire militaire {country} — fortifications, matériel et récits qui valent l''arrêt.",
        "uk": "Військова історія {country} — укріплення, техніка та історії, варті зупинки.",
    },
    "aviation": {
        "cs": "Letecký cíl {country} — letadla zblízka a vůně ranveje, oblíbená motorkářská zastávka.",
        "en": "An aviation sight {country} — aircraft up close and runway vibes, a favourite riders'' stop.",
        "de": "Ein Luftfahrt-Ziel {country} — Flugzeuge hautnah und Flugplatz-Flair, ein beliebter Bikerstopp.",
        "pl": "Cel lotniczy {country} — samoloty z bliska i klimat pasa startowego, ulubiony przystanek motocyklistów.",
        "nl": "Een luchtvaartdoel {country} — vliegtuigen van dichtbij en start­baansfeer, favoriete stop van motorrijders.",
        "es": "Un destino aeronáutico {country}: aviones de cerca y ambiente de pista, parada favorita de moteros.",
        "fr": "Un site aéronautique {country} — des avions de près et l''ambiance des pistes, un arrêt apprécié des motards.",
        "uk": "Авіаційна пам''ятка {country} — літаки зблизька й атмосфера злітної смуги, улюблена зупинка мотоциклістів.",
    },
    "tech": {
        "cs": "Technická památka {country} — doly, železnice a stroje, na kterých stojí historie kraje.",
        "en": "A technical monument {country} — mines, railways and machines behind the region''s history.",
        "de": "Ein technisches Denkmal {country} — Bergwerke, Bahnen und Maschinen der Regionalgeschichte.",
        "pl": "Zabytek techniki {country} — kopalnie, koleje i maszyny, na których stoi historia regionu.",
        "nl": "Een technisch monument {country} — mijnen, spoorwegen en machines achter de streekgeschiedenis.",
        "es": "Un monumento técnico {country}: minas, ferrocarriles y máquinas de la historia local.",
        "fr": "Un monument technique {country} — mines, chemins de fer et machines qui ont fait l''histoire locale.",
        "uk": "Технічна пам''ятка {country} — шахти, залізниці й машини, на яких стоїть історія краю.",
    },
    "moto": {
        "cs": "Motoristický cíl {country} — rychlost, okruhy a legendy motorismu na dosah.",
        "en": "A motorsport sight {country} — speed, circuits and motoring legends within reach.",
        "de": "Ein Motorsport-Ziel {country} — Geschwindigkeit, Rennstrecken und Legenden zum Anfassen.",
        "pl": "Cel motoryzacyjny {country} — prędkość, tory i legendy motoryzacji na wyciągnięcie ręki.",
        "nl": "Een autosportdoel {country} — snelheid, circuits en motorlegendes binnen handbereik.",
        "es": "Un destino del motor {country}: velocidad, circuitos y leyendas del motor al alcance.",
        "fr": "Un site du sport mécanique {country} — vitesse, circuits et légendes de la moto à portée de main.",
        "uk": "Мотоспортивна пам''ятка {country} — швидкість, треки й легенди автоспорту поруч.",
    },
}

# Hranice zemí pro kontrolu souřadnic (lat_min, lat_max, lng_min, lng_max).
# U FR/ES/PT/NO jde o pevninu (vyřadí zámořská území / ostrovy mimo dosah tras).
BBOX = {
    "CZ": (48.5, 51.1, 12.0, 18.9),
    "SK": (47.7, 49.7, 16.8, 22.6),
    "PL": (49.0, 54.9, 14.1, 24.2),
    "AT": (46.3, 49.1, 9.5, 17.2),
    "DE": (47.2, 55.1, 5.8, 15.1),
    "FR": (41.2, 51.2, -5.2, 9.7),
    "IT": (35.4, 47.2, 6.6, 18.6),
    "ES": (35.9, 43.9, -9.4, 4.4),
    "GB": (49.8, 60.9, -8.7, 1.8),
    "NL": (50.7, 53.6, 3.3, 7.3),
    "BE": (49.5, 51.6, 2.5, 6.5),
    "CH": (45.8, 47.9, 5.9, 10.6),
    "SI": (45.4, 46.9, 13.3, 16.7),
    "HR": (42.3, 46.6, 13.4, 19.5),
    "HU": (45.7, 48.6, 16.0, 23.0),
    "RO": (43.6, 48.3, 20.2, 29.8),
    "RS": (42.2, 46.2, 18.8, 23.1),
    "GR": (34.7, 41.8, 19.3, 28.3),
    "PT": (36.9, 42.2, -9.6, -6.1),
    "IE": (51.4, 55.5, -10.7, -5.9),
    "DK": (54.5, 57.8, 8.0, 15.3),
    "SE": (55.3, 69.1, 10.9, 24.2),
    "NO": (57.9, 71.3, 4.5, 31.2),
    "FI": (59.7, 70.1, 19.3, 31.6),
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


def fetch_category(cat, classes, iso, country_qid, limit, minsl=1):
    """FÁZE 1: lehký SPARQL — jen QID, GPS, významnost a fotka (bez labelů;
    16 OPTIONAL labelů v jednom dotazu WDQS neutáhne → 502)."""
    rows = []
    for cls in classes:  # po jedné třídě — velké země (DE/FR/IT) jinak timeoutují
        q = f"""
SELECT ?item ?lat ?lon ?sl (SAMPLE(?im) AS ?img) WHERE {{
  ?item wdt:P31/wdt:P279* wd:{cls} ;
        wdt:P17 wd:{country_qid} ;
        p:P625 [ psv:P625 [ wikibase:geoLatitude ?lat ; wikibase:geoLongitude ?lon ] ] ;
        wikibase:sitelinks ?sl .
  FILTER(?sl >= {minsl})
  OPTIONAL {{ ?item wdt:P18 ?im }}
}}
GROUP BY ?item ?lat ?lon ?sl
ORDER BY DESC(?sl)
LIMIT {limit}
""".replace("{minsl}", str(minsl))
        try:
            rows.extend(sparql(q))
        except Exception as e:  # noqa: BLE001
            print(f"  ! třída {cls} přeskočena ({str(e)[:50]})", file=sys.stderr)
        time.sleep(1)
    out = {}
    for b in rows:
        qid = b["item"]["value"].rsplit("/", 1)[-1]
        if qid in out:
            continue
        lat, lon = float(b["lat"]["value"]), float(b["lon"]["value"])
        lo = BBOX[iso]
        if not (lo[0] <= lat <= lo[1] and lo[2] <= lon <= lo[3]):
            continue  # souřadnice mimo zemi → data jsou podezřelá, přeskoč
        out[qid] = {
            "qid": qid,
            "category": cat,
            "country": iso,
            "name": None,  # doplní fetch_labels
            "lat": round(lat, 5),
            "lng": round(lon, 5),
            "sitelinks": int(b["sl"]["value"]),
            "image": b.get("img", {}).get("value"),
            "labels": {},
            "descs": {},
        }
    return list(out.values())


def fetch_labels(items, chunk=50):
    """FÁZE 2: labely + popisy 8 jazyků přes wbgetentities (spolehlivé, po 50)."""
    ids = [it["qid"] for it in items]
    by_qid = {it["qid"]: it for it in items}
    for i in range(0, len(ids), chunk):
        batch = ids[i : i + chunk]
        for attempt in range(4):
            try:
                r = requests.get(
                    "https://www.wikidata.org/w/api.php",
                    params={
                        "action": "wbgetentities",
                        "ids": "|".join(batch),
                        "props": "labels|descriptions",
                        "languages": "|".join(LANGS),
                        "format": "json",
                    },
                    headers={"User-Agent": UA},
                    timeout=60,
                ).json()
                for qid, ent in r.get("entities", {}).items():
                    it = by_qid.get(qid)
                    if not it:
                        continue
                    labs = ent.get("labels", {})
                    dscs = ent.get("descriptions", {})
                    it["labels"] = {l: labs.get(l, {}).get("value") for l in LANGS}
                    it["descs"] = {l: dscs.get(l, {}).get("value") for l in LANGS}
                    it["name"] = (
                        it["labels"].get("cs") or it["labels"].get("en")
                        or it["labels"].get("de") or it["labels"].get("pl")
                    )
                break
            except Exception as e:  # noqa: BLE001
                if attempt == 3:
                    raise
                print(f"  ! labels {e} — retry", file=sys.stderr)
                time.sleep(2 ** attempt * 3)
        if (i // chunk) % 10 == 0:
            print(f"  labely {i + len(batch)}/{len(ids)}", flush=True)
        time.sleep(0.3)


def esc(s):
    return s.replace("'", "''")


def load_existing_points(outdir):
    """Body již přítomné v katalogových SQL dávkách (dedup nových importů).
    Vrací (množina (name_lower, country), mřížkový index souřadnic)."""
    import glob as _glob
    names = set()
    grid = {}
    row_re = re.compile(
        r"\('(\w+)', '((?:[^']|'')*)', '(?:[^']|'')*', (-?[\d.]+), (-?[\d.]+), '(\w\w)'")
    for f in _glob.glob(f"{outdir}/*poi_catalog*batch*.sql"):
        for m in row_re.finditer(open(f, encoding="utf-8").read()):
            name = m.group(2).replace("''", "'").lower()
            lat, lng, iso = float(m.group(3)), float(m.group(4)), m.group(5)
            names.add((name, iso))
            grid.setdefault((round(lat, 2), round(lng, 2)), []).append((lat, lng))
    return names, grid


def is_duplicate(item, names, grid, radius_km=0.3):
    if ((item["name"] or "").lower(), item["country"]) in names:
        return True
    la, ln = item["lat"], item["lng"]
    cell = (round(la, 2), round(ln, 2))
    for dy in (-0.01, 0.0, 0.01):
        for dx in (-0.01, 0.0, 0.01):
            for (elat, elng) in grid.get((round(cell[0] + dy, 2), round(cell[1] + dx, 2)), []):
                dkm = ((la - elat) * 111.0) ** 2 + ((ln - elng) * 111.0 * 0.67) ** 2
                if dkm <= radius_km ** 2:
                    return True
    return False


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
    ap.add_argument("--countries", default="CZ,SK,PL,AT",
                    help="CSV ISO kódů (viz ALL_COUNTRIES)")
    ap.add_argument("--source-prefix", default="wikidata-batch",
                    help="prefix source tagu (idempotence dávek)")
    ap.add_argument("--file-prefix", default="20260704_poi_catalog_wikidata_batch",
                    help="prefix názvu SQL souborů")
    ap.add_argument("--sort-offset", type=int, default=1000)
    ap.add_argument("--min-sitelinks", type=int, default=1)
    ap.add_argument("--categories", default="",
                    help="CSV kategorií k fetchi (prázdné = všechny)")
    ap.add_argument("--dedup-existing", action="store_true",
                    help="přeskočit body, které už jsou v katalogových dávkách")
    args = ap.parse_args()

    cats_filter = {c.strip() for c in args.categories.split(",") if c.strip()}
    for c in cats_filter:
        if c not in CATEGORY_CLASSES:
            sys.exit(f"Neznámá kategorie: {c} (podporované: {', '.join(CATEGORY_CLASSES)})")

    countries = {}
    for iso in args.countries.split(","):
        iso = iso.strip().upper()
        if iso not in ALL_COUNTRIES:
            sys.exit(f"Neznámá země: {iso} (podporované: {', '.join(ALL_COUNTRIES)})")
        countries[iso] = ALL_COUNTRIES[iso]

    existing_names, existing_grid = (set(), {})
    if args.dedup_existing:
        existing_names, existing_grid = load_existing_points(args.outdir)
        print(f"Dedup: {len(existing_names)} bodů už v katalogových dávkách")

    items = {}
    for cat, classes in CATEGORY_CLASSES.items():
        if cats_filter and cat not in cats_filter:
            continue
        for iso, qid in countries.items():
            print(f"Stahuji {cat} / {iso} …", flush=True)
            for it in fetch_category(cat, classes, iso, qid, args.per_query_limit, args.min_sitelinks):
                # při kolizi kategorií vyhrává specifičtější (první výskyt)
                items.setdefault(it["qid"], it)
            time.sleep(2)  # ohleduplnost k WDQS

    if args.dedup_existing:
        before = len(items)
        items = {q: it for q, it in items.items()
                 if not is_duplicate(it, existing_names, existing_grid)}
        print(f"Dedup souřadnicí: {before} → {len(items)}")

    ranked = sorted(items.values(), key=lambda x: -x["sitelinks"])[: args.target]
    print(f"Celkem kandidátů: {len(items)}, vybráno: {len(ranked)}")

    print("Stahuji názvy a popisy (8 jazyků) …", flush=True)
    fetch_labels(ranked)
    ranked = [it for it in ranked if it["name"] and not re.match(r"^Q\d+$", it["name"])]
    if args.dedup_existing:  # jménem lze dedupovat až po stažení labelů
        ranked = [it for it in ranked
                  if (it["name"].lower(), it["country"]) not in existing_names]

    # Bezpečnost: AKTIVNÍ vojenské letecké základny neseedovat (vstup zakázán);
    # bývalé/opuštěné a muzejní ponechat — to jsou naopak skvělé cíle.
    re_base = re.compile(r"air (force )?base|military air|letecká základna|fliegerhorst|"
                         r"militärflugplatz|air station|baza lotnicza", re.I)
    re_former = re.compile(r"former|abandoned|býval|zanikl|ehemalig|disused|closed|"
                           r"dawn[ay]|muzeum|museum|heritage", re.I)
    def _active_base(it):
        blob = " ".join(filter(None, [it["name"]] + list(it["descs"].values())))
        return bool(re_base.search(blob)) and not re_former.search(blob)
    before = len(ranked)
    ranked = [it for it in ranked if it["category"] != "aviation" or not _active_base(it)]
    if before != len(ranked):
        print(f"Vyřazeno aktivních vojenských základen: {before - len(ranked)}")
    print(f"Po doplnění labelů použitelných: {len(ranked)}")

    for n in range(0, len(ranked), args.batch_size):
        batch_no = n // args.batch_size + 1
        chunk = ranked[n : n + args.batch_size]
        source = f"{args.source_prefix}{batch_no}"
        rows = []
        for i, it in enumerate(chunk):
            row = to_sql_row(it)
            row = row.replace("{SOURCE}", source).replace("{SORT}", str(args.sort_offset + n + i))
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
        path = f"{args.outdir}/{args.file_prefix}{batch_no}.sql"
        with open(path, "w", encoding="utf-8") as f:
            f.write(sql)
        cats = {}
        for it in chunk:
            cats[it["category"]] = cats.get(it["category"], 0) + 1
        print(f"  {path}: {len(chunk)} bodů {cats}")

    print("Hotovo. Dávky nasazuj v Supabase postupně od 1.")


if __name__ == "__main__":
    main()
