// Button-reset specificity check for .dc.html boards.
// Finds "generic" button rules (subject = bare `button`, e.g. the `.mg button{…}` reset) and reports every
// class/attribute rule that styles a real <button> of the board but LOSES a property to such a reset because
// its specificity is lower (e.g. `.scrim{background:…}` (0,1,0) vs `.mg button{background:none}` (0,1,1)).
// Buttons are collected from the template rendered with renderVals() for the default props + random clicks
// (same idea as fuzz.js), so class="{{ x.cls }}" holes are resolved.
// usage: node btncheck.js <board.dc.html> ['<props json>'] [--json]
const fs = require('fs');
const [file, pj] = process.argv.slice(2).filter((a) => a !== '--json');
const asJson = process.argv.includes('--json');
const src = fs.readFileSync(file, 'utf8');
const cssText = (src.match(/<style>([\s\S]*?)<\/style>/) || [, ''])[1];

// ---------- CSS parsing ----------
function parseRules(css) {
  css = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = []; let order = 0;
  (function walk(t) {
    let i = 0;
    while (i < t.length) {
      const ob = findTop(t, '{', i); if (ob < 0) break;
      const head = t.slice(i, ob).trim(); const cb = matchBrace(t, ob); const body = t.slice(ob + 1, cb);
      if (head.startsWith('@')) { if (/^@(media|supports|layer|container)\b/.test(head)) walk(body); }
      else if (head) rules.push({ sel: head, decls: parseDecls(body), order: order++ });
      i = cb + 1;
    }
  })(css);
  return rules;
}
function findTop(t, ch, i) { let q = null; for (; i < t.length; i++) { const c = t[i]; if (q) { if (c === '\\') i++; else if (c === q) q = null; } else if (c === '"' || c === "'") q = c; else if (c === ch) return i; } return -1; }
function matchBrace(t, ob) { let d = 0, q = null; for (let i = ob; i < t.length; i++) { const c = t[i]; if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; } if (c === '"' || c === "'") q = c; else if (c === '{') d++; else if (c === '}' && !--d) return i; } return t.length; }
function parseDecls(body) {
  const out = []; let cur = '', depth = 0, q = null;
  for (const c of body + ';') {
    if (q) { cur += c; if (c === q) q = null; continue; }
    if (c === '"' || c === "'") { q = c; cur += c; continue; }
    if (c === '(') depth++; if (c === ')') depth--;
    if (c === ';' && !depth) { const k = cur.indexOf(':'); if (k > 0) { const v = cur.slice(k + 1).trim(); out.push({ p: cur.slice(0, k).trim().toLowerCase(), imp: /!important\s*$/.test(v) }); } cur = ''; } else cur += c;
  }
  return out;
}
function splitTop(s, seps) { const out = []; let cur = '', d = 0, b = 0; for (const c of s) { if (c === '(') d++; else if (c === ')') d--; else if (c === '[') b++; else if (c === ']') b--; if (!d && !b && seps.includes(c)) { out.push(cur); cur = ''; } else cur += c; } out.push(cur); return out.map((x) => x.trim()).filter(Boolean); }

// ---------- selectors ----------
function compound(c) { // parse one compound selector
  const r = { tag: null, cls: [], ids: 0, attrs: 0, pcs: [], pe: false, where: 0, spec: [0, 0, 0] };
  let i = 0;
  const ident = () => { const m = c.slice(i).match(/^-?[_a-zA-Z -￿][-\w -￿]*|^\*/); if (!m) return ''; i += m[0].length; return m[0]; };
  while (i < c.length) {
    const ch = c[i];
    if (ch === '.') { i++; r.cls.push(ident()); r.spec[1]++; }
    else if (ch === '#') { i++; ident(); r.spec[0]++; }
    else if (ch === '[') { const e = c.indexOf(']', i); i = e + 1; r.spec[1]++; r.attrs++; }
    else if (ch === ':') {
      const el = c[i + 1] === ':'; i += el ? 2 : 1; const name = ident().toLowerCase(); let arg = null;
      if (c[i] === '(') { let d = 0, j = i; for (; j < c.length; j++) { if (c[j] === '(') d++; else if (c[j] === ')' && !--d) break; } arg = c.slice(i + 1, j); i = j + 1; }
      if (el || ['before', 'after', 'first-line', 'first-letter'].includes(name)) { r.pe = true; r.spec[2]++; }
      else if (name === 'where') { /* 0 */ }
      else if (['is', 'not', 'has', 'matches'].includes(name)) { const best = splitTop(arg || '', [',']).map(spec).sort(cmp).pop() || [0, 0, 0]; add(r.spec, best); if (name !== 'not') r.pcs.push(name); }
      else { r.spec[1]++; r.pcs.push(name); }
    } else { const t = ident(); if (!t) { i++; continue; } if (t !== '*') { r.tag = t.toLowerCase(); r.spec[2]++; } }
  }
  return r;
}
function compounds(sel) { return sel.replace(/\s*([>+~])\s*/g, ' ').split(/\s+(?![^(]*\))(?![^[]*\])/).filter(Boolean); }
function spec(sel) { const s = [0, 0, 0]; for (const c of compounds(sel)) add(s, compound(c).spec); return s; }
function add(a, b) { a[0] += b[0]; a[1] += b[1]; a[2] += b[2]; }
function cmp(a, b) { return a[0] - b[0] || a[1] - b[1] || a[2] - b[2]; }

