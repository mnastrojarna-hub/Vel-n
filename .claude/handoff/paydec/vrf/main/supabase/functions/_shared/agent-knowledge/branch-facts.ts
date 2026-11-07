// ===== _shared/agent-knowledge/branch-facts.ts =====
// Pobočky pro AI agenty (audit i18n 2026-10-10, AI-07/AI-13): branches.opening_hours je
// jsonb objekt ({mo:'00:00-24:00',…}) — snapshot ho dřív vložil jako „[object Object]"
// a get_branches ho vracel syrový vedle is_open_nonstop (= jen „není trvale zavřená").
// Majitel 2026-10-10: OBĚ pobočky NONSTOP (výdej/vrácení kdykoli dle času v rezervaci).
// Tool get_branches je sdílený — web agent i agent v appce mají stejná fakta i notice.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GATE_BRANCHES_NOTICE_CS, markGateBranches } from './branch-gate.ts'

const DAY_CS: Record<string, string> = { mo: 'Po', tu: 'Út', we: 'St', th: 'Čt', fr: 'Pá', sa: 'So', su: 'Ne' }
const isNonstop = (v: unknown) => /^\s*(0?0:00\s*-\s*24:00|00:00\s*-\s*23:59|nonstop|24\/7)\s*$/i.test(String(v ?? ''))

/** Čitelná otevírací doba (text) z jsonb/textu; null = neuvedeno. */
export function formatOpeningHours(oh: unknown): string | null {
  if (oh == null || oh === '') return null
  if (typeof oh === 'string') return isNonstop(oh) ? 'NONSTOP (Po–Ne 0–24 h)' : oh
  if (typeof oh !== 'object') return String(oh)
  const o = oh as Record<string, unknown>
  const days = Object.keys(DAY_CS).filter((d) => o[d] != null)
  if (days.length === 7 && days.every((d) => isNonstop(o[d]))) return 'NONSTOP (Po–Ne 0–24 h)'
  if (days.length === 0) {
    const all = o.all ?? o.default
    return all != null ? formatOpeningHours(String(all)) : null
  }
  return days.map((d) => `${DAY_CS[d]} ${dayText(o[d])}`).join(', ')
}

/** Provozní doba z DB jen když je NONSTOP, jinak null. Majitel 2026-10-10 potvrdil NONSTOP u obou
 *  poboček (owner-facts.ts); jiný údaj (starý seed Po–Pá 8–18, So 9–14, Ne zavřeno — data opravuje
 *  migrace 20261011_i18n_customer_language) by závazným faktům odporoval → agent ho nedostane. */
export function nonstopHours(oh: unknown): string | null {
  const t = formatOpeningHours(oh)
  return t && t.startsWith('NONSTOP') ? t : null
}

// Hodnota dne: 'HH:MM-HH:MM' | 'closed' | {open, close} | cokoli jiného (nikdy „[object Object]")
function dayText(v: unknown): string {
  if (v && typeof v === 'object') {
    const r = v as Record<string, unknown>
    if (r.closed === true) return 'zavřeno'
    if (r.open != null || r.close != null) return `${r.open ?? '?'}-${r.close ?? '?'}`
    try { return JSON.stringify(v) } catch { return '?' }
  }
  return String(v).replace(/^closed$/i, 'zavřeno')
}

/** Text režimu pobočky pro tooly a snapshoty (dle typu + majitelova fakta 2026-10-10, vrácení 2026-10-11, palivo 2026-10-12). */
export function branchModeCs(type: unknown): string {
  return type === 'samoobslužná'
    ? 'SAMOOBSLUŽNÁ — NONSTOP: výdej i vrácení 24/7 přístupovým kódem (bez obsluhy); vrací se UMYTÁ a bez svítící kontrolky rezervy (tankovat ani plná nádrž netřeba)'
    : type === 'obslužná'
      ? 'OBSLUŽNÁ — NONSTOP: motorku předá a převezme obsluha v čase z rezervace (kdykoli 0–24 h, výdej nejdřív 1–6 h po vytvoření a zaplacení rezervace); vrací se bez mytí i tankování, jen ať nesvítí kontrolka rezervy'
      : 'typ neuveden — režim výdeje netvrď, ověř u firmy'
}

