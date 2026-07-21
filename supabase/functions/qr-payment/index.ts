// qr-payment — WEB (motogo24.cz): zvolení platby QR / bankovním převodem na kroku 2.
// Přidělí ČÍSELNÝ VS (RPC set_booking_qr_payment), vystaví ZF s číslem účtu (mBank) +
// VS + splatností 4 h, pošle zákazníkovi platební údaje (QR + účet + VS) i ZF v příloze
// a upozorní info@motogo24.cz ("zkontroluj účet, potvrď ve Velíně"). Rezervace zůstává
// pending/unpaid → admin ji ručně potvrdí (PaymentConfirmModal → confirm_payment),
// nezaplacené QR ruší cron auto_cancel_expired_pending() po 4 h. POUZE WEB, ne appka.
// verify_jwt=false (volá se anon apikey z prohlížeče); dovnitř běží service role.
//
// REŽIM SURCHARGE (2026-07-27, `{booking_id, surcharge:true}` — volá Velín po
// úpravě ZAPLACENÉ rezervace s doplatkem): částka = bookings.mod_surcharge_due
// (server-side, klient ji neposílá), VS přidělí RPC set_booking_mod_surcharge
// (stejná sekvence booking_vs_seq), NEgeneruje se ZF, neběží 4h auto-cancel a
// mail jde ze sesterské šablony `booking_qr_payment_surcharge` (stejný vzhled,
// text sedí na doplatek). Potvrzení pak ve Velíně přes „Potvrdit doplatek"
// (RPC confirm_booking_surcharge → teprve pak odejde booking_modified mail).
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const OPS_EMAIL = 'info@motogo24.cz'

// Fallback pro účet 670100-2225851630/6210 (mBank). Přebije company_info.{bank_iban,bank_account,bank_name}.
const IBAN_FALLBACK = 'CZ3962106701002225851630'
const ACCOUNT_FALLBACK = '670100-2225851630/6210'
const BANK_FALLBACK = 'mBank'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const fmtAmount = (n: number) => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2)
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

