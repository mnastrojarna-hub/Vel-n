// fio-sync — automatické potvrzování QR / bankovních plateb z Fio API.
//
// Nový firemní účet je u Fio banky a je napojený na API Bankovnictví
// (https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf). Cron `fio-bank-sync`
// (pg_cron → fio_sync_tick() → tato funkce) každých 5 minut stáhne nové
// příchozí pohyby endpointem „od posledního stažení":
//   GET https://fioapi.fio.cz/v1/rest/last/{token}/transactions.json
// Fio si zarážku (ID posledního pohybu) posouvá samo; minimální interval
// dotazu na token je 30 s (dřívější dotaz vrací 409 Conflict → skip).
//
// Každý pohyb se idempotentně uloží do `fio_transactions` (PK = fio ID pohybu)
// a příchozí platba se spáruje přes VS:
//   1. bookings.payment_vs       → celá platba rezervace (QR / převod z webu)
//   2. bookings.mod_surcharge_vs → doplatek za úpravu zaplacené rezervace
//   3. invoices.variable_symbol  → fallback: VS z ručně vystavené ZF k rezervaci
//
// Potvrzení jde STEJNÝM flow jako ruční tlačítko „Potvrdit platbu" ve Velíně
// (BookingDetail.confirmManualPayment) / Stripe webhook — jen se nekliká:
//   • payment_reference = FIO ID pohybu
//   • RPC confirm_payment (p_method='bank_transfer') — atomic dedup, revive se tu
//     záměrně NEvyužívá (platba po auto-zrušení = needs_review, řeší admin ručně)
//   • ZF (pokud chybí) + DP přes generate-invoice se skutečným VS platby
//     a datem úhrady — send-booking-email je pak reuse-ne jako přílohy
//   • mail: web + nedokončené doklady → invoice_payment_receipt, jinak
//     booking_reserved (stejné rozhodnutí jako webhook-receiver / Velín)
//   • in-app zpráva do vlákna (parita se sendBookingMessage ve Velíně)
// Doplatek jde přes RPC confirm_booking_surcharge (od 20260829 pouští
// i service_role) — ta sama pošle odložený booking_modified mail + app zprávu.
//
// Nespárované / nesedící platby se NEPOTVRZUJÍ — jen se zapíšou a pošle se
// upozornění na info@motogo24.cz; ruční tlačítko ve Velíně zůstává fallback.
//
// Auth: service key / service_role claim / klíč z app_settings / admin JWT
// (vzor mirror-route-images). Secret: FIO_API_TOKEN (Supabase Edge secrets).

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FIO_TOKEN = Deno.env.get('FIO_API_TOKEN') || ''
const OPS_EMAIL = 'info@motogo24.cz'
const FIO_BASE = 'https://fioapi.fio.cz/v1/rest'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

const fmtAmount = (n: number) => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2)

/// Je token service_role JWT? Jen claim, bez ověření podpisu (viz send-push /
/// mirror-route-images — po rotaci klíčů může platit víc service klíčů zároveň).
function isServiceRole(token: string): boolean {
  try {
    const p = token.split('.')
    if (p.length !== 3) return false
    const pad = '='.repeat((4 - (p[1].length % 4)) % 4)
    const payload = JSON.parse(atob(p[1].replace(/-/g, '+').replace(/_/g, '/') + pad))
    return payload.role === 'service_role'
  } catch (_) {
    return false
  }
}

type FioColumn = { value: unknown } | null
type FioTx = Record<string, FioColumn>

const colStr = (tx: FioTx, key: string): string | null => {
  const v = tx[key]?.value
  return v === null || v === undefined || v === '' ? null : String(v)
}
const colNum = (tx: FioTx, key: string): number => Number(tx[key]?.value ?? 0)

/// Datum pohybu (column0) → YYYY-MM-DD v Europe/Prague. JSON vrací epoch ms
/// (starší verze) nebo string „2023-08-25+0200" (novější) — zvládáme obojí.
function txDate(tx: FioTx): string {
  const v = tx['column0']?.value
  if (typeof v === 'number') return new Date(v).toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
  if (typeof v === 'string' && v.length >= 10) return v.slice(0, 10)
  return new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
}

