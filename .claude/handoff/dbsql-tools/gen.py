#!/usr/bin/env python3
"""Generate m3a_owner_texts.sql from spec.py + live JSON dumps (verifies every old phrase)."""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import spec

S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
LIVE = S + '/dbsql/live'
OUT = S + '/sql/m3a_owner_texts.sql'
LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']

cms = {r['key']: r for r in json.load(open(LIVE + '/cms_variables.json'))}
faq = {r['id']: r for r in json.load(open(LIVE + '/faq_items.json'))}
aps = {r['key']: r['value'] for r in json.load(open(LIVE + '/app_settings.json'))}
langvals = json.load(open(S + '/dbsql/langvals.json'))
errs = []

def q(s):
    if s is None:
        return 'NULL'
    assert '$t$' not in s
    return '$t$' + s + '$t$'

def check(cur, old, new, label):
    """Resolve @FULL and verify old occurs exactly once (or lang missing for old=None)."""
    if old is None:
        if cur:
            errs.append(f'{label}: expected missing, found {cur!r}')
        return None
    if old == '@FULL':
        if not cur:
            errs.append(f'{label}: @FULL but current empty')
        return cur
    if cur is None or cur.count(old) != 1:
        errs.append(f'{label}: old phrase found {0 if cur is None else cur.count(old)}x in {cur!r}')
    return old

cms_rows = []
for k, lang, old, new, gate in spec.CMS:
    r = cms[k]
    cur = r['value'] if lang == 'cs' else ((r.get('translations') or {}).get(lang) or {}).get('value')
    old = check(cur, old, new, f'{k}/{lang}')
    if lang == 'cs' and gate not in new:
        errs.append(f'{k}: gate not in new CS')
    cms_rows.append((k, lang, old, new, gate))

faq_rows = []
for i, field, lang, old, new, gate in spec.FAQ:
    r = faq[i]
    cur = r[field] if lang == 'cs' else ((r.get('translations') or {}).get(lang) or {}).get(field)
    old = check(cur, old, new, f'{i[:8]}/{field}/{lang}')
    if lang == 'cs' and gate not in new:
        errs.append(f'{i}: gate not in new CS')
    faq_rows.append((i, field, lang, old, new, gate))

ov_rows = []
for page, path in spec.OVERLAY_PATHS:
    for lang in LANGS:
        key = f'pages_overlay.{page}.{lang}'
        if key not in aps:
            continue  # uk has no overlays
        v = aps[key]
        for p in path:
            v = v[int(p)] if isinstance(v, list) else v.get(p)
        new = langvals[lang].get(page + '.' + '.'.join(path))
        if not isinstance(v, str) or not isinstance(new, str) or v == new:
            errs.append(f'overlay {key} {path}: cur={v!r} new={new!r}')
            continue
        ov_rows.append((page, lang, '{' + ','.join(path) + '}', v, new))

if errs:
    print('\n'.join(errs))
    sys.exit(1)

def values(rows):
    return ',\n'.join('    (' + ', '.join(q(x) if not isinstance(x, int) else str(x) for x in row) + ')' for row in rows)

tmpl = open(os.path.dirname(__file__) + '/template.sql').read()
sql = (tmpl.replace('@@CMS@@', values(cms_rows))
           .replace('@@FAQ@@', values(faq_rows))
           .replace('@@OVERLAY@@', values(ov_rows))
           .replace('@@BANNER_CS@@', q(spec.BANNER_CS))
           .replace('@@BANNER_TR@@', ',\n      '.join(f"'{l}', {q(spec.BANNER_TR[l])}" for l in LANGS)))
open(OUT, 'w').write(sql)
print(f'OK cms={len(cms_rows)} faq={len(faq_rows)} overlay={len(ov_rows)} -> {OUT} ({len(sql)} bytes)')