// SPD (Short Payment Descriptor) — česká QR Platba. ACC = IBAN, X-VS = jen číslice (max 10).
function buildSpd(iban: string, amount: number, vs: string, msg: string): string {
  const parts = ['SPD*1.0', 'ACC:' + iban.replace(/\s+/g, ''), 'AM:' + fmtAmount(amount), 'CC:CZK']
  const num = String(vs || '').replace(/\D/g, '').slice(0, 10)
  if (num) parts.push('X-VS:' + num)
  if (msg) parts.push('MSG:' + msg.slice(0, 60))
  return parts.join('*')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const { booking_id, locale, surcharge } = await req.json().catch(() => ({}))
    if (!booking_id) return json({ success: false, error: 'missing_booking_id' }, 400)
    const sb = createClient(SUPABASE_URL, SERVICE_KEY)

    // 1) Rezervace. Základní režim = jen web + nezaplacená (celá platba rezervace).
    //    Režim surcharge = doplatek za úpravu (rezervace je naopak už zaplacená;
    //    zdroj web i app — bankovní převod funguje pro oba). Sloupce doplatku se
    //    tu záměrně NEselectují (guard + částka jde z RPC) — select tak nespadne,
    //    dokud migrace 20260727 neproběhne, a základní web flow zůstane netknutý.
    const { data: bk } = await sb.from('bookings')
      .select('id, booking_source, payment_status, total_price, profiles(full_name, email)')
      .eq('id', booking_id).maybeSingle()
    if (!bk) return json({ success: false, error: 'not_found' }, 404)
    if (!surcharge) {
      if (bk.booking_source !== 'web') return json({ success: false, error: 'not_web_booking' }, 400)
      if (bk.payment_status === 'paid') return json({ success: false, error: 'already_paid' }, 400)
    }

    // 2) Přiděl VS (idempotentní). Surcharge má vlastní VS (mod_surcharge_vs) a RPC
    //    hlídá i guard `no_surcharge_pending`; základní režim značí kanál
    //    (pay_channel='qr') + potlačí abandoned mail.
    const { data: rpc, error: rpcErr } = await sb.rpc(
      surcharge ? 'set_booking_mod_surcharge' : 'set_booking_qr_payment',
      { p_booking_id: booking_id },
    )
    if (rpcErr || !rpc || rpc.success === false) {
      return json({ success: false, error: rpc?.error || rpcErr?.message || 'rpc_failed' }, 400)
    }
    const vs = String(rpc.vs)
    const amount = Number(rpc.amount ?? (surcharge ? 0 : bk.total_price) ?? 0)

    // 3) Číslo účtu / IBAN z company_info (fallback konstanty)
    let iban = IBAN_FALLBACK, account = ACCOUNT_FALLBACK, bank = BANK_FALLBACK
    try {
      const { data: ci } = await sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
      const v: any = ci?.value || {}
      if (v.bank_iban) iban = String(v.bank_iban).replace(/\s+/g, '')
      if (v.bank_account) account = String(v.bank_account)
      if (v.bank_name) bank = String(v.bank_name)
    } catch { /* fallback */ }

    const bookingNumber = String(booking_id).slice(-8).toUpperCase()
    const spd = buildSpd(iban, amount, vs, 'MotoGo24 ' + (surcharge ? 'doplatek ' : '') + bookingNumber)
    const qrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=' + encodeURIComponent(spd)

    // 4) ZF (bank blok + VS + splatnost 4 h). Reuse existující advance ZF, ať se netvoří duplikáty.
    //    V režimu surcharge se ZF NEgeneruje (rozdílový DP vznikne až po potvrzení
    //    doplatku v odloženém booking_modified mailu — pravidlo 2026-06-11: u úprav
    //    se proforma neposílá).
    let invoiceNumber: string | null = null
    let invoicePath: string | null = null
    if (!surcharge) try {
      const { data: existing } = await sb.from('invoices')
        .select('number, pdf_path').eq('booking_id', booking_id).eq('type', 'advance')
        .neq('status', 'cancelled').order('created_at', { ascending: false }).limit(1)
      if (existing?.[0]?.pdf_path) {
        invoiceNumber = existing[0].number
        invoicePath = existing[0].pdf_path
      } else {
        const gi = await fetch(SUPABASE_URL + '/functions/v1/generate-invoice', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
          body: JSON.stringify({
            type: 'advance', booking_id, source: 'booking', language: locale || 'cs',
            variable_symbol: vs, due_note: 'do 4 hodin od vystavení',
          }),
        })
        const gj = await gi.json().catch(() => ({}))
        if (gj?.success) { invoiceNumber = gj.number; invoicePath = gj.pdf_path }
        else console.warn('[qr-payment] generate-invoice:', JSON.stringify(gj))
      }
    } catch (e) { console.warn('[qr-payment] ZF gen failed:', (e as Error).message) }

    // 5) Mail zákazníkovi s platebními údaji + ZF v příloze.
    //    Text i předmět jsou editovatelné ve Velíně (email_templates slug
    //    'booking_qr_payment') a obsah je 1:1 s mailem, který dosud chodil.
    //    Fallback na inline HTML (stejné znění), aby mail odešel i kdyby šablona
    //    chyběla nebo byla deaktivovaná.
    const custEmail = (bk as any).profiles?.email || null
    const custName = (bk as any).profiles?.full_name || ''
    if (custEmail) {
      const attachment_paths = invoicePath
        ? [{ filename: (invoiceNumber || 'zalohova-faktura') + '.pdf', path: invoicePath }]
        : []
      const subject = surcharge
        ? 'Doplatek k rezervaci #' + bookingNumber + ' — QR / bankovní převod'
        : 'Platební údaje k rezervaci #' + bookingNumber + ' — QR / bankovní převod'
      // Placeholdery pro šablonu = 1:1 znění mailu, který dosud chodil (viz
      // customerEmailHtml). `lead` a `invoice_suffix` skládají podmíněné části
      // (jméno / číslo ZF), aby text šablony zůstal 1:1 a přitom editovatelný.
      // Surcharge šablona začíná "{{lead}} <strong>#X</strong> se váže doplatek."
      // → lead = "Jméno, k úpravě vaší rezervace" / "K úpravě vaší rezervace".
      const surchargeLead = (custName ? custName + ', k' : 'K') + ' úpravě vaší rezervace'
      const tvars = {
        lead: surcharge ? surchargeLead : (custName ? custName + ', děkujeme' : 'Děkujeme'),
        booking_number: bookingNumber,
        qr_url: qrUrl,
        amount: fmtAmount(amount) + ' Kč',
        account,
        iban: iban.replace(/(.{4})/g, '$1 ').trim(),
        bank,
        vs,
        invoice_suffix: invoiceNumber ? ' (č. ' + invoiceNumber + ')' : '',
      }
      const postEmail = (payload: Record<string, unknown>) =>
        fetch(SUPABASE_URL + '/functions/v1/send-email', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
          body: JSON.stringify(payload),
        })
      let sentOk = false
      try {
        const r = await postEmail({
          to: custEmail,
          template_slug: surcharge ? 'booking_qr_payment_surcharge' : 'booking_qr_payment',
          template_vars: tvars,
          language: locale || 'cs',
          booking_id,
          attachment_paths,
        })
        const rj = await r.json().catch(() => ({}))
        sentOk = !!(rj as any)?.success
        if (!sentOk) console.warn('[qr-payment] template mail not sent:', JSON.stringify(rj))
      } catch (e) { console.warn('[qr-payment] template mail error:', (e as Error).message) }
      if (!sentOk) {
        try {
          await postEmail({
            to: custEmail,
            subject,
            raw_html: surcharge
              ? surchargeEmailHtml({ custName, amount, account, iban, bank, vs, qrUrl, bookingNumber })
              : customerEmailHtml({ custName, amount, account, iban, bank, vs, qrUrl, bookingNumber, invoiceNumber }),
            booking_id,
            attachment_paths,
          })
        } catch (e) { console.warn('[qr-payment] fallback mail failed:', (e as Error).message) }
      }
    }

    // 6) Upozornění na info@motogo24.cz
    try {
      await fetch(SUPABASE_URL + '/functions/v1/send-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
        body: JSON.stringify({
          to: OPS_EMAIL,
          subject: '🔔 ' + (surcharge ? 'DOPLATEK (úprava rezervace)' : 'QR/převod platba') + ' — VS ' + vs + ' — ' + fmtAmount(amount) + ' Kč (rez. #' + bookingNumber + ')',
          raw_html: opsEmailHtml({ custName, custEmail, amount, vs, bookingNumber, account, surcharge: !!surcharge }),
        }),
      })
    } catch (e) { console.warn('[qr-payment] ops mail failed:', (e as Error).message) }

    return json({
      success: true, vs, amount, account, iban, bank, spd, qr_url: qrUrl,
      booking_number: bookingNumber, invoice_number: invoiceNumber, due_hours: 4,
    })
  } catch (err) {
    console.error('[qr-payment] error:', err)
    return json({ success: false, error: (err as Error).message }, 500)
  }
})

