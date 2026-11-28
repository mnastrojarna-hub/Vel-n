// ===== qr-payment/request-actions.ts =====
// QR údaje EXISTUJÍCÍHO požadavku na platbu (bank_payment_requests — doplatek úpravy rezervace z webu,
// dárkový poukaz) pro čekací obrazovku webu po obnovení stránky / na jiném zařízení, a jeho zrušení:
//   {action:'request', request_id | order_id | booking_id, locale?}
//   {action:'request_cancel', request_id}
// Oprávnění NEŘEŠÍ tato funkce: RPC get_bank_payment_request / cancel_bank_payment_request se volají
// pod tokenem VOLAJÍCÍHO (anon klíč / JWT zákazníka), takže platí jejich pravidla (podle rezervace jen
// vlastník nebo admin; podle UUID požadavku / objednávky jen platební údaje, žádné osobní údaje).
// Účet / IBAN / banka vždy z app_settings.company_info. Bez nasazeného SQL → 503 bank_unavailable.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { bankDetails, bankSpdMessage, bankSqlMissing, deadlineText, type BankKind } from '../_shared/bank-request.ts'
import { loadBookingLanguage, pickQrLang } from './texts.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
type Row = Record<string, unknown>
type Json = (o: unknown, status?: number) => Response

export const isRequestAction = (body: Row | null | undefined) => body?.action === 'request' || body?.action === 'request_cancel'

function callerClient(req: Request): Sb {
  const anon = Deno.env.get('SUPABASE_ANON_KEY') || ''
  return createClient(Deno.env.get('SUPABASE_URL') || '', anon, {
    global: { headers: { Authorization: req.headers.get('Authorization') || `Bearer ${anon}` } },
  })
}

export async function handleRequestAction(req: Request, body: Row, sb: Sb, json: Json): Promise<Response> {
  const caller = callerClient(req)
  if (body.action === 'request_cancel') {
    if (!body.request_id) return json({ success: false, error: 'missing_identifier' }, 400)
    const { data, error } = await caller.rpc('cancel_bank_payment_request', { p_request_id: body.request_id })
    if (error) return json({ success: false, error: 'bank_unavailable' }, bankSqlMissing(error) ? 503 : 500)
    const d = (data || {}) as Row
    if (d.success === true) return json({ success: true })
    return json(d, d.error === 'not_found' ? 404 : d.error === 'forbidden' ? 403 : 409)
  }

  if (!body.request_id && !body.order_id && !body.booking_id) return json({ success: false, error: 'missing_identifier' }, 400)
  const { data, error } = await caller.rpc('get_bank_payment_request', {
    p_request_id: body.request_id ?? null, p_booking_id: body.request_id ? null : (body.booking_id ?? null),
    p_order_id: body.request_id || body.booking_id ? null : (body.order_id ?? null),
  })
  if (error) return json({ success: false, error: 'bank_unavailable' }, bankSqlMissing(error) ? 503 : 500)
  const r = (data || {}) as Row
  if (r.error) return json({ success: false, error: r.error }, r.error === 'login_required' ? 401 : 400)
  if (r.status === 'none' || !r.request_id) return json({ success: true, status: 'none' })

  const kind = (r.kind === 'booking_change' ? 'booking_change' : 'shop_order') as BankKind
  let number = String(r.booking_id || r.order_id || '').slice(-8).toUpperCase()
  let rowLang: string | null = null
  if (kind === 'booking_change') rowLang = await loadBookingLanguage(sb, String(r.booking_id))
  else {
    try {
      const { data: o } = await sb.from('shop_orders').select('order_number, language').eq('id', r.order_id).maybeSingle()
      if (o?.order_number) number = String(o.order_number)
      rowLang = (o?.language as string) || null
    } catch { /* krátké id */ }
  }
  const lang = pickQrLang(body.locale, rowLang)
  const details = await bankDetails(sb, { vs: String(r.vs), amount: Number(r.amount), message: bankSpdMessage(kind, lang, number), expiresAt: (r.expires_at as string) || null })
  return json({
    success: true, request_id: r.request_id, kind, status: r.status, booking_id: r.booking_id ?? null, order_id: r.order_id ?? null,
    change_kind: r.change_kind ?? null, reason: r.reason ?? null, paid_at: r.paid_at ?? null, created_at: r.created_at ?? null,
    ...details, deadline_text: r.status === 'pending' ? deadlineText(kind, lang, details.expires_at) : '',
  })
}
