#!/usr/bin/env python3
"""seed_json.py <db> <table> <json file> [--schema S]

Upsert rows (a JSON array of objects, e.g. the output of rest_get.sh) into
public.<table> of the LOCAL test database <db>.
  * only keys that are real, non-generated columns of the table are used
    (other keys are listed on stderr and ignored);
  * runs with session_replication_role = replica -> no triggers, no FK checks;
  * conflict target = primary key (rows are updated); a table without a primary
    key gets plain inserts with ON CONFLICT DO NOTHING;
  * everything in one transaction; prints the number of rows written.
Run as:  python3 -I seed_json.py mydb cms_variables /path/cms_variables.json
"""
import json, os, re, subprocess, sys, uuid

RIG = os.path.dirname(os.path.abspath(__file__))

def psql(db, sql, args=()):
    r = subprocess.run([os.path.join(RIG, 'psql.sh'), db, '-q', '-At', '-F', '\t', '-v', 'ON_ERROR_STOP=1', *args, '-f', '-'],
                       input=sql, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit(1)
    return r.stdout

def qi(name):
    return '"' + name.replace('"', '""') + '"'

def main():
    argv = sys.argv[1:]
    if len(argv) < 3 or argv[0] in ('-h', '--help'):
        print(__doc__); sys.exit(0 if argv and argv[0] in ('-h', '--help') else 1)
    db, table, path = argv[:3]
    schema = 'public'
    if '--schema' in argv:
        schema = argv[argv.index('--schema') + 1]
    for ident in (table, schema):
        if not re.fullmatch(r'[a-z_][a-z0-9_]*', ident):
            sys.exit('seed_json.py: table/schema must be a plain identifier')
    try:
        rows = json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError) as e:
        sys.exit(f'seed_json.py: cannot read a JSON array from {path}: {e}')
    if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
        sys.exit('seed_json.py: the file must hold a JSON array of objects')
    if not rows:
        print(f'{schema}.{table}: 0 rows in {path}, nothing to do'); return
    rel = f'{qi(schema)}.{qi(table)}'
    cols = [l.split('\t') for l in psql(db, f"""
        select a.attname, a.attgenerated <> '', a.attidentity
          from pg_attribute a where a.attrelid = '{schema}.{table}'::regclass and a.attnum > 0 and not a.attisdropped
         order by a.attnum;""").splitlines() if l]
    pk = [l for l in psql(db, f"""
        select a.attname from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
         where i.indrelid = '{schema}.{table}'::regclass and i.indisprimary order by array_position(i.indkey::int2[], a.attnum);""").splitlines() if l]
    keys = set()
    for r in rows:
        keys.update(r.keys())
    use = [c[0] for c in cols if c[0] in keys and c[1] != 't']
    always = any(c[2] == 'a' for c in cols if c[0] in use)
    ignored = sorted(keys - {c[0] for c in cols}) + sorted(c[0] for c in cols if c[0] in keys and c[1] == 't')
    if ignored:
        sys.stderr.write(f'seed_json.py: ignored keys (no such column / generated): {", ".join(ignored)}\n')
    if not use:
        sys.exit('seed_json.py: no key of the JSON rows is a column of the table')
    if pk and not set(pk) <= set(use):
        sys.exit(f'seed_json.py: the rows lack the primary key column(s) {pk}')
    payload = json.dumps(rows, ensure_ascii=False)
    tag = '$seed_' + uuid.uuid4().hex + '$'
    collist = ', '.join(qi(c) for c in use)
    if pk:
        upd = [c for c in use if c not in pk]
        conflict = f"on conflict ({', '.join(qi(c) for c in pk)}) " + (
            'do update set ' + ', '.join(f'{qi(c)} = excluded.{qi(c)}' for c in upd) if upd else 'do nothing')
    else:
        conflict = 'on conflict do nothing'
    sql = f"""begin;
set local session_replication_role = replica;
with w as (
  insert into {rel} ({collist}) {'overriding system value' if always else ''}
  select {collist} from jsonb_populate_recordset(null::{rel}, {tag}{payload}{tag}::jsonb)
  {conflict}
  returning 1)
select count(*) from w;
commit;
"""
    n = psql(db, sql).strip().splitlines()[-1]
    print(f'{schema}.{table}: {n} row(s) written from {len(rows)} JSON row(s); columns used: {len(use)}'
          + (f'; conflict target: {", ".join(pk)}' if pk else '; no primary key (insert only)'))

main()
