// ===== _shared/extension-apply-types.ts =====
// Typy a drobné pomocníky pro dokončení zaplacené změny rezervace (D6, 2026-10-16).
// Sdílí webhook-receiver a process-payment (complete_extension, odpuštění do 1 Kč).
// deno-lint-ignore no-explicit-any
export const round2 = (n)=>Math.round((Number(n) || 0) * 100) / 100;
/** Otisk místa rezervace (delivery_fee + způsob a adresa obou stran) — process-payment
 *  ho dává do metadata.srv.f, apply podle něj pozná, že se místo mezitím změnilo. */ export function placeFingerprint(r) {
  if (!r) return '';
  const norm = (v)=>String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
  const src = [
    Math.round(Number(r.delivery_fee || 0)),
    norm(r.pickup_method),
    norm(r.pickup_address),
    norm(r.return_method),
    norm(r.return_address)
  ].join('|');
  let h = 2166136261;
  for(let i = 0; i < src.length; i++){
    h ^= src.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h.toString(16);
}
/** Otisk payloadu změny (prvních 16 hex SHA-256) — shodný s metadata.chg_hash z process-payment
 *  (hash z JSON.stringify(change) = spojené chg…chg_8). Do historie úprav → pozná se, že TUTÉŽ
 *  změnu zapsala jiná platba (duplicita), ne jiná úprava se stejným výsledkem. */ export async function chgDigest(chg) {
  if (!chg) return null;
  try {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(chg));
    return Array.from(new Uint8Array(buf)).slice(0, 8).map((b)=>b.toString(16).padStart(2, '0')).join('');
  } catch  {
    return null;
  }
}
/** Záznam historie od vytvoření platby (`since`, rezerva 60 s) se značkou JINÉ platby. */ export function otherPaymentEntry(h, payRef, sinceMs) {
  if (!h || typeof h.payment_ref !== 'string' || !h.payment_ref || h.payment_ref === payRef) return false;
  if (sinceMs == null) return false;
  const t = Date.parse(String(h.at || ''));
  return Number.isFinite(t) && t >= sinceMs - 60_000;
}
/** Payload změny je v metadatech rozdělený po 500 znacích: chg, chg_2 … chg_8. */ export function chgFromMetadata(md) {
  if (!md || !md.chg) return null;
  let out = md.chg;
  for(let i = 2; i <= 8; i++){
    const part = md[`chg_${i}`];
    if (!part) break;
    out += part;
  }
  return out;
}
/** `failed` + manual = nejednoznačný stav (např. rezervace už jezdí na nové motorce, ale
 *  bez záznamu této platby) → bez automatické vratky, rozhodne obsluha. */ /** Odmítnutí triggerem / omezením (překryv, zavřená pobočka, vozík, pojistka
 *  přistavení) = trvalé; vše ostatní (síť, 5xx, timeout) = přechodné. */ export function isPermanentDbError(e) {
  const c = String(e?.code || '');
  return [
    'P0001',
    '23505',
    '23514',
    '23P01',
    '23502',
    '22P02',
    '22023'
  ].includes(c);
}
/** Chybí funkce / její signatura (SQL ještě nenasazené). */ export function isMissingFunction(e) {
  return /PGRST202|42883|could not find the function|does not exist/i.test(`${e?.code || ''} ${e?.message || ''}`);
}
export async function logDebug(sb, action, status, data, message) {
  try {
    await sb.from('debug_log').insert({
      source: 'extension-apply',
      action,
      component: 'stripe',
      status,
      error_message: message ?? null,
      request_data: data
    });
  } catch  {}
}
