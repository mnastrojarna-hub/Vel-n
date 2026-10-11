// MotoGo24 — Velín: jazyk zákaznických dokumentů k rezervaci (smlouva, VOP, protokoly).
//
// edge `generate-document` bez parametru `language` vyráběl českou verzi a tu
// zákaznickou (např. EN) při přegenerování SMAZAL — zákazník pak v appce i na webu
// viděl českou smlouvu (audit 2026-10-10, EDGE-DOC-05). Každé (pře)generování
// dokumentu z Velína proto posílá jazyk rezervace → jazyk profilu → cs.

import { supabase } from './supabase'

export const DOC_LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']

export function normDocLang(v) {
  const l = String(v || '').trim().toLowerCase().slice(0, 2)
  return DOC_LANGS.includes(l) ? l : null
}

/** Jazyk dokumentů z načtené rezervace (bookings.language → profiles.language → cs). */
export function bookingDocLang(booking, profileLang) {
  return normDocLang(booking?.language) || normDocLang(profileLang ?? booking?.profiles?.language) || 'cs'
}

/**
 * Jazyk dokumentů dohledaný podle id rezervace. Při chybě dotazu vrací null —
 * volající pak jazyk NEPOSÍLÁ a edge funkce ho určí sama (nikdy tím nepřepíšeme
 * zákaznickou verzi českou jen kvůli výpadku dotazu).
 */
export async function fetchBookingDocLang(bookingId) {
  if (!bookingId) return null
  try {
    const { data, error } = await supabase.from('bookings').select('language, user_id').eq('id', bookingId).maybeSingle()
    if (error || !data) return null
    if (normDocLang(data.language)) return normDocLang(data.language)
    if (data.user_id) {
      const { data: prof, error: pErr } = await supabase.from('profiles').select('language').eq('id', data.user_id).maybeSingle()
      if (pErr) return null
      if (normDocLang(prof?.language)) return normDocLang(prof.language)
    }
    return 'cs'
  } catch {
    return null
  }
}

/** Vygeneruje (přegeneruje) dokument k rezervaci v jazyce zákazníka. */
export function generateBookingDoc(templateSlug, bookingId, language) {
  const lang = normDocLang(language)
  return supabase.functions.invoke('generate-document', {
    body: { template_slug: templateSlug, booking_id: bookingId, ...(lang ? { language: lang } : {}) },
  })
}
