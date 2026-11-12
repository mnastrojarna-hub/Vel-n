#!/usr/bin/env python3
"""Split a pg_dump style SQL file into statements (dollar quotes, quotes and
comments respected).

  split_sql.py count <file>             -> number of statements per leading keyword group
  split_sql.py defer <file> <pre> <post>
        write <pre>  = every statement except the deferred ones
              <post> = CREATE POLICY / CREATE [OR REPLACE] TRIGGER statements that
                       reference the public schema (they need public objects first)
  split_sql.py names <file>             -> one line per CREATE statement: kind <tab> name
Used only to build the template database; not needed for testing migrations.
"""
import re, sys

def split(text):
    out, buf, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '-' and text.startswith('--', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            buf.append(text[i:j]); i = j; continue
        if c == '/' and text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            buf.append(text[i:j]); i = j; continue
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2; continue
                    break
                j += 1
            buf.append(text[i:j + 1]); i = j + 1; continue
        if c == '"':
            j = text.find('"', i + 1)
            while j >= 0 and j + 1 < n and text[j + 1] == '"':
                j = text.find('"', j + 2)
            j = n - 1 if j < 0 else j
            buf.append(text[i:j + 1]); i = j + 1; continue
        if c == '$':
            m = re.match(r'\$([A-Za-z_][A-Za-z_0-9]*)?\$', text[i:i + 80])
            if m:
                tag = m.group(0)
                j = text.find(tag, i + len(tag))
                j = n if j < 0 else j + len(tag)
                buf.append(text[i:j]); i = j; continue
        if c == ';':
            buf.append(c); out.append(''.join(buf).strip()); buf = []; i += 1; continue
        buf.append(c); i += 1
    rest = ''.join(buf).strip()
    if rest:
        out.append(rest)
    return [s for s in out if s and s != ';']

KIND = re.compile(
    r'^CREATE\s+(?:OR\s+REPLACE\s+)?(UNIQUE\s+INDEX|INDEX|TABLE|FUNCTION|PROCEDURE|TRIGGER|POLICY|TYPE|VIEW|'
    r'MATERIALIZED\s+VIEW|SEQUENCE|SCHEMA|DOMAIN|AGGREGATE|EXTENSION)\s+(?:IF\s+NOT\s+EXISTS\s+)?', re.I)

def strip_comments(s):
    lines = [l for l in s.split('\n') if not l.lstrip().startswith('--')]
    return '\n'.join(lines).strip()

def kind_of(s):
    s = strip_comments(s)
    m = KIND.match(s)
    if m:
        return re.sub(r'\s+', ' ', m.group(1).upper()), s[m.end():]
    return None, s

def main():
    cmd = sys.argv[1]
    text = open(sys.argv[2], encoding='utf-8').read()
    stmts = split(text)
    if cmd == 'count':
        cnt = {}
        for s in stmts:
            k, _ = kind_of(s)
            if k is None:
                k = '(other) ' + ' '.join(strip_comments(s).split()[:2]).upper()
            cnt[k] = cnt.get(k, 0) + 1
        for k in sorted(cnt):
            print(f'{cnt[k]:6d}  {k}')
    elif cmd == 'names':
        for s in stmts:
            k, rest = kind_of(s)
            if k:
                print(k + '\t' + ' '.join(rest.split())[:4000])
    elif cmd == 'defer':
        pre, post = [], []
        for s in stmts:
            k, _ = kind_of(s)
            if k in ('POLICY', 'TRIGGER') and '"public".' in s:
                post.append(s)
            else:
                pre.append(s)
        open(sys.argv[3], 'w', encoding='utf-8').write('\n\n'.join(pre) + '\n')
        open(sys.argv[4], 'w', encoding='utf-8').write('\n\n'.join(post) + '\n')
        print(f'statements: {len(stmts)}, deferred: {len(post)}')
    else:
        sys.exit(__doc__)

main()