function row(label: string, value: string, big = false): string {
  return `<tr>
    <td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">${label}</td>
    <td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:${big ? '18px' : '14px'};font-variant-numeric:tabular-nums">${value}</td>
  </tr>`
}

// Fallback HTML — 1:1 se šablonou email_templates('booking_qr_payment') i s
// mailem, který dosud chodil. Použije se, jen když šablona chybí/je vypnutá.
function customerEmailHtml(p: {
  custName: string; amount: number; account: string; iban: string; bank: string;
  vs: string; qrUrl: string; bookingNumber: string; invoiceNumber: string | null
}): string {
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Platební údaje — QR / bankovní převod</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${p.custName ? p.custName + ', d' : 'D'}ěkujeme za rezervaci <strong>#${p.bookingNumber}</strong>. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.</p>
  <div style="text-align:center;margin:0 0 16px"><img src="${p.qrUrl}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>
  <table style="width:100%;border-collapse:collapse;margin:0 0 14px">
    ${row('Částka', fmtAmount(p.amount) + ' Kč', true)}
    ${row('Číslo účtu', p.account)}
    ${row('IBAN', p.iban.replace(/(.{4})/g, '$1 ').trim())}
    ${row('Banka', p.bank)}
    ${row('Variabilní symbol', p.vs)}
  </table>
  <p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">⏱ Platbu prosím proveďte do 4 hodin. Pokud se do té doby nepřipíše, rezervace se automaticky zruší a termín se uvolní.</p>
  <p style="margin:0 0 6px;color:#374151;font-size:13px">Po připsání platby vám rezervaci potvrdíme a pošleme potvrzení s přístupovými údaji. Zálohovou fakturu najdete v příloze.${p.invoiceNumber ? ' (č. ' + p.invoiceNumber + ')' : ''}</p>
  <p style="margin:0;color:#6b7280;font-size:12px">Platíte-li raději kartou (okamžité potvrzení), můžete rezervaci dokončit online platbou v rezervačním formuláři.</p>
  `
}

// Fallback HTML pro DOPLATEK za úpravu rezervace — bez 4h splatnosti a bez ZF
// (rezervace je zaplacená, nic se automaticky neruší; doklad přijde po potvrzení).
function surchargeEmailHtml(p: {
  custName: string; amount: number; account: string; iban: string; bank: string;
  vs: string; qrUrl: string; bookingNumber: string
}): string {
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Doplatek za úpravu rezervace — QR / bankovní převod</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${p.custName ? p.custName + ', k' : 'K'} úpravě vaší rezervace <strong>#${p.bookingNumber}</strong> se váže doplatek. Uhraďte ho prosím bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.</p>
  <div style="text-align:center;margin:0 0 16px"><img src="${p.qrUrl}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>
  <table style="width:100%;border-collapse:collapse;margin:0 0 14px">
    ${row('Částka', fmtAmount(p.amount) + ' Kč', true)}
    ${row('Číslo účtu', p.account)}
    ${row('IBAN', p.iban.replace(/(.{4})/g, '$1 ').trim())}
    ${row('Banka', p.bank)}
    ${row('Variabilní symbol', p.vs)}
  </table>
  <p style="margin:0;color:#374151;font-size:13px">Po připsání platby vám úpravu rezervace potvrdíme e-mailem spolu s dokladem o platbě a aktualizovanou smlouvou.</p>
  `
}

