import { useState } from 'react'
import { Link } from 'react-router-dom'
import { DetailRow } from '../../financeHelpers'
import { fmtMoney, fmtDate, fmtDateTime, shortId, FOLLOWUP } from './bankFormat'

export const REQUEST_STATUS = {
  pending: 'Čeká na platbu', paid: 'Zaplaceno', failed: 'Zaplaceno — úpravu nešlo provést (vrátit doplatek)',
  expired: 'Vypršelo', cancelled: 'Zrušeno',
}
const CHANGE_KIND = { edit: 'změna termínu', swap: 'výměna motorky', moto: 'jiná motorka', gear: 'výbava' }
const AUDIT = {
  fio_transaction_paired: 'Ručně spárováno',
  fio_transaction_ignored: 'Ignorováno',
  fio_transaction_reopened: 'Vráceno ke zpracování',
  fio_transaction_followup_acked: 'Přeplatek označen jako vrácený',
  fio_followup_acked: 'Přeplatek označen jako vrácený',
}
const TARGET_WORD = { booking: 'rezervace', surcharge: 'doplatek rezervace', order: 'objednávka', request: 'požadavek na platbu' }

const H = ({ children }) => <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2 mt-5" style={{ color: '#1a2e22' }}>{children}</h3>
const link = { color: '#2563eb', fontWeight: 800 }

/** Všechna uložená pole pohybu. */
export function MovementFields({ tx }) {
  const account = tx.counter_account ? `${tx.counter_account}${tx.counter_bank ? '/' + tx.counter_bank : ''}` : null
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-4 gap-y-3" style={{ overflowWrap: 'anywhere' }}>
      <DetailRow label="Datum" value={fmtDate(tx.tx_date)} />
      <DetailRow label="Částka" value={fmtMoney(tx.amount, tx.currency)} />
      <DetailRow label="Variabilní symbol" value={tx.vs || '—'} mono />
      <DetailRow label="Název protiúčtu" value={tx.counter_name || '—'} />
      <DetailRow label="Protiúčet" value={account || '—'} mono />
      <DetailRow label="Typ pohybu" value={tx.tx_type || '—'} />
      <div className="col-span-2 sm:col-span-3"><DetailRow label="Zpráva pro příjemce" value={tx.message || '—'} /></div>
      <DetailRow label="ID pohybu v bance" value={String(tx.fio_id)} mono />
      <DetailRow label="Uloženo" value={fmtDateTime(tx.created_at)} />
      <DetailRow label="Zpracováno" value={fmtDateTime(tx.processed_at)} />
      {tx.expected_amount != null && <DetailRow label="Očekávaná částka" value={fmtMoney(tx.expected_amount)} />}
      {Number(tx.attempts) > 0 && <DetailRow label="Pokusů o zpracování" value={String(tx.attempts)} />}
    </div>
  )
}

/** K čemu je pohyb přiřazený — odkazy do existujících obrazovek Velína. */
export function MovementTarget({ tx, targets, orderNumbers = {} }) {
  const b = targets.booking
  const o = targets.order
  const r = targets.request
  if (!tx.booking_id && !tx.order_id && !tx.request_id) return null
  return (
    <div data-bank="target">
      <H>Přiřazeno k</H>
      <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 13, color: '#1a2e22', lineHeight: 1.7, overflowWrap: 'anywhere' }}>
        {tx.booking_id && (
          <div>
            <Link to={`/rezervace/${tx.booking_id}`} style={link}>{b?.booking_kind === 'gear' ? 'Výpůjčka výbavy' : 'Rezervace'} <span className="font-mono">#{shortId(tx.booking_id)}</span> ↗</Link>
            {b && <> · {b.profiles?.full_name || 'zákazník neuveden'} · {fmtDate(b.start_date)} – {fmtDate(b.end_date)} · {fmtMoney(b.total_price)}</>}
          </div>
        )}
        {tx.order_id && (
          <div>
            <Link to="/e-shop" style={link}>Objednávka <span className="font-mono">{o?.order_number || orderNumbers[tx.order_id] || ''}</span> ↗</Link>
            {o && <> · {o.customer_name || o.customer_email || 'zákazník neuveden'} · {fmtMoney(o.total)}</>}
          </div>
        )}
        {tx.request_id && (
          <div>
            Požadavek na platbu{r ? <>: {r.kind === 'booking_change' ? `úprava rezervace${CHANGE_KIND[r.change_kind] ? ` (${CHANGE_KIND[r.change_kind]})` : ''}` : 'objednávka / poukaz'}
              {' '}· VS <span className="font-mono">{r.vs}</span> · {fmtMoney(r.amount)} · {REQUEST_STATUS[r.status] || r.status}</> : null}
          </div>
        )}
        {tx.manual_target_type && (
          <div style={{ color: '#4a6357' }}>Cíl zvolila obsluha ručně ({TARGET_WORD[tx.manual_target_type] || tx.manual_target_type}){tx.manual_accept_amount ? ' — přijata nižší částka' : ''}.</div>
        )}
      </div>
    </div>
  )
}

