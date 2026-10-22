#!/usr/bin/env python3
"""Sync appdesign/project/canvas.json with the boards.

- h/w of every board = its data-props "$preview" (also checks the root div matches)
- v2.2 board titles + order (13 boards), title-note width
Usage: python3 -I canvas_sync.py <project dir> [--check]
--check only reports drift (exit 1 on drift), without writing.
"""
import json, re, sys, os

TITLES = {
    # final v2.2 numbering (shared fixer 2026-10-16; SOS 12 + Stavy 13 added) — in-board cross-references ("board N · Název") use exactly these numbers/names
    'Main.dc.html': '1 · Domů — tvoje příští jízda',
    'MotoKatalog.dc.html': '2 · Motorky — celá obrazovka + kalkulačka',
    'Kalkulacka.dc.html': '3 · Kalkulačka — jako web, s tvou cenou',
    'MotoDetail.dc.html': '4 · Detail — přehledně, REZERVOVAT',
    'Booking.dc.html': '5 · Rezervace expres — máme to připravené',
    'Reservation.dc.html': '6 · Správa rezervace — kódy, vrácení, hodnocení',
    'Profil.dc.html': '7 · Profil — můj klub',
    'TrasyHub.dc.html': '8 · Trasy — místa, trasy, moje',
    'TrasaDetail.dc.html': '9 · Trasa a navigace — detail, navigace, plánovač',
    'Zazitky.dc.html': '10 · Moje zážitky — jízdy, trasy, místa',
    'RankStyly.dc.html': '11 · Rank styly — 20 ranků, bez fialové',
    'SOS.dc.html': '12 · SOS — pomoc na cestě',
    'Stavy.dc.html': '13 · Stavy — výsledky, chyby, offline',
}
ORDER = list(TITLES)
GAP = 80  # 390 wide boards every 470 px, as in v1


def preview(path):
    s = open(path, encoding='utf-8').read()
    dp = json.loads(re.search(r"data-props='(.*?)'>", s, re.S).group(1))
    pv = dp['$preview']
    root = re.search(r'</helmet>\s*<div[^>]*style="width:(\d+)px;height:(\d+)px', s)
    if not root:
        raise SystemExit(f'{path}: root div size not found')
    rw, rh = int(root.group(1)), int(root.group(2))
    if (rw, rh) != (pv['width'], pv['height']):
        raise SystemExit(f'{path}: $preview {pv} != root div {rw}x{rh}')
    return pv['width'], pv['height']


def main():
    proj, check = sys.argv[1], '--check' in sys.argv
    cpath = os.path.join(proj, 'canvas.json')
    c = json.load(open(cpath, encoding='utf-8'))
    old = json.dumps(c, ensure_ascii=False, sort_keys=True)
    boards, x = {}, 0
    for name in ORDER:
        fp = os.path.join(proj, name)
        if not os.path.exists(fp):
            raise SystemExit(f'missing board {name}')
        w, h = preview(fp)
        prev = c['boards'].get(name, {})
        b = {'x': x, 'y': 0, 'w': w, 'h': h, 'title': TITLES[name], 'is_interactive': True}
        for k, v in prev.items():
            if k not in b:
                b[k] = v
        boards[name] = b
        x += w + GAP
    extra = [n for n in c['boards'] if n not in boards]
    if extra:
        raise SystemExit(f'unknown boards in canvas.json: {extra}')
    c['boards'], c['order'] = boards, ORDER
    c['notes']['title']['maxW'] = x - GAP
    new = json.dumps(c, ensure_ascii=False, sort_keys=True)
    for name, b in boards.items():
        print(f"{name:22} x={b['x']:5} h={b['h']:5}  {b['title']}")
    if check:
        print('IN SYNC' if new == old else 'DRIFT')
        sys.exit(0 if new == old else 1)
    with open(cpath, 'w', encoding='utf-8') as f:
        json.dump(c, f, ensure_ascii=False)
    print('written' if new != old else 'unchanged')


main()
