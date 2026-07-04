#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MotoGo24 — doplnění bodů zájmu do dlouhých prázdných úseků tras.

Trasy jako „Sozopol a jižní Černomoří" měly body zájmu nahloučené v jednom
místě a 30-250 km dlouhé úseky bez jediné zastávky. Skript:
  - zrekonstruuje živý stav tras z migrací (waypointy z 20260704 fixu,
    route_pois ze seedů + korekce, přejmenování z postseed fixes),
  - najde úseky >= 30 km bez POI a doplní do nich body z katalogu
    points_of_interest (<= 7 km od čáry, nejznámější první, max 8/trasu),
  - přidá ručně kurátorované body z tools/route_poi_gap_curated.json
    (země bez katalogu: BG, EE, LT, MD, MK — souřadnice ověřeny proti webu),
  - přečísluje sort_order dle pořadí na trase a přegeneruje waypoints,
    distance_km/duration_min (odchylka > 15 %), mapy_url, geometry=null.

POUŽITÍ (z kořene repa):
    python3 tools/fill_route_poi_gaps.py
Výstup: supabase/migrations/20260705_route_pois_fill_gaps.sql
        + tools/route_poi_gap_report.txt
"""
import glob, json, math, os, re, sys, unicodedata, collections

import glob, json, math, re, unicodedata, collections

REPO = ""
MIG = REPO + "supabase/migrations/"

def haversine(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371 * 2 * math.asin(math.sqrt(h))

def norm(s):
    s = unicodedata.normalize('NFD', s.lower())
    return ''.join(c for c in s if unicodedata.category(c) != 'Mn')

def sqlesc(s):
    return s.replace("'", "''")

def load_routes():
    """name -> {waypoints:[(lat,lng,label)], distance_km, duration_min, pois:[{name,desc,lat,lng,sort,image,images_raw}], country}"""
    routes = {}
    fix = open(MIG + "20260704_routes_fix_waypoints_pois.sql", encoding="utf-8").read()
    wp_re = re.compile(r"update public\.routes set waypoints = '(\[.*?\])'::jsonb(.*?) where name = '((?:[^']|'')*)';")
    for m in wp_re.finditer(fix):
        wps = json.loads(m.group(1))
        rest, name = m.group(2), m.group(3).replace("''", "'")
        dm = re.search(r"distance_km = ([\d.]+)", rest)
        du = re.search(r"duration_min = (\d+)", rest)
        routes[name] = {"waypoints": [(w["lat"], w["lng"], w.get("label", "")) for w in wps],
                        "distance_km": float(dm.group(1)) if dm else None,
                        "duration_min": int(du.group(1)) if du else None,
                        "pois": [], "country": None}
    # přejmenování tras z postseed fixes (seedy mají stará jména)
    renames = {}
    post = open(MIG + "20260704_routes_postseed_fixes.sql", encoding="utf-8").read()
    for m in re.finditer(r"update public\.routes set name = '((?:[^']|'')*)' where name = '((?:[^']|'')*)';", post):
        renames[m.group(2).replace("''", "'")] = m.group(1).replace("''", "'")
    seed_files = sorted(glob.glob(MIG+"20260701_seed_recommended_routes_*.sql") + glob.glob(MIG+"20260703_seed_routes_*.sql"))
    route_hdr = re.compile(r"values \(v_route, (?:v_branch|null), '((?:[^']|'')*)', '((?:[^']|'')*)',")
    poi_row = re.compile(r"^\s*\(v_route, '((?:[^']|'')*)', '((?:[^']|'')*)', (-?[\d.]+), (-?[\d.]+), ('[^']*'|null), ('\{.*?\}'::text\[\]|null), (\d+)\)", re.M)
    cur = None
    for f in seed_files:
        cc = re.search(r"seed_routes_([a-z_]+)\.sql", f)
        cc = cc.group(1) if cc else "batch12"
        for line in open(f, encoding="utf-8"):
            hm = route_hdr.search(line)
            if hm:
                cur = hm.group(1).replace("''", "'")
                cur = renames.get(cur, cur)
                if cur in routes:
                    routes[cur]["country"] = cc
                continue
            pm = poi_row.match(line)
            if pm and cur in routes:
                routes[cur]["pois"].append({
                    "name": pm.group(1).replace("''", "'"),
                    "desc": pm.group(2).replace("''", "'"),
                    "lat": float(pm.group(3)), "lng": float(pm.group(4)),
                    "image_raw": pm.group(5), "images_raw": pm.group(6),
                    "sort": int(pm.group(7))})
    corr_re = re.compile(r"update public\.route_pois p set lat = (-?[\d.]+), lng = (-?[\d.]+),.*?r\.name = '((?:[^']|'')*)' and p\.name = '((?:[^']|'')*)';")
    for m in corr_re.finditer(fix):
        rn, pn = m.group(3).replace("''","'"), m.group(4).replace("''","'")
        if rn in routes:
            for p in routes[rn]["pois"]:
                if p["name"] == pn:
                    p["lat"], p["lng"] = float(m.group(1)), float(m.group(2))
    return routes

def load_catalog():
    cat_re = re.compile(
        r"\('(\w+)', '((?:[^']|'')*)', '((?:[^']|'')*)', (-?[\d.]+), (-?[\d.]+), '(\w\w)', "
        r"'[^']*', (\d+)(?:, (null|'(?:[^']|'')*'))?, '(\{.*?\})'::jsonb\)", re.S)
    catalog = []
    for f in glob.glob(MIG+"20260704_poi_catalog_seed_batch*.sql") + glob.glob(MIG+"20260704_poi_catalog_wikidata*batch*.sql"):
        for m in cat_re.finditer(open(f, encoding="utf-8").read()):
            img_raw = m.group(8)  # včetně SQL escapování a uvozovek, nebo 'null'/None
            catalog.append({"category": m.group(1), "name": m.group(2).replace("''","'"),
                            "desc_raw": m.group(3), "name_raw": m.group(2),
                            "lat": float(m.group(4)), "lng": float(m.group(5)),
                            "country": m.group(6), "rank": int(m.group(7)),
                            "image_raw": (None if img_raw in (None, "null") else img_raw),
                            "tr_raw": m.group(9)})
    return catalog

class Grid:
    def __init__(self, pts):
        self.pts = pts
        self.g = collections.defaultdict(list)
        for i, p in enumerate(pts):
            self.g[(int(p["lat"]*2), int(p["lng"]*2))].append(i)
    def near(self, lat, lng, km):
        out, r = [], int(km/55)+1
        for dy in range(-r, r+1):
            for dx in range(-r, r+1):
                for i in self.g.get((int(lat*2)+dy, int(lng*2)+dx), ()):
                    p = self.pts[i]
                    d = haversine((lat, lng), (p["lat"], p["lng"]))
                    if d <= km:
                        out.append((d, i))
        return out

def path_cum(wps):
    cum = [0.0]
    for i in range(1, len(wps)):
        cum.append(cum[-1] + haversine(wps[i-1][:2], wps[i][:2]))
    return cum

def project(pt, wps, cum):
    """(vzdálenost od čáry km, pozice podél čáry km)"""
    best = (1e9, 0.0)
    for i in range(1, len(wps)):
        a, b = wps[i-1][:2], wps[i][:2]
        ky = 111.0; kx = 111.0*math.cos(math.radians(a[0]))
        ax, ay = a[1]*kx, a[0]*ky; bx, by = b[1]*kx, b[0]*ky
        px, py = pt[1]*kx, pt[0]*ky
        dx, dy = bx-ax, by-ay
        L2 = dx*dx+dy*dy
        t = 0 if L2 == 0 else max(0, min(1, ((px-ax)*dx+(py-ay)*dy)/L2))
        d = math.hypot(px-(ax+t*dx), py-(ay+t*dy))
        if d < best[0]:
            best = (d, cum[i-1] + t*(cum[i]-cum[i-1]))
    return best

def point_at(wps, cum, pos):
    for i in range(1, len(wps)):
        if cum[i] >= pos:
            t = (pos-cum[i-1])/max(cum[i]-cum[i-1], 1e-9)
            return (wps[i-1][0] + t*(wps[i][0]-wps[i-1][0]),
                    wps[i-1][1] + t*(wps[i][1]-wps[i-1][1]))
    return wps[-1][:2]



GAP_MIN = 30.0      # km bez POI, od kterých úsek plníme
CORRIDOR = 7.0      # max vzdálenost katalogového bodu od čáry
EDGE = 8.0          # nový bod min. km (podél trasy) od okrajů gapu
ROUTE_CAP = 8       # max doplněných bodů na trasu
DIST_W = 800        # penalizace za km od čáry (v jednotkách ranku)

SCRATCH = "tools"

routes = load_routes()
catalog = load_catalog()
grid = Grid(catalog)

curated = []
cur_path = os.path.join(SCRATCH, "route_poi_gap_curated.json")
if os.path.exists(cur_path):
    curated = json.load(open(cur_path, encoding="utf-8"))
curated_by_route = collections.defaultdict(list)
for c in curated:
    curated_by_route[c["route"]].append(c)

no_pois = [n for n, r in routes.items() if not r["pois"]]
if no_pois:
    print("!! trasy bez naparsovaných POI (přeskočeny):", no_pois, file=sys.stderr)

additions = {}   # route -> list of dicts (poi record + pos)
for name, r in routes.items():
    wps = r["waypoints"]
    if len(wps) < 2 or not r["pois"]:
        continue
    cum = path_cum(wps)
    total = cum[-1]
    stops = sorted(((project((p["lat"], p["lng"]), wps, cum)[1], p) for p in r["pois"]), key=lambda x: x[0])
    existing_norm = {norm(p["name"]) for p in r["pois"]}
    marks = [0.0] + [s[0] for s in stops] + [total]
    adds = []

    # 1) kurátorované body — vždy
    for c in curated_by_route.get(name, ()):
        d, pos = project((c["lat"], c["lng"]), wps, cum)
        adds.append({"kind": "curated", "pos": pos, "off": d, **c})

    # 2) katalog do gapů
    gaps = []
    for i in range(1, len(marks)):
        g = marks[i] - marks[i-1]
        if g >= GAP_MIN:
            gaps.append((g, marks[i-1], marks[i]))
    gaps.sort(reverse=True)
    picked_pos = [a["pos"] for a in adds]
    for g, lo, hi in gaps:
        n_target = max(1, int(g // 30))
        # kandidáti podél úseku
        cand = {}
        steps = max(2, int(g / 8))
        for s in range(steps + 1):
            pos = lo + (hi - lo) * s / steps
            lat, lng = point_at(wps, cum, pos)
            for d, ci in grid.near(lat, lng, CORRIDOR):
                if ci not in cand or d < cand[ci]:
                    cand[ci] = d
        scored = []
        for ci, dseg in cand.items():
            p = catalog[ci]
            doff, pos = project((p["lat"], p["lng"]), wps, cum)
            if doff > CORRIDOR or not (lo + EDGE <= pos <= hi - EDGE):
                continue
            if norm(p["name"]) in existing_norm:
                continue
            if any(haversine((p["lat"], p["lng"]), (e["lat"], e["lng"])) < 2.5 for e in r["pois"]):
                continue
            scored.append((p["rank"] + doff * DIST_W, ci, doff, pos))
        scored.sort()
        minsep = max(12.0, g / (n_target + 1) * 0.6)
        cnt, catcnt = 0, collections.Counter()
        for score, ci, doff, pos in scored:
            if cnt >= n_target or len(adds) >= ROUTE_CAP:
                break
            p = catalog[ci]
            if catcnt[p["category"]] >= 2:
                continue
            if any(abs(pos - pp) < minsep for pp in picked_pos):
                continue
            if any(haversine((p["lat"], p["lng"]), (a["lat"], a["lng"])) < 2.5 for a in adds):
                continue
            adds.append({"kind": "catalog", "pos": pos, "off": doff, "ci": ci,
                         "name": p["name"], "lat": p["lat"], "lng": p["lng"]})
            picked_pos.append(pos)
            existing_norm.add(norm(p["name"]))
            catcnt[p["category"]] += 1
            cnt += 1
    if adds:
        additions[name] = sorted(adds, key=lambda a: a["pos"])

# ── REPORT ───────────────────────────────────────────────────────────
rep = open(os.path.join(SCRATCH, "route_poi_gap_report.txt"), "w", encoding="utf-8")
tot = 0
for name in sorted(additions, key=lambda n: -len(additions[n])):
    r = routes[name]
    tot += len(additions[name])
    rep.write(f"[{r['country'] or 'batch12'}] {name} (+{len(additions[name])}):\n")
    for a in additions[name]:
        src = "KURÁTOR" if a["kind"] == "curated" else f"katalog r{catalog[a['ci']]['rank']}"
        rep.write(f"   +{a['name']}  @{a['pos']:.0f} km, {a['off']:.1f} km od čáry ({src})\n")
rep.write(f"\nCelkem: {tot} bodů do {len(additions)} tras\n")
rep.close()
print(f"Doplněno {tot} bodů do {len(additions)} tras (report: tools/route_poi_gap_report.txt)")

# ── SQL ──────────────────────────────────────────────────────────────
def poi_sql_values(v, sort):
    """VALUES řádek pro insert route_pois"""
    if v["kind"] == "catalog":
        p = catalog[v["ci"]]
        img = p["image_raw"]  # včetně uvozovek / None
        img_col = img if img else "null"
        imgs_col = "'{\"" + img[1:-1] + "\"}'::text[]" if img else "null"
        return (f"    (v_route, '{p['name_raw']}', '{p['desc_raw']}', {p['lat']}, {p['lng']}, "
                f"{img_col}, {imgs_col}, {sort}, '{p['tr_raw']}'::jsonb)")
    else:
        img = v.get("image")
        img_col = f"'{sqlesc(img)}'" if img else "null"
        imgs_col = "'{\"" + sqlesc(img) + "\"}'::text[]" if img else "null"
        return (f"    (v_route, '{sqlesc(v['name'])}', '{sqlesc(v['desc'])}', {v['lat']}, {v['lng']}, "
                f"{img_col}, {imgs_col}, {sort}, '{{}}'::jsonb)")

out = []
out.append("""-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Doplnění bodů zájmu PODÉL tras (2026-07-04)
--
-- Problém: řada tras (např. Sozopol a jižní Černomoří) měla body zájmu
-- nahloučené v jednom místě a dlouhé úseky (30–250 km) bez jediné
-- zastávky — cesta byla „nuda". Tato migrace:
--  1) doplňuje do všech úseků >= 30 km bez POI nové body:
--     - z katalogu points_of_interest (<= 7 km od trasy, nejznámější první),
--     - ručně kurátorované body pro země bez katalogu (BG, EE, LT, MD, MK),
--       souřadnice ověřeny proti webovým zdrojům (Wikipedia/Wikidata),
--  2) přečíslovává sort_order VŠECH bodů trasy podle pořadí na trase,
--  3) přegenerovává waypoints (trasa nově vede přes doplněné body),
--     přepočítává distance_km/duration_min (vzdušná délka × 1.35, ~42 km/h)
--     při odchylce > 15 %, obnovuje mapy_url a nuluje geometry cache.
-- Idempotentní: doplněné body se před insertem smažou dle jména.
-- Překlady nových kurátorovaných bodů doplní cron backfill-route-translations
-- (přeplánován na konci); body z katalogu mají překlady rovnou.
-- Vygenerováno: tools/fill_route_poi_gaps.py
-- ════════════════════════════════════════════════════════════════════

