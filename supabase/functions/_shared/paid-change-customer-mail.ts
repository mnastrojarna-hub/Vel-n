// ===== _shared/paid-change-customer-mail.ts =====
// Zaplacenou změnu rezervace nešlo zapsat (typicky motorka je mezitím obsazená — nová
// rezervace má přednost, odpověď majitele 2026-10-16, otázka 3) a doplatek se vrací přímo
// ze Stripe — ta vratka zákazníkovi nic nepošle. Krátký e-mail v jazyce rezervace proto
// řekne, co se stalo, že původní rezervace platí beze změny, co se děje s doplatkem a co
// dál (vybrat jinou motorku / nechat současnou). Bez kontaktů (D5). Volá ho jen
// handlePaidChangeFailure — až po zámku „jednou na platbu", tedy jednou na platbu.
import type { Sb } from './extension-apply-types.ts'
import { LANGS, TX, type Lang } from './paid-change-customer-mail-texts.ts'

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
const fill = (s: string, v: Record<string, string>) => s.replace(/\{(\w+)\}/g, (_m, k) => v[k] ?? '')
const kc = (n: number) => `${(Math.round(n * 100) / 100).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`

export function normLang(l: unknown): Lang {
  const s = String(l || '').slice(0, 2).toLowerCase()
  return (LANGS as string[]).includes(s) ? s as Lang : 'cs'
}

/** Předmět + HTML e-mailu (čistá funkce — testovatelná bez sítě). */
export function paidChangeCustomerMail(a: { lang: unknown; bookingId: string; amount: number; taken: boolean; staff: boolean; site?: string }) {
  const lang = normLang(a.lang)
  const t = TX[lang]
  const num = a.bookingId.slice(-8).toUpperCase()
  const v = { num, amount: kc(a.amount) }
  const site = a.site || (lang === 'cs' ? (Deno.env.get('SITE_URL') || 'https://www.motogo24.cz') : 'https://motogo24.com')
  const url = `${site.replace(/\/$/, '')}/upravit-rezervaci?edit_booking=${encodeURIComponent(a.bookingId)}`
  const p = (s: string, extra = '') => `<p style="margin:0 0 12px;font-size:15px;line-height:1.5;color:#1a2e22${extra}">${esc(fill(s, v))}</p>`
  const html = `<div style="max-width:560px;margin:0 auto;font-family:Arial,Helvetica,sans-serif;background:#ffffff">`
    + `<div style="background:#000;color:#fff;padding:18px 24px;font-size:20px;font-weight:900;letter-spacing:2px">MOTO GO 24</div>`
    + `<div style="padding:22px 24px">`
    + p(`${t.hello} ${a.taken ? t.taken : t.failed}`)
    + p(t.unchanged, ';font-weight:700')
    + p(a.staff ? t.staff : t.auto)
    + p(a.taken ? t.nextTaken : t.nextFailed)
    + `<p style="margin:18px 0"><a href="${esc(url)}" style="display:inline-block;background:#74fb71;color:#0b0b0b;padding:12px 22px;border-radius:24px;font-weight:800;text-decoration:none">${esc(t.cta)}</a></p>`
    + p(t.sign, ';margin-top:18px')
    + `</div></div>`
  return { lang, subject: fill(a.taken ? t.subjTaken : t.subjFailed, v), html }
}

/** Odeslání zákazníkovi přes send-email (best-effort; bez e-mailu v profilu nic). */
export async function sendPaidChangeCustomerMail(sb: Sb, a: { bookingId: string; amount: number; taken: boolean; staff: boolean }): Promise<boolean> {
  try {
    const { data: bk } = await sb.from('bookings').select('user_id, language').eq('id', a.bookingId).maybeSingle()
    if (!bk?.user_id) return false
    const { data: pr } = await sb.from('profiles').select('email').eq('id', bk.user_id).maybeSingle()
    const to = String(pr?.email || '').trim()
    if (!to.includes('@')) return false
    const m = paidChangeCustomerMail({ lang: bk.language, ...a })
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const r = await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to, subject: m.subject, raw_html: m.html, booking_id: a.bookingId, customer_id: bk.user_id, language: m.lang }),
    })
    return r.ok
  } catch { return false }
}
