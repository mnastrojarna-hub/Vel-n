// Kontrola přeložené části (audit EDGE-DOC-08): useknutý, zkrácený nebo poškozený překlad
// právního textu se NIKDY neuloží. Vrací null = OK, jinak popis problému (→ opakování / chyba).
import { placeholderList } from '../_shared/doc-i18n.ts';
import { MARK_RE } from './chunker.ts';
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
// Strukturní prvky: počet MUSÍ sedět (ztracený odstavec / řádek tabulky = vynechaný článek).
const STRUCT = new Set([
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'ol',
  'ul',
  'table',
  'tr',
  'td',
  'th',
  'title'
]);
function tagStats(html) {
  const balance = new Map(), opens = new Map();
  const s = html.replace(/<!--[\s\S]*?-->/g, '');
  const re = /<(\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:"[^"]*"|'[^']*'|[^'">])*)>/g;
  let m;
  while((m = re.exec(s)) !== null){
    const tag = m[2].toLowerCase();
    if (VOID.has(tag) || /\/\s*$/.test(m[3])) continue;
    balance.set(tag, (balance.get(tag) || 0) + (m[1] ? -1 : 1));
    if (!m[1]) opens.set(tag, (opens.get(tag) || 0) + 1);
  }
  return {
    balance,
    opens
  };
}
/** Viditelný text (bez tagů, entity &nbsp; → mezera). */ export function visibleText(html) {
  return html.replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<!--[\s\S]*?-->/g, ' ').replace(/<[^>]*>/g, ' ').replace(/&nbsp;|&#160;| /g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
}
/** Částky před „Kč“ a procenta jako číslice (bez oddělovačů tisíců) — v překladu musí zůstat. */ export function amountList(html) {
  const t = visibleText(html);
  const out = [];
  // „30 000 Kč“, „30,000 Kč“, „30.000 Kč“, „1 500,50 Kč“, „100 %“ — oddělovač tisíců smí překlad změnit
  const re = /(\d{1,3}(?:[ .,'  ]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?)\s*(Kč|%)/g;
  let m;
  while((m = re.exec(t)) !== null)out.push(m[1].replace(/\D/g, '') + m[2]);
  return out.sort();
}
const sameList = (a, b)=>a.length === b.length && a.every((v, i)=>v === b[i]);
const markers = (s)=>(s.match(MARK_RE) || []).join(',');
export function validateChunk(src, out) {
  if (!out || !out.trim()) return 'empty_output';
  if (markers(src) !== markers(out)) return 'structure_markers_changed';
  if (!sameList(placeholderList(src), placeholderList(out))) {
    return `placeholders_changed: ${placeholderList(src).join(' ')} → ${placeholderList(out).join(' ')}`.slice(0, 300);
  }
  const a = tagStats(src), b = tagStats(out);
  for (const tag of new Set([
    ...a.balance.keys(),
    ...b.balance.keys()
  ])){
    if ((a.balance.get(tag) || 0) !== (b.balance.get(tag) || 0)) return `unbalanced_tag: <${tag}>`;
  }
  for (const tag of STRUCT){
    if ((a.opens.get(tag) || 0) !== (b.opens.get(tag) || 0)) return `structure_changed: <${tag}> ${a.opens.get(tag) || 0} → ${b.opens.get(tag) || 0}`;
  }
  const amA = amountList(src), amB = amountList(out);
  if (!sameList(amA, amB)) return `amounts_changed: ${amA.join(' ')} → ${amB.join(' ')}`.slice(0, 300);
  const ta = visibleText(src), tb = visibleText(out);
  if (ta.length >= 200) {
    const ratio = tb.length / ta.length;
    if (ratio < 0.4 || ratio > 2.5) return `length_ratio_${ratio.toFixed(2)}`;
    if (ta === tb && /[áčďéěíňóřšťúůýž]/i.test(ta)) return 'not_translated';
  }
  return null;
}
/** PDF část (zdroj není HTML): jen neprázdná a vyvážená. */ export function validatePdfPart(out) {
  if (!out || visibleText(out).length < 20) return 'empty_output';
  const b = tagStats(out);
  for (const [tag, n] of b.balance)if (n !== 0 && ![
    'p',
    'li',
    'td',
    'th',
    'tr'
  ].includes(tag)) return `unbalanced_tag: <${tag}>`;
  return null;
}