begin;
""")

for name in sorted(additions):
    r = routes[name]
    adds = additions[name]
    wps = r["waypoints"]
    cum = path_cum(wps)
    stops = sorted([(project((p["lat"], p["lng"]), wps, cum)[1], "old", p) for p in r["pois"]]
                   + [(a["pos"], "new", a) for a in adds], key=lambda x: x[0])
    esc_name = sqlesc(name)
    out.append(f"-- ── {name} (+{len(adds)} bodů) " + "─" * max(1, 40 - len(name)))
    out.append("do $$\ndeclare v_route uuid;\nbegin")
    out.append(f"  select id into v_route from public.routes where name = '{esc_name}' limit 1;")
    out.append(f"  if v_route is null then raise notice 'Trasa nenalezena: {esc_name}'; return; end if;")
    new_names = ", ".join(f"'{sqlesc(a['name'])}'" for a in adds)
    out.append(f"  delete from public.route_pois where route_id = v_route and name in ({new_names});")
    # insert nových se správným sort_order
    vals = []
    for i, (pos, kind, obj) in enumerate(stops):
        if kind == "new":
            vals.append(poi_sql_values(obj, i))
    out.append("  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order, translations) values")
    out.append(",\n".join(vals) + ";")
    # přečíslování stávajících
    for i, (pos, kind, obj) in enumerate(stops):
        if kind == "old" and obj["sort"] != i:
            out.append(f"  update public.route_pois set sort_order = {i}, updated_at = now() "
                       f"where route_id = v_route and name = '{sqlesc(obj['name'])}';")
    # nové waypointy: stávající + nové body dle pozice
    wp_seq = [(cum[i], {"lat": w[0], "lng": w[1], "label": w[2]}) for i, w in enumerate(wps)]
    wp_seq += [(a["pos"], {"lat": a["lat"], "lng": a["lng"], "label": a["name"]}) for a in adds]
    wp_seq.sort(key=lambda x: x[0])
    new_wps = [w for _, w in wp_seq]
    wp_json = json.dumps(new_wps, ensure_ascii=False, separators=(", ", ": "))
    # délka nové čáry
    ncum = 0.0
    for i in range(1, len(new_wps)):
        ncum += haversine((new_wps[i-1]["lat"], new_wps[i-1]["lng"]), (new_wps[i]["lat"], new_wps[i]["lng"]))
    est = ncum * 1.35
    set_dist = ""
    if r["distance_km"] and abs(est - r["distance_km"]) / r["distance_km"] > 0.15:
        dk = max(5, int(round(est / 5) * 5))
        dm = max(15, int(round(est / 42 * 60 / 5) * 5))
        set_dist = f", distance_km = {dk}, duration_min = {dm}"
    o, d = new_wps[0], new_wps[-1]
    mid = "%7C".join(f"{w['lat']},{w['lng']}" for w in new_wps[1:-1])
    mapy = (f"https://www.google.com/maps/dir/?api=1&origin={o['lat']},{o['lng']}"
            f"&destination={d['lat']},{d['lng']}&travelmode=driving" + (f"&waypoints={mid}" if mid else ""))
    out.append(f"  update public.routes set waypoints = '{sqlesc(wp_json)}'::jsonb{set_dist}, "
               f"mapy_url = '{mapy}', geometry = null, updated_at = now() where id = v_route;")
    out.append("end $$;\n")

out.append("""-- ── Překlady nových bodů: přeplánuj cron backfill (viz 20260704_route_translations_cron.sql)
do $$
begin
  begin
    perform cron.unschedule('backfill-route-translations');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-route-translations',
    '* * * * *',
    $cron$ select public.trigger_route_translation_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;

commit;
""")

sql_path = os.path.join("supabase/migrations", "20260705_route_pois_fill_gaps.sql")
open(sql_path, "w", encoding="utf-8").write("\n".join(out))
print("SQL:", sql_path, f"({os.path.getsize(sql_path)//1024} KB)")