function opsEmailHtml(p: {
  custName: string; custEmail: string | null; amount: number; vs: string; bookingNumber: string; account: string; surcharge?: boolean
}): string {
  return `
  <h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">🔔 ${p.surcharge ? 'Čeká na DOPLATEK za úpravu rezervace' : 'Čeká na bankovní převod'}</h2>
  <p style="margin:0 0 12px;color:#374151;font-size:14px">${p.surcharge
    ? 'Admin upravil zaplacenou rezervaci s doplatkem. Zkontrolujte prosím připsání na účtu a po přijetí doplatek potvrďte ve Velíně (detail rezervace → Potvrdit doplatek) — teprve pak zákazníkovi odejde potvrzení úpravy.'
    : 'Zákazník zvolil platbu QR / převodem. Zkontrolujte prosím připsání na účtu a po přijetí platbu potvrďte ve Velíně (rezervace → Potvrdit platbu → Bankovní převod).'}</p>
  <table style="width:100%;border-collapse:collapse;margin:0 0 12px">
    ${row('Rezervace', '#' + p.bookingNumber)}
    ${row('Zákazník', (p.custName || '—') + (p.custEmail ? ' · ' + p.custEmail : ''))}
    ${row('Variabilní symbol', p.vs)}
    ${row('Částka', fmtAmount(p.amount) + ' Kč', true)}
    ${row('Účet', p.account)}
  </table>
  ${p.surcharge
    ? '<p style="margin:0;color:#374151;font-weight:700;font-size:13px">Rezervace je jinak zaplacená — nic se automaticky neruší.</p>'
    : '<p style="margin:0;color:#b91c1c;font-weight:700;font-size:13px">Splatnost 4 h. Nezaplacená rezervace se pak automaticky zruší. Případnou pozdní/duplicitní platbu vraťte převodem zpět.</p>'}
  `
}