async function debugLog(sb: ReturnType<typeof createClient>, action: string, status: string, data: Record<string, unknown>, err?: string) {
  try {
    await sb.from('debug_log').insert({
      source: 'fio-sync', action, component: 'fio', status,
      request_data: data, error_message: err || null,
    })
  } catch { /* ignore */ }
}

function opsRow(label: string, value: string): string {
  return `<tr><td style="padding:6px 0;color:#16a34a;font-weight:600;font-size:13px">${label}</td>
    <td style="padding:6px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px">${value}</td></tr>`
}

async function sendOpsMail(subject: string, html: string) {
  try {
    await fetch(SUPABASE_URL + '/functions/v1/send-email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
      body: JSON.stringify({ to: OPS_EMAIL, subject, raw_html: html }),
    })
  } catch (e) { console.warn('[fio-sync] ops mail failed:', (e as Error).message) }
}

type PendingRow = {
  fio_id: number; tx_date: string; amount: number; currency: string | null;
  vs: string | null; counter_account: string | null; counter_bank: string | null;
  counter_name: string | null; message: string | null; tx_type: string | null;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const sb = createClient(SUPABASE_URL, SERVICE_KEY)

  // ── Auth: service key / service_role claim / klíč z app_settings / admin JWT ──
  let bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (bearer.length > 1 && bearer.startsWith('"') && bearer.endsWith('"')) bearer = bearer.slice(1, -1)
  const svcMatch = bearer.length > 0 && bearer === SERVICE_KEY
  const roleMatch = !svcMatch && isServiceRole(bearer)
  let appMatch = false
  if (!svcMatch && !roleMatch && bearer.length > 0) {
    const { data: row } = await sb.from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
    appMatch = !!row && bearer === String((row as { value: unknown }).value ?? '').replace(/^"|"$/g, '')
  }
  let adminMatch = false
  if (!svcMatch && !roleMatch && !appMatch && bearer.length > 0) {
    try {
      const caller = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
        global: { headers: { Authorization: `Bearer ${bearer}` } },
      })
      const { data: isAdmin } = await caller.rpc('is_admin')
      adminMatch = isAdmin === true
    } catch (_) { /* ne */ }
  }
  if (!svcMatch && !roleMatch && !appMatch && !adminMatch) return json({ success: false, error: 'forbidden' }, 403)

  if (!FIO_TOKEN) {
    await debugLog(sb, 'missing_fio_token', 'warning', {})
    return json({ success: false, error: 'missing_fio_token' })
  }

  try {
    // ── 1) Stáhni nové pohyby od posledního stažení (Fio si posouvá zarážku) ──
    const resp = await fetch(`${FIO_BASE}/last/${FIO_TOKEN}/transactions.json`)
    if (resp.status === 409) {
      // Dotaz dřív než 30 s po předchozím — příští cron tick to dožene.
      return json({ success: true, skipped: 'rate_limited' })
    }
    if (!resp.ok) {
      const body = await resp.text().catch(() => '')
      await debugLog(sb, 'fio_fetch_failed', 'error', { http_status: resp.status }, body.slice(0, 500))
      return json({ success: false, error: `fio_http_${resp.status}` })
    }
    const payload = await resp.json().catch(() => null)
    const txs: FioTx[] = payload?.accountStatement?.transactionList?.transaction || []

    // ── 2) Idempotentní zápis do fio_transactions (PK fio_id; duplicity skip) ──
    if (txs.length > 0) {
      const rows = txs.map((tx) => {
        const amount = colNum(tx, 'column1')
        return {
          fio_id: colNum(tx, 'column22'),
          tx_date: txDate(tx),
          amount,
          currency: colStr(tx, 'column14'),
          vs: colStr(tx, 'column5'),
          counter_account: colStr(tx, 'column2'),
          counter_bank: colStr(tx, 'column3'),
          counter_name: colStr(tx, 'column10'),
          message: colStr(tx, 'column16'),
          tx_type: colStr(tx, 'column8'),
          status: amount > 0 ? 'new' : 'outgoing',
        }
      }).filter((r) => r.fio_id > 0)
      if (rows.length > 0) {
        const { error: insErr } = await sb.from('fio_transactions')
          .upsert(rows, { onConflict: 'fio_id', ignoreDuplicates: true })
        if (insErr) {
          await debugLog(sb, 'fio_tx_insert_failed', 'error', { count: rows.length }, insErr.message)
          return json({ success: false, error: 'insert_failed' })
        }
      }
    }

    // ── 3) Zpracuj VŠECHNY nezpracované příchozí platby (i z dřívějšího běhu,
    //       kdyby předchozí invokace spadla uprostřed — crash-safe re-scan). ──
    const { data: pending } = await sb.from('fio_transactions')
      .select('fio_id, tx_date, amount, currency, vs, counter_account, counter_bank, counter_name, message, tx_type')
      .eq('status', 'new').order('fio_id', { ascending: true }).limit(50)

    const summary = { fetched: txs.length, confirmed: 0, surcharge: 0, no_match: 0, mismatch: 0, review: 0, errors: 0 }

    for (const p of (pending || []) as PendingRow[]) {
      const finish = async (status: string, bookingId: string | null, note: string | null) => {
        await sb.from('fio_transactions')
          .update({ status, booking_id: bookingId, note, processed_at: new Date().toISOString() })
          .eq('fio_id', p.fio_id)
      }
      try {
        const vsDigits = String(p.vs || '').replace(/\D/g, '')
        const txRef = 'FIO ' + p.fio_id

        if ((p.currency || 'CZK') !== 'CZK') {
          await finish('no_match', null, 'cizí měna ' + p.currency)
          summary.no_match++
          await notifyUnmatched(p, 'Platba v cizí měně (' + p.currency + ') — spárujte a potvrďte ručně ve Velíně.')
          continue
        }

        // ── Match 1: celá platba rezervace (bookings.payment_vs) ──
        let booking: Record<string, unknown> | null = null
        if (vsDigits) {
          const { data } = await sb.from('bookings')
            .select('id, status, payment_status, total_price, booking_source, user_id, moto_id, start_date, end_date, docs_completed_at, motorcycles!moto_id(model, manual_url), profiles(full_name, email)')
            .eq('payment_vs', vsDigits).maybeSingle()
          booking = data as Record<string, unknown> | null
        }

        // ── Match 2: doplatek za úpravu (bookings.mod_surcharge_vs) ──
        if (!booking && vsDigits) {
          const { data: sur } = await sb.from('bookings')
            .select('id, mod_surcharge_due, mod_surcharge_vs')
            .eq('mod_surcharge_vs', vsDigits).maybeSingle()
          if (sur) {
            const due = Number((sur as { mod_surcharge_due: unknown }).mod_surcharge_due) || 0
            const surId = String((sur as { id: unknown }).id)
            if (due <= 0) {
              await finish('already_paid', surId, 'doplatek už potvrzen')
              continue
            }
            if (p.amount + 0.01 < due) {
              await finish('amount_mismatch', surId, `přišlo ${fmtAmount(p.amount)}, doplatek ${fmtAmount(due)} Kč`)
              summary.mismatch++
              await notifyMismatch(p, surId, due, 'doplatek za úpravu rezervace')
              continue
            }
            const { data: cs, error: csErr } = await sb.rpc('confirm_booking_surcharge', {
              p_booking_id: surId, p_method: 'bank_transfer', p_vs: vsDigits,
              p_paid_date: p.tx_date, p_transaction_ref: txRef,
            })
            if (csErr || (cs as { success?: boolean } | null)?.success === false) {
              const msg = csErr?.message || (cs as { error?: string } | null)?.error || 'rpc_failed'
              await finish('error', surId, 'confirm_booking_surcharge: ' + msg)
              summary.errors++
              await debugLog(sb, 'confirm_surcharge_failed', 'error', { fio_id: p.fio_id, booking_id: surId }, msg)
              continue
            }
            await finish('confirmed_surcharge', surId, p.amount > due + 0.01 ? `přeplatek: přišlo ${fmtAmount(p.amount)}, doplatek ${fmtAmount(due)} Kč` : null)
            summary.surcharge++
            await debugLog(sb, 'surcharge_confirmed', 'ok', { fio_id: p.fio_id, booking_id: surId, amount: p.amount, vs: vsDigits })
            await notifyConfirmed(p, surId, due, true, p.amount > due + 0.01)
            continue
          }
        }

        // ── Match 3 (fallback): VS z ručně vystavené ZF k rezervaci ──
        if (!booking && vsDigits) {
          const { data: inv } = await sb.from('invoices')
            .select('booking_id').eq('variable_symbol', vsDigits)
            .in('type', ['advance', 'proforma']).neq('status', 'cancelled')
            .not('booking_id', 'is', null)
            .order('created_at', { ascending: false }).limit(1)
          const invBookingId = inv?.[0]?.booking_id as string | undefined
          if (invBookingId) {
            const { data } = await sb.from('bookings')
              .select('id, status, payment_status, total_price, booking_source, user_id, moto_id, start_date, end_date, docs_completed_at, motorcycles!moto_id(model, manual_url), profiles(full_name, email)')
              .eq('id', invBookingId).maybeSingle()
            booking = data as Record<string, unknown> | null
          }
        }

        if (!booking) {
          await finish('no_match', null, vsDigits ? 'VS bez shody' : 'platba bez VS')
          summary.no_match++
          // Drobné příchozí položky bez VS (úroky apod.) nespamují — mail jen
          // když platba nese VS nebo je na „zákaznickou" částku.
          if (vsDigits || p.amount >= 50) {
            await notifyUnmatched(p, 'Platba se nepodařilo spárovat s žádnou rezervací — zkontrolujte a případně potvrďte/vraťte ručně.')
          }
          continue
        }

        const bId = String(booking.id)
        const expected = Number(booking.total_price) || 0

        if (booking.payment_status === 'paid') {
          await finish('already_paid', bId, 'rezervace už zaplacená')
          continue
        }
        if (!['pending', 'reserved', 'active'].includes(String(booking.status))) {
          // Např. platba po 4h auto-zrušení — revive nechává na adminovi
          // (motorka mohla být mezitím zarezervovaná jinému zákazníkovi).
          await finish('needs_review', bId, `rezervace ve stavu ${booking.status}`)
          summary.review++
          await notifyUnmatched(p, `Platba sedí na rezervaci #${bId.slice(-8).toUpperCase()}, ale ta je ve stavu „${booking.status}" (pravděpodobně platba po automatickém zrušení). Potvrďte / vraťte ručně ve Velíně.`)
          continue
        }
        if (p.amount + 0.01 < expected) {
          await finish('amount_mismatch', bId, `přišlo ${fmtAmount(p.amount)}, cena ${fmtAmount(expected)} Kč`)
          summary.mismatch++
          await notifyMismatch(p, bId, expected, 'rezervace')
          continue
        }

        // ── Potvrzení — 1:1 s ručním tlačítkem ve Velíně / Stripe webhookem ──
        await sb.from('bookings').update({ payment_reference: txRef }).eq('id', bId)

        const { data: cp, error: cpErr } = await sb.rpc('confirm_payment', { p_booking_id: bId, p_method: 'bank_transfer' })
        if (cpErr || (cp as { success?: boolean } | null)?.success === false) {
          const msg = cpErr?.message || (cp as { error?: string } | null)?.error || 'rpc_failed'
          await finish('error', bId, 'confirm_payment: ' + msg)
          summary.errors++
          await debugLog(sb, 'confirm_payment_failed', 'error', { fio_id: p.fio_id, booking_id: bId }, msg)
          continue
        }
        if ((cp as { was_already_paid?: boolean } | null)?.was_already_paid) {
          await finish('already_paid', bId, 'souběh — už potvrzeno jinou cestou')
          continue
        }
        await debugLog(sb, 'confirm_payment', 'ok', { fio_id: p.fio_id, booking_id: bId, amount: p.amount, vs: vsDigits })

        // ── ZF (pokud chybí) + DP se skutečným VS a datem úhrady — stejné
        //    doklady jako ruční potvrzení; send-booking-email je pak reuse-ne. ──
        const invoiceErrors: string[] = []
        try {
          const { data: existingInv } = await sb.from('invoices').select('id, type')
            .eq('booking_id', bId).in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
          const genInvoice = (body: Record<string, unknown>) =>
            fetch(SUPABASE_URL + '/functions/v1/generate-invoice', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
              body: JSON.stringify(body),
            }).then((r) => r.json().catch(() => ({})))
          if (!(existingInv || []).some((i: { type: string }) => i.type === 'advance' || i.type === 'proforma')) {
            const zf = await genInvoice({ type: 'advance', booking_id: bId, source: 'booking', variable_symbol: vsDigits || undefined, send_email: false })
            if (!zf?.success) invoiceErrors.push('ZF: ' + (zf?.error || 'failed'))
          }
          if (!(existingInv || []).some((i: { type: string }) => i.type === 'payment_receipt')) {
            const dp = await genInvoice({ type: 'payment_receipt', booking_id: bId, variable_symbol: vsDigits || undefined, invoice_date: p.tx_date, send_email: false })
            if (!dp?.success) invoiceErrors.push('DP: ' + (dp?.error || 'failed'))
          }
        } catch (e) { invoiceErrors.push((e as Error).message) }
        if (invoiceErrors.length > 0) {
          await debugLog(sb, 'invoice_generation_failed', 'warning', { fio_id: p.fio_id, booking_id: bId }, invoiceErrors.join('; '))
        }

        // ── Potvrzovací mail — stejné rozhodnutí jako webhook / ruční flow:
        //    web + nedokončené doklady → invoice_payment_receipt (ZF+DP + výzva
        //    doplnit údaje), jinak kompletní booking_reserved. ──
        const profile = (booking.profiles ?? null) as { full_name?: string; email?: string } | null
        const moto = (booking.motorcycles ?? null) as { model?: string; manual_url?: string } | null
        const source = String(booking.booking_source || 'app')
        if (profile?.email) {
          let mailType = 'booking_reserved'
          if (source === 'web') {
            let docsOk = !!booking.docs_completed_at
            if (!docsOk) {
              try {
                const { data: ds } = await sb.rpc('check_booking_docs_status', {
                  p_user_id: booking.user_id,
                  p_end_date: String(booking.end_date || '').slice(0, 10),
                  p_moto_id: booking.moto_id,
                })
                docsOk = (ds === null || ds === undefined)
              } catch { docsOk = false }
            }
            mailType = docsOk ? 'booking_reserved' : 'invoice_payment_receipt'
          }
          try {
            const mr = await fetch(SUPABASE_URL + '/functions/v1/send-booking-email', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
              body: JSON.stringify({
                type: mailType, booking_id: bId,
                customer_email: profile.email, customer_name: profile.full_name || '',
                motorcycle: moto?.model || '', start_date: booking.start_date, end_date: booking.end_date,
                total_price: booking.total_price, source, manual_url: moto?.manual_url || '',
              }),
            })
            if (!mr.ok) await debugLog(sb, 'confirmation_mail_http_error', 'error', { fio_id: p.fio_id, booking_id: bId, http_status: mr.status })
          } catch (e) {
            await debugLog(sb, 'confirmation_mail_failed', 'error', { fio_id: p.fio_id, booking_id: bId }, (e as Error).message)
          }
        }

        // ── In-app zpráva (parita se sendBookingMessage ve Velíně) ──
        try {
          const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
          const newStatus = String(booking.start_date || '').slice(0, 10) <= today ? 'active' : 'reserved'
          const fmtCs = (s: unknown) => s ? new Date(String(s)).toLocaleDateString('cs-CZ') : ''
          const msg = newStatus === 'active'
            ? `Motorka ${moto?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`
            : `Vaše rezervace motorky ${moto?.model || ''} (${fmtCs(booking.start_date)} – ${fmtCs(booking.end_date)}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`
          const userId = String(booking.user_id || '')
          if (userId) {
            let { data: thread } = await sb.from('message_threads').select('id').eq('customer_id', userId).limit(1).maybeSingle()
            if (!thread) {
              const { data: nt } = await sb.from('message_threads')
                .insert({ customer_id: userId, subject: 'Rezervace', channel: 'app' }).select('id').maybeSingle()
              thread = nt
            }
            if (thread) {
              await sb.from('messages').insert({ thread_id: (thread as { id: string }).id, direction: 'admin', sender_name: 'MotoGo', content: msg })
              await sb.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', (thread as { id: string }).id)
            }
          }
        } catch { /* best-effort */ }

        // ── Audit (správné sloupce admin_audit_log — new_data, žádný `details`) ──
        try {
          await sb.from('admin_audit_log').insert({
            admin_id: null, action: 'booking_payment_confirmed_fio',
            entity_type: 'booking', entity_id: bId,
            new_data: { fio_id: p.fio_id, amount: p.amount, vs: vsDigits, paid_date: p.tx_date, method: 'bank_transfer' },
          })
        } catch { /* ignore */ }

        const overpay = p.amount > expected + 0.01
        await finish('confirmed_booking', bId, overpay ? `přeplatek: přišlo ${fmtAmount(p.amount)}, cena ${fmtAmount(expected)} Kč` : null)
        summary.confirmed++
        await notifyConfirmed(p, bId, expected, false, overpay)
      } catch (e) {
        summary.errors++
        await debugLog(sb, 'tx_processing_failed', 'error', { fio_id: p.fio_id }, (e as Error).message)
        try {
          await sb.from('fio_transactions')
            .update({ status: 'error', note: (e as Error).message.slice(0, 500), processed_at: new Date().toISOString() })
            .eq('fio_id', p.fio_id)
        } catch { /* ignore */ }
      }
    }

    return json({ success: true, ...summary })
  } catch (err) {
    console.error('[fio-sync] error:', err)
    await debugLog(sb, 'sync_failed', 'error', {}, (err as Error).message)
    return json({ success: false, error: (err as Error).message }, 500)
  }
})

