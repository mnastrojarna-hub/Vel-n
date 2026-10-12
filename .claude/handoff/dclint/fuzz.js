// Spustí renderVals, pak náhodně mačká všechny funkce (i vnořené v polích/objektech) a znovu renderuje.
const fs = require('fs');
const [file, propsJson] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const m = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/);
global.DCLogic = class { constructor(p) { this.props = p; } setState(o) { this.state = Object.assign({}, this.state, typeof o === 'function' ? o(this.state) : o); } };
const Component = new Function(m[1] + '\nreturn Component;')();
const dp = JSON.parse(src.match(/data-props='([^']*)'/)[1]);
const props = {}; for (const k in dp) if (k !== '$preview') props[k] = dp[k].default;
Object.assign(props, JSON.parse(propsJson || '{}'));
const c = new Component(props);
const fns = (v, path, out) => { if (typeof v === 'function') out.push([path, v]); else if (Array.isArray(v)) v.forEach((x, i) => fns(x, path + '[' + i + ']', out)); else if (v && typeof v === 'object') for (const k in v) fns(v[k], path + '.' + k, out); return out; };
let seed = 7; const rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const holes = [...new Set([...src.matchAll(/\{\{\s*([\w$.]+)\s*\}\}/g)].map(x => x[1]))];
const loopVars = new Set([...src.matchAll(/<sc-for[^>]*\bas="(\w+)"/g)].map(x => x[1]));
let r = c.renderVals(), calls = 0, missing = new Set();
for (let i = 0; i < 400; i++) {
  for (const h of holes) { const top = h.split('.')[0]; if (loopVars.has(top) || /^(true|false|\d+)$/.test(h)) continue; let v = r; for (const k of h.split('.')) v = v == null ? undefined : v[k]; if (v === undefined) missing.add(h); }
  const f = fns(r, 'r', []); if (!f.length) break;
  const [p, fn] = f[rnd(f.length)];
  try { fn({ target: { value: 'Test ' + i } }); calls++; r = c.renderVals(); } catch (e) { console.log('ERR after', p, e.message); process.exit(1); }
}
console.log('fuzz ok, calls', calls, missing.size ? 'UNDEFINED holes (some state): ' + [...missing].slice(0, 30).join(', ') : 'no undefined holes');
