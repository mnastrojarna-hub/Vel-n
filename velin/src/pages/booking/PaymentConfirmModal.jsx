import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { generateInvoiceNumber } from '../../lib/invoiceUtils'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { MANUAL_PAYMENT_METHODS } from './bookingConstants'

/**
 * Ruční potvrzení platby ve Velínu (QR kód, převod, hotově, krypto…).
 * Po potvrzení projde STEJNÉ flow jako Stripe (confirm_payment + booking_reserved mail),
 * jen platební údaje (způsob, VS, datum úhrady, č. transakce) se doplní ručně a zapíšou
 * do rezervace i do DP / faktur.
 *
 * Pokud k rezervaci existují vystavené zálohové faktury (ZF), nabídne jejich výběr,
 * aby se platba + DP navázaly na konkrétní ZF (spárování dokladů a VS).
 */
/**
 * Režim `surcharge` (2026-07-27): potvrzuje se JEN doplatek za úpravu už zaplacené
 * rezervace (bookings.mod_surcharge_due) — bez párování na ZF (u úprav se ZF
 * nevystavuje), VS se předvyplní z bookings.mod_surcharge_vs (VS z QR výzvy).
 * Po potvrzení odejde odložený booking_modified mail (confirm_booking_surcharge).
 */
export default function PaymentConfirmModal({ open, onClose, onConfirm, saving, error, total, bookingId, payChannel, paymentVs, surcharge = false, surchargeVs = null }) {
  const today = new Date().toISOString().slice(0, 10)
  const [method, setMethod] = useState('bank_transfer')
  const [vs, setVs] = useState('')
  const [paidDate, setPaidDate] = useState(today)
  const [txRef, setTxRef] = useState('')
  const [advances, setAdvances] = useState([])
  const [advanceId, setAdvanceId] = useState('')
  // Skutečný VS, kterým zákazník platil QR / převodem (bookings.payment_vs). Je to
  // ZDROJ PRAVDY — QR kód i ZF nesou právě tento číselný VS. Když existuje, VŽDY
  // přebije fakturní VS/číslo (i při ruční změně ZF v selectu), ať se platba spáruje.
  const [qrVs, setQrVs] = useState('')

  // Načti vystavené ZF (zálohové / proforma) k rezervaci při otevření + skutečný VS
  // QR platby. Priorita VS:
  //   1) QR/převod → bookings.payment_vs (číselný VS z QR kódu / ZF) — vždy správně
  //   2) existuje ZF → variable_symbol z ní (jinak její číslo)
  //   3) žádná ZF → nabídni automaticky následující číslo DP jako VS
  useEffect(() => {
    if (!open || !bookingId) return
    let active = true
    setQrVs('')
    // Doplatek za úpravu: žádné ZF párování, VS = VS doplatku z QR výzvy.
    if (surcharge) {
      setAdvances([]); setAdvanceId('')
      if (surchargeVs) { setVs(String(surchargeVs)); return }
      ;(async () => {
        try {
          const { data: bk } = await supabase.from('bookings')
            .select('mod_surcharge_vs').eq('id', bookingId).maybeSingle()
          if (active && bk?.mod_surcharge_vs) setVs(String(bk.mod_surcharge_vs))
        } catch { /* VS zůstane prázdný */ }
      })()
      return () => { active = false }
    }
    ;(async () => {
      // payment_vs se plní jen u QR/převodu; když ho parent nepředal, dočti ho z DB
      // (rezervace se potvrzuje ručně klidně hodinu po platbě → čti čerstvě).
      let channel = payChannel || null
      let vsNum = (channel === 'qr' && paymentVs) ? String(paymentVs) : ''
      if (!vsNum) {
        try {
          const { data: bk } = await supabase.from('bookings')
            .select('pay_channel, payment_vs').eq('id', bookingId).maybeSingle()
          if (bk?.pay_channel === 'qr' && bk?.payment_vs) vsNum = String(bk.payment_vs)
        } catch { /* ignore → padne na fakturní VS */ }
      }
      if (!active) return
      setQrVs(vsNum)

      const { data } = await supabase.from('invoices')
        .select('id, number, total, issue_date, variable_symbol')
        .eq('booking_id', bookingId).in('type', ['advance', 'proforma']).neq('status', 'cancelled')
        .order('issue_date', { ascending: false })
      if (!active) return
      const list = data || []
      setAdvances(list)
      if (list.length > 0) {
        // Přednostně vyber ZF, jejíž VS odpovídá skutečnému QR VS (spárování platby).
        const match = vsNum ? list.find(a => String(a.variable_symbol || '') === vsNum) : null
        const chosen = match || list[0]
        setAdvanceId(chosen.id)
        setVs(vsNum || chosen.variable_symbol || chosen.number || '')
      } else if (vsNum) {
        // QR bez vystavené ZF (např. selhala generace) → drž skutečný VS zákazníka.
        setVs(vsNum)
      } else {
        try {
          const next = await generateInvoiceNumber('payment_receipt')
          if (active && next) setVs(next.replace(/^[A-Z]+-/, ''))
        } catch { /* fallback: prázdný VS = č. dokladu */ }
      }
    })()
    return () => { active = false }
  }, [open, bookingId, payChannel, paymentVs, surcharge, surchargeVs])

  if (!open) return null

  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
  const labelCls = 'block text-sm font-extrabold uppercase tracking-wide mb-1'
  const fmtCs = d => d ? new Date(d).toLocaleDateString('cs-CZ') : ''
  const selectedAdvance = advances.find(a => a.id === advanceId) || null

  function pickAdvance(id) {
    setAdvanceId(id)
    const adv = advances.find(a => a.id === id)
    // U QR/převodu zůstává VS = skutečný VS zákazníka i po ruční změně ZF.
    if (adv) setVs(qrVs || adv.variable_symbol || adv.number || '')
  }

  function submit() {
    onConfirm({
      method,
      vs: vs.trim() || null,
      paid_date: paidDate || today,
      transaction_ref: txRef.trim() || null,
      advance_invoice_id: advanceId || null,
      advance_number: selectedAdvance?.number || null,
    })
  }

  return (
    <Modal open title={surcharge ? 'Potvrdit doplatek za úpravu' : 'Potvrdit platbu'} onClose={onClose}>
      {surcharge ? (
        <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
          Potvrzuje se <strong>pouze doplatek za úpravu</strong> — původní rezervace je už zaplacená.
          Po potvrzení zákazníkovi odejde e-mail o úpravě rezervace (booking modified) s dokladem
          o platbě a aktualizovanou smlouvou.
          {total != null && <> Částka doplatku: <strong>{Number(total).toLocaleString('cs-CZ')} Kč</strong>.</>}
        </p>
      ) : (
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Rezervace se označí jako <strong>zaplacená</strong> a přejde do stavu <strong>Nadcházející / Aktivní</strong> (dle data) —
        proběhne stejné flow jako u platby kartou (doklady, e-mail, přístupové kódy).
        {total != null && <> Částka: <strong>{Number(total).toLocaleString('cs-CZ')} Kč</strong>.</>}
      </p>
      )}

      {surcharge ? null : advances.length > 0 ? (
        <>
          <label className={labelCls} style={{ color: '#1a2e22' }}>Spárovat se zálohovou fakturou (ZF)</label>
          <select value={advanceId} onChange={e => pickAdvance(e.target.value)}
            className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}>
            {advances.map(a => (
              <option key={a.id} value={a.id}>
                {a.number} · {Number(a.total || 0).toLocaleString('cs-CZ')} Kč · {fmtCs(a.issue_date)}
              </option>
            ))}
          </select>
        </>
      ) : (
        <p className="text-[13px] mb-3 rounded-btn" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a5a52' }}>
          K rezervaci zatím není vystavená ZF — bude vytvořena nová zálohová faktura a DP se na ni naváže.
        </p>
      )}

      <label className={labelCls} style={{ color: '#1a2e22' }}>Způsob platby</label>
      <select value={method} onChange={e => setMethod(e.target.value)}
        className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}>
        {MANUAL_PAYMENT_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
      </select>

      <div className="grid grid-cols-2 gap-3 mb-3">
        <div>
          <label className={labelCls} style={{ color: '#1a2e22' }}>Variabilní symbol</label>
          <input type="text" value={vs} onChange={e => setVs(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}
            placeholder="Výchozí = č. dokladu" />
        </div>
        <div>
          <label className={labelCls} style={{ color: '#1a2e22' }}>Datum úhrady</label>
          <input type="date" value={paidDate} onChange={e => setPaidDate(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>

      <label className={labelCls} style={{ color: '#1a2e22' }}>Číslo transakce <span style={{ fontWeight: 400, textTransform: 'none' }}>(volitelné)</span></label>
      <input type="text" value={txRef} onChange={e => setTxRef(e.target.value)}
        className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}
        placeholder="Reference / ID transakce" />

      {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}

      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose} disabled={saving}>Zpět</Button>
        <Button onClick={submit} green disabled={saving || !paidDate}>
          {saving ? 'Potvrzuji…' : surcharge ? 'Potvrdit doplatek' : 'Potvrdit platbu'}
        </Button>
      </div>
    </Modal>
  )
}