// ── Ops maily (info@motogo24.cz) — stejný vizuální styl jako qr-payment ──

function txTable(p: PendingRow, extra: Array<[string, string]> = []): string {
  return `<table style="width:100%;border-collapse:collapse;margin:0 0 12px">
    ${opsRow('Částka', fmtAmount(p.amount) + ' ' + (p.currency || 'CZK'))}
    ${opsRow('Variabilní symbol', p.vs || '—')}
    ${opsRow('Datum', p.tx_date)}
    ${opsRow('Protiúčet', (p.counter_account ? p.counter_account + '/' + (p.counter_bank || '') : '—') + (p.counter_name ? ' · ' + p.counter_name : ''))}
    ${opsRow('Zpráva', p.message || '—')}
    ${opsRow('Fio ID pohybu', String(p.fio_id))}
    ${extra.map(([l, v]) => opsRow(l, v)).join('')}
  </table>`
}

async function notifyConfirmed(p: PendingRow, bookingId: string, expected: number, isSurcharge: boolean, overpay: boolean) {
  const bn = '#' + bookingId.slice(-8).toUpperCase()
  const what = isSurcharge ? 'DOPLATEK' : 'platba'
  await sendOpsMail(
    `✅ Fio: ${what} VS ${p.vs || '—'} — ${fmtAmount(p.amount)} Kč potvrzena automaticky (rez. ${bn})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">✅ ${isSurcharge ? 'Doplatek potvrzen' : 'Platba potvrzena'} automaticky (Fio API)</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">Příchozí platba na Fio účtu byla automaticky spárována s rezervací <strong>${bn}</strong> a potvrzena stejným flow jako tlačítko „Potvrdit ${isSurcharge ? 'doplatek' : 'platbu'}" ve Velíně. Není potřeba nic dělat.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč']])}
     ${overpay ? '<p style="margin:0;color:#b45309;font-weight:700;font-size:13px">⚠️ Zákazník poslal víc, než měl — přeplatek vraťte převodem zpět.</p>' : ''}`
  )
}

async function notifyMismatch(p: PendingRow, bookingId: string, expected: number, what: string) {
  const bn = '#' + bookingId.slice(-8).toUpperCase()
  await sendOpsMail(
    `⚠️ Fio: platba VS ${p.vs || '—'} NESEDÍ částkou (${fmtAmount(p.amount)} / ${fmtAmount(expected)} Kč, rez. ${bn})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">⚠️ Platba nesedí částkou — potvrďte ručně</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">Příchozí platba se páruje VS na ${what} <strong>${bn}</strong>, ale částka je NIŽŠÍ než očekávaná — automaticky se nepotvrzuje. Zkontrolujte a potvrďte ručně ve Velíně (detail rezervace), nebo platbu vraťte.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč']])}`
  )
}

async function notifyUnmatched(p: PendingRow, reason: string) {
  await sendOpsMail(
    `🔔 Fio: nespárovaná příchozí platba ${fmtAmount(p.amount)} ${p.currency || 'CZK'} (VS ${p.vs || '—'})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">🔔 Nespárovaná příchozí platba na Fio účtu</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">${reason}</p>
     ${txTable(p)}`
  )
}