/** Rozhodnutí automatu, poznámky obsluhy a historie zásahů (admin_audit_log). */
export function MovementHistory({ tx, history, resolver }) {
  const any = tx.note || tx.resolution_note || tx.resolved_at || tx.followup || history.length > 0
  if (!any) return null
  return (
    <div data-bank="history">
      <H>Rozhodnutí a historie</H>
      <div style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.7, overflowWrap: 'anywhere' }}>
        {tx.note && <div><b>Automat:</b> {tx.note}</div>}
        {tx.followup && <div><b>Úkol:</b> {FOLLOWUP[tx.followup] || tx.followup}{tx.followup_done_at ? ` — vyřízeno ${fmtDateTime(tx.followup_done_at)}` : ' — čeká na vyřízení'}</div>}
        {tx.resolution_note && <div><b>Poznámka obsluhy:</b> {tx.resolution_note}</div>}
        {tx.resolved_at && <div style={{ color: '#4a6357' }}>Poslední zásah obsluhy: {fmtDateTime(tx.resolved_at)}{resolver ? ` · ${resolver}` : ''}</div>}
      </div>
      {history.length > 0 && (
        <ul className="mt-2" style={{ fontSize: 12, color: '#1a2e22', lineHeight: 1.7, overflowWrap: 'anywhere' }}>
          {history.map(h => {
            const d = h.new_data || {}
            const extra = [d.target_type ? TARGET_WORD[d.target_type] || d.target_type : null, d.accept_amount ? 'přijata nižší částka' : null, d.note || null].filter(Boolean).join(' · ')
            return <li key={h.id}><span className="font-mono">{fmtDateTime(h.created_at)}</span> · {h.admin_name} · <b>{AUDIT[h.action] || h.action}</b>{extra ? ` — ${extra}` : ''}</li>
          })}
        </ul>
      )}
    </div>
  )
}

/** Surová data pohybu z banky (sloupce column0…column27), rozbalovací. */
export function MovementRaw({ raw }) {
  const [open, setOpen] = useState(false)
  const cols = raw && typeof raw === 'object'
    ? Object.entries(raw).filter(([, v]) => v && typeof v === 'object' && v.value !== null && v.value !== undefined && v.value !== '')
      .sort((a, b) => (Number(a[0].replace(/\D/g, '')) || 0) - (Number(b[0].replace(/\D/g, '')) || 0))
    : []
  return (
    <div className="mt-5" data-bank="raw">
      <button onClick={() => setOpen(o => !o)} className="text-sm font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[36px]"
        style={{ background: 'none', border: 'none', padding: 0, color: '#1a2e22' }}>{open ? '▾' : '▸'} Surová data z banky</button>
      {open && (cols.length === 0
        ? <p className="mt-2" style={{ fontSize: 13, color: '#4a6357' }}>U tohoto pohybu nejsou surová data uložená (starší pohyb).</p>
        : (
          <div className="mt-2 p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 12, overflowWrap: 'anywhere' }}>
            {cols.map(([k, v]) => (
              <div key={k} className="flex justify-between gap-3 py-0.5" style={{ borderBottom: '1px solid #e2ece7' }}>
                <span style={{ color: '#4a6357' }}>{v.name || k}</span>
                <span className="font-mono text-right" style={{ color: '#0f1a14' }}>{String(v.value)}</span>
              </div>
            ))}
          </div>
        ))}
    </div>
  )
}