// ---------- reset-property overlap ----------
const SKIP = new Set(['border-radius', 'border-collapse', 'border-spacing', 'border-top-left-radius', 'border-top-right-radius', 'border-bottom-left-radius', 'border-bottom-right-radius']);
function overlaps(p, r) {
  if (p === r) return true;
  if (r === 'font') return p.startsWith('font-') || p === 'line-height';
  if (r === 'border') return p.startsWith('border') && !SKIP.has(p);
  if (['background', 'padding', 'margin', 'outline'].includes(r)) return p.startsWith(r + '-') || (p === r);
  if (p === 'font') return r.startsWith('font-') || r === 'line-height';
  if (p === 'border') return r.startsWith('border') && !SKIP.has(r);
  if (['background', 'padding', 'margin'].includes(p)) return r.startsWith(p + '-');
  return false;
}

// ---------- buttons of the board (rendered) ----------
const ROOT = new Set();
function collectButtons() {
  const sets = new Map();
  const tpl = src.slice(src.indexOf('</helmet>') + 9, src.indexOf('</x-dc>'));
  const sm = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/);
  const addFrom = (html) => { const rm = html.match(/^\s*<div\b[^>]*?\bclass="([^"]*)"/); if (rm) rm[1].split(/\s+/).filter(Boolean).forEach((k) => ROOT.add(k)); for (const m of html.matchAll(/<button\b[^>]*?\bclass="([^"]*)"/g)) { const cl = m[1].split(/\s+/).filter(Boolean).sort(); sets.set(cl.join(' '), cl); } if (/<button\b(?![^>]*\bclass=)/.test(html)) sets.set('', []); };
  addFrom(tpl.replace(/\{\{[^}]*\}\}/g, ' '));
  if (!sm) return [...sets.values()];
  global.DCLogic = class { constructor(p) { this.props = p; } setState(o) { this.state = Object.assign({}, this.state, typeof o === 'function' ? o(this.state) : o); } };
  const C = new Function(sm[1] + '\nreturn Component;')();
  const dp = JSON.parse((src.match(/data-props='([^']*)'/) || [, '{}'])[1]);
  const base = {}; for (const k in dp) if (k !== '$preview') base[k] = dp[k].default;
  const variants = [{}];
  for (const k in dp) { const d = dp[k]; if (k === '$preview' || !d) continue; if (d.editor === 'enum') d.options.forEach((o) => variants.push({ [k]: o })); if (d.editor === 'boolean') variants.push({ [k]: !d.default }); if (d.editor === 'int') [d.min, d.max].forEach((v) => v != null && variants.push({ [k]: v })); }
  if (pj) variants.push(JSON.parse(pj));
  const look = (ctx, p) => { let v = ctx; for (const k of p.split('.')) v = v == null ? undefined : v[k]; return v; };
  function render(t, ctx) {
    const re = /<(sc-for|sc-if)\b([^>]*)>/g; let m, out = '', last = 0;
    while ((m = re.exec(t))) {
      const tag = m[1]; let depth = 1, i = re.lastIndex; const open = new RegExp('<' + tag + '\\b', 'g'), close = '</' + tag + '>';
      while (depth) { open.lastIndex = i; const no = open.exec(t); const nc = t.indexOf(close, i); if (nc < 0) { i = t.length; break; } if (no && no.index < nc) { depth++; i = no.index + 1; } else { depth--; i = nc + close.length; } }
      const inner = t.slice(re.lastIndex, i - close.length); out += t.slice(last, m.index);
      const attr = (n) => (m[2].match(new RegExp(n + '="\\{\\{\\s*([\\w$.]+)\\s*\\}\\}"')) || [])[1];
      if (tag === 'sc-if') { if (look(ctx, attr('value'))) out += render(inner, ctx); }
      else { const as = (m[2].match(/as="(\w+)"/) || [])[1]; for (const it of look(ctx, attr('list')) || []) out += render(inner, Object.assign({}, ctx, { [as]: it })); }
      last = i; re.lastIndex = i;
    }
    out += t.slice(last);
    return out.replace(/\{\{\s*([\w$.]+)\s*\}\}/g, (_, p) => { const v = look(ctx, p); return typeof v === 'function' || v == null ? '' : String(v); });
  }
  const fns = (v, out) => { if (typeof v === 'function') out.push(v); else if (Array.isArray(v)) v.forEach((x) => fns(x, out)); else if (v && typeof v === 'object') for (const k in v) fns(v[k], out); return out; };
  const realST = global.setTimeout; global.setTimeout = () => 0; global.clearTimeout = () => {}; global.setInterval = () => 0; global.clearInterval = () => {};
  let seed = 11; const rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  for (const v of variants) {
    let c, r; try { c = new C(Object.assign({}, base, v)); r = c.renderVals(); } catch (e) { continue; }
    addFrom(render(tpl, r));
    for (let i = 0; i < 150; i++) { const f = fns(r, []); if (!f.length) break; try { f[rnd(f.length)]({ target: { value: 'Test ' + i }, stopPropagation() {}, preventDefault() {} }); r = c.renderVals(); addFrom(render(tpl, r)); } catch (e) { break; } }
  }
  global.setTimeout = realST;
  return [...sets.values()];
}

