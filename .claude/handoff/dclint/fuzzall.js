// In-process fuzz over prop combinations (same logic as fuzz.js, plus queued timers flushed between taps).
// node fuzzall.js <board> [fullLimit]
// 1) every rank 1-20 x (defaults + each single enum/boolean option), 400 taps
// 2) pairwise covering set over all props (rank as 20-level factor), 120 taps
// 3) full cartesian of enum/boolean props (rank cycles 1-20) when <= fullLimit combos, 40 taps
const fs = require('fs');
const [file, limArg] = process.argv.slice(2);
const FULL_LIMIT = +(limArg || 10000);
const src = fs.readFileSync(file, 'utf8');
const m = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/);
let queue = [];
global.setTimeout = (fn, ms) => { queue.push(fn); return queue.length; };
global.clearTimeout = () => {};
global.setInterval = (fn) => { queue.push(fn); return queue.length; };
global.clearInterval = () => {};
global.requestAnimationFrame = (fn) => { queue.push(() => fn(0)); return queue.length; };
global.cancelAnimationFrame = () => {};
global.DCLogic = class { constructor(p) { this.props = p; } setState(o) { this.state = Object.assign({}, this.state, typeof o === 'function' ? o(this.state) : o); } };
const Component = new Function(m[1] + '\nreturn Component;')();
const dp = JSON.parse(src.match(/data-props='([^']*)'/)[1]);
const keys = Object.keys(dp).filter(k => k !== '$preview');
const defaults = {}; for (const k of keys) defaults[k] = dp[k].default;
const optsOf = k => { const d = dp[k]; if (d.editor === 'enum') return d.options; if (d.editor === 'boolean') return [false, true]; if (k === 'rank') { const a = []; for (let i = d.min; i <= d.max; i++) a.push(i); return a; } const a = []; for (let i = d.min; i <= d.max; i++) a.push(i); return a.length <= 21 ? a : [d.min, d.default, d.max]; };
const holes = [...new Set([...src.matchAll(/\{\{\s*([\w$.]+)\s*\}\}/g)].map(x => x[1]))];
const loopVars = new Set([...src.matchAll(/<sc-for[^>]*\bas="(\w+)"/g)].map(x => x[1]));
const fns = (v, path, out) => { if (typeof v === 'function') out.push([path, v]); else if (Array.isArray(v)) v.forEach((x, i) => fns(x, path + '[' + i + ']', out)); else if (v && typeof v === 'object') for (const k in v) fns(v[k], path + '.' + k, out); return out; };
let runs = 0, taps = 0, timersRun = 0; const errors = new Map(); const missingAll = new Map();
function run(props, n, seed0) {
  runs++; queue = []; let seed = seed0; const rnd = (k) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % k; };
  const tag = JSON.stringify(Object.fromEntries(Object.entries(props).filter(([k, v]) => v !== defaults[k])));
  const fail = (where, e) => { const key = where + ': ' + (e && e.message); if (!errors.has(key)) errors.set(key, tag); };
  let c, r;
  try { c = new Component(Object.assign({}, props)); r = c.renderVals(); } catch (e) { fail('init', e); return; }
  const check = () => { for (const h of holes) { const top = h.split('.')[0]; if (loopVars.has(top) || /^(true|false|\d+)$/.test(h)) continue; let v = r; for (const k of h.split('.')) v = v == null ? undefined : v[k]; if (v === undefined && !missingAll.has(h)) missingAll.set(h, tag); } };
  for (let i = 0; i < n; i++) {
    check();
    const f = fns(r, 'r', []); if (!f.length) break;
    const [p, fn] = f[rnd(f.length)];
    try { fn({ target: { value: 'Test ' + i }, stopPropagation() {}, preventDefault() {} }); taps++; r = c.renderVals(); } catch (e) { fail('tap ' + p.replace(/\[\d+\]/g, '[]'), e); return; }
    let budget = 40; while (queue.length && budget--) { const t = queue.shift(); try { t(); timersRun++; r = c.renderVals(); } catch (e) { fail('timer', e); return; } }
  }
  check();
}
// 1) one-factor-at-a-time x every rank
const ranks = optsOf('rank');
let s = 11;
for (const rk of ranks) {
  run(Object.assign({}, defaults, { rank: rk }), 400, s++);
  for (const k of keys) if (k !== 'rank') for (const o of optsOf(k)) if (o !== defaults[k]) run(Object.assign({}, defaults, { rank: rk, [k]: o }), 400, s++);
}
// 2) pairwise covering (greedy)
const fac = keys.map(k => optsOf(k));
const uncovered = new Set();
for (let a = 0; a < keys.length; a++) for (let b = a + 1; b < keys.length; b++) for (let i = 0; i < fac[a].length; i++) for (let j = 0; j < fac[b].length; j++) uncovered.add(a + ':' + i + ':' + b + ':' + j);
let pw = 0; let rs = 99;
const rr = (k) => { rs = (rs * 1103515245 + 12345) % 2147483648; return rs % k; };
while (uncovered.size && pw < 5000) {
  let best = null, bestGain = -1;
  for (let t = 0; t < 30; t++) {
    const first = [...uncovered][rr(uncovered.size)].split(':').map(Number);
    const row = fac.map(f => rr(f.length)); row[first[0]] = first[1]; row[first[2]] = first[3];
    let gain = 0; for (let a = 0; a < keys.length; a++) for (let b = a + 1; b < keys.length; b++) if (uncovered.has(a + ':' + row[a] + ':' + b + ':' + row[b])) gain++;
    if (gain > bestGain) { bestGain = gain; best = row; }
  }
  for (let a = 0; a < keys.length; a++) for (let b = a + 1; b < keys.length; b++) uncovered.delete(a + ':' + best[a] + ':' + b + ':' + best[b]);
  const props = {}; keys.forEach((k, i) => props[k] = fac[i][best[i]]);
  run(props, 120, 5000 + pw++);
}
// 3) full cartesian over enum/boolean (rank cycles)
const ek = keys.filter(k => dp[k].editor === 'enum' || dp[k].editor === 'boolean');
const total = ek.reduce((n, k) => n * optsOf(k).length, 1);
let full = 0;
if (total <= FULL_LIMIT) {
  const idx = ek.map(() => 0);
  for (let n = 0; n < total; n++) {
    const props = Object.assign({}, defaults, { rank: ranks[n % ranks.length] });
    ek.forEach((k, i) => props[k] = optsOf(k)[idx[i]]);
    run(props, 40, 90000 + n); full++;
    for (let i = 0; i < idx.length; i++) { idx[i]++; if (idx[i] < optsOf(ek[i]).length) break; idx[i] = 0; }
  }
}
console.log(file.split('/').pop(), '| runs', runs, '| taps', taps, '| timers', timersRun, '| pairwise rows', pw, '| full cartesian', total <= FULL_LIMIT ? full + '/' + total : 'skipped (' + total + ' combos)');
if (missingAll.size) console.log('  UNDEFINED holes:', [...missingAll].slice(0, 20).map(([h, t]) => h + ' @ ' + t).join(' | '));
if (errors.size) { console.log('  ERRORS:'); for (const [e, t] of [...errors].slice(0, 20)) console.log('   ', e, '@', t); process.exitCode = 1; } else console.log('  fuzzall ok');
