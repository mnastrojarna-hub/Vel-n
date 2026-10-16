import re, sys, json, subprocess, os
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
errs = []
# holes
for m in re.finditer(r'\{\{(.*?)\}\}', s, re.S):
    e = m.group(1).strip()
    if not re.fullmatch(r'[A-Za-z_$][\w$]*(\.[\w$]+)*|true|false|-?\d+(\.\d+)?', e):
        errs.append('bad hole: ' + e[:80])
# sc-if / sc-for hints
for m in re.finditer(r'<sc-if\b[^>]*>', s):
    if 'hint-placeholder-val' not in m.group(0): errs.append('sc-if no hint: ' + m.group(0)[:100])
for m in re.finditer(r'<sc-for\b[^>]*>', s):
    if 'hint-placeholder-count' not in m.group(0): errs.append('sc-for no hint: ' + m.group(0)[:100])
    if ' as="' not in m.group(0): errs.append('sc-for no as: ' + m.group(0)[:100])
o_if, c_if = len(re.findall(r'<sc-if\b', s)), s.count('</sc-if>')
o_for, c_for = len(re.findall(r'<sc-for\b', s)), s.count('</sc-for>')
if o_if != c_if: errs.append(f'sc-if open {o_if} close {c_if}')
if o_for != c_for: errs.append(f'sc-for open {o_for} close {c_for}')
# data-props
m = re.search(r"data-props='(.*?)'>", s, re.S)
if not m: errs.append('no data-props')
else:
    try:
        dp = json.loads(m.group(1))
        for k, v in dp.items():
            if k == '$preview': continue
            if not isinstance(v, dict) or 'editor' not in v or 'default' not in v: errs.append('bad prop ' + k)
        print('props:', list(dp.keys()), dp.get('$preview'))
    except Exception as ex: errs.append('data-props json: ' + str(ex))
# script syntax
sm = re.search(r'<script type="text/x-dc"[^>]*>(.*?)</script>', s, re.S)
if sm:
    js = 'class DCLogic{constructor(p){this.props=p}setState(){}}\n' + sm.group(1) + '\nnew Component({}).renderVals();\nconsole.log("render ok");'
    fn = p + '.check.js'
    open(fn, 'w').write(js)
    r = subprocess.run(['node', fn], capture_output=True, text=True)
    print('node:', (r.stdout + r.stderr).strip()[-600:])
    os.remove(fn)
# top-level hole names vs script
tops = set(re.findall(r'\{\{\s*([A-Za-z_$][\w$]*)', s))
loopvars = set(re.findall(r'<sc-for[^>]*\bas="(\w+)"', s))
script = sm.group(1) if sm else ''
for t in sorted(tops - loopvars - {'true', 'false'}):
    if not re.search(r'(?<![\w$.])' + re.escape(t) + r'\s*[:,}\n]', script):
        errs.append('hole not in script?: ' + t)
# helmet / root
if '<helmet>' not in s or '</helmet>' not in s: errs.append('no helmet')
if './support.js' not in s: errs.append('no support.js')
# button reset specificity: a bare-button reset such as `.mg button{background:none;padding:0…}` (0,1,1) silently beats
# single-class button rules (0,1,0) like `.scrim{background:…}` -> scope resets with `:where(.mg) button` (see btncheck.js)
try:
    r = subprocess.run(['node', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'btncheck.js'), p, '--json'], capture_output=True, text=True, timeout=240)
    bj = json.loads(r.stdout.strip().splitlines()[-1])
    for f in bj['findings']:
        errs.append('button rule loses to reset %s (%s): %s (%s) -> %s; scope the reset as :where(.mg) button' % (f['reset'], f['resetSpec'], f['sel'], f['spec'], ','.join(f['props'])))
    print('btncheck: resets', bj['resets'] or 'none', '· button class sets', bj['buttons'], '· findings', len(bj['findings']))
except Exception as ex:
    print('btncheck: WARNING could not run (' + str(ex)[:120] + ')')
print('size', len(s.encode()))
print('\n'.join(errs) if errs else 'LINT OK')
