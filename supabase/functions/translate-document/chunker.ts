// Dělení dlouhého HTML na části k překladu (audit EDGE-DOC-08) — na hranicích bloků nejvyšší úrovně.
// VOP má ~62 tis. znaků (Word HTML s inline styly, <p> uvnitř <h1>, vše v <div class="wrap">) —
// celodokumentový request se nevešel do časového limitu edge funkce ani do max_tokens.
//
// Postup: HTML → strom (tolerantní k chybějícím koncovým tagům) → lineární „jednotky“:
//   - překládané: celý prvek (podstrom) nebo souvislý běh textu + inline prvků,
//   - průchozí (model je NEVIDÍ): komentáře, doctype, <style>/<script>/<meta>/<link>, bílé znaky,
//     otevírací a zavírací tag kontejneru, do kterého se „sestoupilo“ (html/head/body vždy;
//     div/h1/ol/table… jen když jsou větší než cíl a obsahují blokové prvky).
// Jednotky se skládají do částí o ~CHUNK_TARGET znacích překládaného textu; průchozí jednotky
// uvnitř části nahradí značka <!--mg:N--> (model ji musí zachovat), na krajích části jdou mimo.
// Spojení přeložených částí + průchozích úseků vrátí dokument ve stejném pořadí; při identickém
// „překladu“ je výsledek bajtově shodný se vstupem (test v CHANGES).
export const CHUNK_TARGET = 9000;
const VOID = new Set([
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr'
]);
const RAW = new Set([
  'style',
  'script'
]);
const PASS = new Set([
  'style',
  'script',
  'meta',
  'link',
  'base',
  'noscript'
]);
const ALWAYS_DESCEND = new Set([
  'html',
  'head',
  'body'
]);
export const BLOCK = new Set([
  'address',
  'article',
  'aside',
  'blockquote',
  'dd',
  'div',
  'dl',
  'dt',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
  'title'
]);
const TOKEN = /<!--[\s\S]*?-->|<![^>]*>|<(\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:"[^"]*"|'[^']*'|[^'">])*)>/g;
/** HTML → seznam uzlů nejvyšší úrovně. Neuzavřený prvek končí tam, kde se uzavřel rodič. */ export function parseHtml(html) {
  const root = {
    kind: 'el',
    tag: '#root',
    start: 0,
    end: html.length,
    children: []
  };
  const stack = [
    root
  ];
  let pos = 0;
  const top = ()=>stack[stack.length - 1];
  const pushText = (a, b)=>{
    if (b > a) top().children.push({
      kind: 'text',
      start: a,
      end: b
    });
  };
  TOKEN.lastIndex = 0;
  let m;
  while((m = TOKEN.exec(html)) !== null){
    const s = m.index, e = s + m[0].length;
    pushText(pos, s);
    pos = e;
    if (m[0].startsWith('<!--')) {
      top().children.push({
        kind: 'comment',
        start: s,
        end: e
      });
      continue;
    }
    if (!m[2]) {
      top().children.push({
        kind: 'doctype',
        start: s,
        end: e
      });
      continue;
    }
    const tag = m[2].toLowerCase();
    if (m[1]) {
      let i = stack.length - 1;
      while(i > 0 && stack[i].tag !== tag)i--;
      if (i === 0) {
        top().children.push({
          kind: 'text',
          start: s,
          end: e
        });
        continue;
      }
      while(stack.length - 1 > i){
        const n = stack.pop();
        n.end = s;
      }
      const n = stack.pop();
      n.closeStart = s;
      n.end = e;
      continue;
    }
    const node = {
      kind: 'el',
      tag,
      start: s,
      end: e,
      openEnd: e,
      children: []
    };
    top().children.push(node);
    if (VOID.has(tag) || /\/\s*$/.test(m[3])) continue;
    if (RAW.has(tag)) {
      const close = html.toLowerCase().indexOf(`</${tag}`, e);
      const ce = close < 0 ? html.length : html.indexOf('>', close) + 1 || html.length;
      node.closeStart = close < 0 ? undefined : close;
      node.end = ce;
      pos = ce;
      TOKEN.lastIndex = ce;
      continue;
    }
    stack.push(node);
  }
  pushText(pos, html.length);
  while(stack.length > 1){
    const n = stack.pop();
    n.end = html.length;
  }
  return root.children;
}
function isBlockEl(n) {
  return n.kind === 'el' && BLOCK.has(n.tag);
}
function linearize(html, nodes, out) {
  let run = null // souvislý běh textu + inline prvků = jedna jednotka
  ;
  const flush = ()=>{
    if (run) {
      out.push(run);
      run = null;
    }
  };
  for (const n of nodes){
    const size = n.end - n.start;
    if (n.kind === 'comment' || n.kind === 'doctype' || n.kind === 'el' && PASS.has(n.tag)) {
      flush();
      out.push({
        start: n.start,
        end: n.end,
        translate: false
      });
      continue;
    }
    if (n.kind === 'text' || n.kind === 'el' && !isBlockEl(n) && !ALWAYS_DESCEND.has(n.tag)) {
      if (run) run.end = n.end;
      else run = {
        start: n.start,
        end: n.end,
        translate: true
      };
      continue;
    }
    flush();
    const kids = n.children || [];
    const descend = ALWAYS_DESCEND.has(n.tag) || size > CHUNK_TARGET && kids.some(isBlockEl);
    if (!descend) {
      out.push({
        start: n.start,
        end: n.end,
        translate: true
      });
      continue;
    }
    out.push({
      start: n.start,
      end: n.openEnd,
      translate: false
    });
    linearize(html, kids, out);
    const innerEnd = kids.length ? kids[kids.length - 1].end : n.openEnd;
    if (n.end > innerEnd) out.push({
      start: innerEnd,
      end: n.end,
      translate: false
    });
  }
  flush();
  // běh jen z bílých znaků = průchozí (model nemá co překládat)
  for (const u of out)if (u.translate && !html.slice(u.start, u.end).trim()) u.translate = false;
}
const MARK = (i)=>`<!--mg:${i}-->`;
export const MARK_RE = /<!--mg:(\d+)-->/g;
/** HTML → úseky: doslovné (verbatim) a části k překladu (text se značkami průchozích úseků). */ export function chunkHtml(html, target = CHUNK_TARGET) {
  const units = [];
  linearize(html, parseHtml(html), units);
  const groups = [];
  let cur = [], curSize = 0;
  for (const u of units){
    const sz = u.translate ? u.end - u.start : 0;
    if (u.translate && curSize > 0 && curSize + sz > target) {
      groups.push(cur);
      cur = [];
      curSize = 0;
    }
    cur.push(u);
    curSize += sz;
  }
  if (cur.length) groups.push(cur);
  const segs = [];
  const pushVerbatim = (s)=>{
    if (!s) return;
    const l = segs[segs.length - 1];
    if (l && l.verbatim !== undefined) l.verbatim += s;
    else segs.push({
      verbatim: s
    });
  };
  for (const g of groups){
    let a = 0, b = g.length;
    while(a < b && !g[a].translate)pushVerbatim(html.slice(g[a].start, g[a++].end));
    while(b > a && !g[b - 1].translate)b--;
    if (a < b) {
      const markers = [];
      let text = '';
      for(let i = a; i < b; i++){
        const piece = html.slice(g[i].start, g[i].end);
        if (g[i].translate) text += piece;
        else {
          text += MARK(markers.length);
          markers.push(piece);
        }
      }
      segs.push({
        chunk: {
          text,
          markers
        }
      });
    }
    for(let i = b; i < g.length; i++)pushVerbatim(html.slice(g[i].start, g[i].end));
  }
  return segs;
}
/** Spojí úseky; `translated[i]` = přeložený text i-té části (značky se nahradí zpět). */ export function assemble(segs, translated) {
  let k = 0;
  return segs.map((s)=>{
    if (s.verbatim !== undefined) return s.verbatim;
    const c = s.chunk;
    const t = translated[k++];
    return t.replace(MARK_RE, (_, n)=>c.markers[Number(n)] ?? '');
  }).join('');
}