export const BRANCHES_TOOL_NOTICE_CS = 'REŽIM výdeje/vrácení urči VÝHRADNĚ z pole `type` konkrétní pobočky (`mode` ho shrnuje). OBĚ pobočky fungují NONSTOP (potvrzeno majitelem): "samoobslužná" = výdej i vrácení 24/7 přístupovým kódem; "obslužná" = motorku předává a přebírá OBSLUHA osobně v čase z rezervace (kdykoli 0–24 h). Nikdy neuváděj zavírací dny ani hodiny, které nejsou v `opening_hours_text`. Přístupové kódy chodí e-mailem u OBOU typů — u obslužné pobočky neotvírají dveře, slouží jako IDENTIFIKACE: zákazník je řekne obsluze, ta podle nich rezervaci dohledá, předání ~2 minuty; sken dokladů předem není podmínkou převzetí (obsluha je zkontroluje na místě; kódy ale přijdou až s kompletními doklady), doporučuje se ale (urychlí odbavení, zvlášť při více odjezdech najednou). NIKDY netvrď, že výdej je VŠUDE samoobslužný, ani že u obslužné pobočky kódy nechodí. Rezervaci lze VYTVOŘIT 24/7 u obou typů — u OBSLUŽNÉ pobočky proběhne výdej nejdřív 1–6 hodin PO vytvoření a zaplacení rezervace (příprava stroje), tam neslibuj okamžité vyzvednutí. U SAMOOBSLUŽNÉ pobočky se volí jen čas VYZVEDNUTÍ (hodina předem potřeba není, rezervovat lze i na dnešek) — čas vrácení ne (vrací se kdykoli poslední den do 24:00). Vyzvednutí od 12:00 při výpůjčce 2+ dny = sleva 50 % na 1. den, ale kiosk takovou rezervaci (motorku i šatnu) vydá až od 12:00 v den začátku; kdo ji potřebuje dřív, změní v Upravit rezervaci (web/appka) čas vyzvednutí na dřívější — sleva zanikne, rozdíl doplatí a kód platí hned. U přistavení platí čas min. aktuální + 6 h. Vrácení: tankovat netřeba nikde (plná nádrž není potřeba), jen ať nesvítí kontrolka rezervy paliva (na samoobslužné pobočce NESMÍ svítit); motorka musí být UMYTÁ jen na samoobslužné pobočce — na obslužné pobočce (i při vrácení jinde) se nemyje. Při převzetí NIKDY neslibuj plnou nádrž (předává se s tím, co v ní je).'

/** Pole pro externí kanály (MCP, public API) anglicky: režim (+ pravidlo vrácení jako branchModeCs, 2026-10-11/12) + čitelná provozní doba (obě NONSTOP). */
export function branchPublicFieldsEn(b: Record<string, unknown>): { mode: string | null; opening_hours_text: string } {
  const self = b.type === 'samoobslužná'
  return {
    mode: self ? 'self-service (24/7 access code, no staff); return: no refuelling needed (a full tank is not required), but the motorcycle must be returned washed and the fuel reserve warning light must not be on'
      : b.type === 'obslužná' ? 'staffed (handover by staff at the booked time, nonstop); return (also at another agreed place): no washing and no refuelling needed, just make sure the fuel reserve warning light is not on' : null,
    opening_hours_text: self ? 'NONSTOP (0–24 h, self-service with access code)'
      : 'NONSTOP (0–24 h, handover by staff at the booked time)', // viz nonstopHours (fakta majitele)
  }
}

/** Implementace toolu get_branches (web agent i agent v appce). */
export async function getBranchesTool(sb: SupabaseClient): Promise<unknown> {
  // select('*') SCHVÁLNĚ — výčet neexistujících sloupců dřív shodil dotaz (PostgREST 42703)
  // a agent tvrdil „pobočky nemáme" (incident 2026-08-05).
  const { data, error } = await sb.from('branches').select('*').order('name')
  // is_open === false = trvale zavřená pobočka: nenabízet.
  const rows = ((data || []) as Array<Record<string, unknown>>).filter((b) => b.active !== false && b.is_open !== false)
  await markGateBranches(sb, rows) // has_gate = jen příznak (RPC branch_has_gate), NIKDY kód
  if (error || rows.length === 0) {
    const { data: ci } = await sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
    const c = (ci?.value || {}) as Record<string, unknown>
    return {
      branches: [],
      ...(error ? { error: `Načtení poboček selhalo: ${error.message}` } : {}),
      fallback_contact: {
        name: c.name || 'MotoGo24', address: c.address || 'Mezná 9, 393 01 Pelhřimov',
        phone: c.phone || '+420 774 256 271', email: c.email || 'info@motogo24.cz',
      },
      notice: 'Seznam poboček se teď nepodařilo načíst — TECHNICKÁ chyba, NE stav reality. NIKDY zákazníkovi netvrď, že žádné pobočky nemáme nebo že je seznam v databázi prázdný. Vyzvednutí motorky probíhá na naší pobočce — pošli zákazníka na adresu ve `fallback_contact` (hlavní výdejní místo) a nabídni telefon/e-mail pro potvrzení detailů.',
    }
  }
  return {
    branches: rows.map((b) => {
      const lat = b.lat ?? b.gps_lat ?? null
      const lng = b.lng ?? b.gps_lng ?? null
      return {
        id: b.id, name: b.name,
        address: [b.address, `${b.zip || ''} ${b.city || ''}`.trim()].filter(Boolean).join(', '),
        lat, lng,
        maps_url: (lat != null && lng != null) ? `https://mapy.cz/zakladni?q=${lat},${lng}` : null,
        phone: b.phone ?? null, email: b.email ?? null,
        type: b.type, mode: branchModeCs(b.type),
        opening_hours_text: b.type === 'samoobslužná' ? 'NONSTOP (Po–Ne 0–24 h, kódem)' : (nonstopHours(b.opening_hours) || 'NONSTOP (Po–Ne 0–24 h) — čas předání dle rezervace'),
        notes: b.notes, has_gate: b.has_gate === true,
      }
    }),
    notice: BRANCHES_TOOL_NOTICE_CS + (rows.some((b) => b.has_gate === true) ? GATE_BRANCHES_NOTICE_CS : ''),
  }
}