// ---------- analysis ----------
const rules = parseRules(cssText);
const items = []; // one per selector of a rule
for (const r of rules) for (const s of splitTop(r.sel, [','])) { const cs = compounds(s); const subj = compound(cs[cs.length - 1] || ''); items.push({ sel: s, spec: spec(s), subj, decls: r.decls, order: r.order }); }
const buttons = collectButtons();
// a "global" reset = bare `button` whose ancestors are only the board root (e.g. `.mg button`, `:where(.mg) button`);
// contextual rules such as `.stars button` style one container on purpose and are not checked.
const rootCls = new Set(['mg', ...ROOT]);
const isRootAnc = (c) => { const x = compound(c); return (!x.tag || ['html', 'body', 'div'].includes(x.tag)) && !x.attrs && !x.pcs.length && x.cls.every((k) => rootCls.has(k)); };
const resets = items.filter((it) => { const cs = compounds(it.sel); return it.subj.tag === 'button' && !it.subj.cls.length && !it.subj.attrs && !it.subj.pcs.length && !it.subj.pe && it.decls.length && cs.slice(0, -1).every(isRootAnc); });
const findings = [];
for (const it of items) {
  if (it.subj.pe || resets.includes(it)) continue;
  if (it.subj.tag && it.subj.tag !== 'button') continue;
  if (!it.subj.cls.length && !it.subj.attrs) continue;
  const hit = buttons.filter((b) => it.subj.cls.every((c) => b.includes(c)));
  if (!hit.length) continue;
  for (const d of it.decls) {
    if (d.imp) continue;
    for (const rs of resets) {
      const c = cmp(rs.spec, it.spec);
      if (c < 0 || (c === 0 && rs.order < it.order)) continue;
      const rp = rs.decls.find((x) => overlaps(d.p, x.p)); if (!rp) continue;
      findings.push({ sel: it.sel, spec: it.spec.join(','), prop: d.p, reset: rs.sel, resetSpec: rs.spec.join(','), resetProp: rp.p, button: hit[0].join(' ') });
    }
  }
}
// group per selector
const by = new Map(); for (const f of findings) { const k = f.sel + '  <-  ' + f.reset; if (!by.has(k)) by.set(k, { ...f, props: new Set() }); by.get(k).props.add(f.prop); }
const grouped = [...by.values()].map((g) => ({ sel: g.sel, spec: g.spec, reset: g.reset, resetSpec: g.resetSpec, props: [...g.props], button: g.button }));
if (asJson) console.log(JSON.stringify({ resets: resets.map((r) => r.sel + ' (' + r.spec + ')'), buttons: buttons.length, findings: grouped }));
else {
  console.log('button resets:', resets.map((r) => r.sel + ' (' + r.spec + ')').join(' | ') || 'none', '· button class sets:', buttons.length);
  for (const g of grouped) console.log('LOSES TO RESET: ' + g.sel + ' (' + g.spec + ') vs ' + g.reset + ' (' + g.resetSpec + '): ' + g.props.join(',') + '  [e.g. <button class="' + g.button + '">]');
  console.log(grouped.length ? 'BTNRESET FAIL ' + grouped.length : 'BTNRESET OK');
}
