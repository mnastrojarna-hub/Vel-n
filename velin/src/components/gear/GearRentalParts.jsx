import { useState, useEffect } from 'react'
import { TRow, TD } from '../ui/Table'
import { RENTAL_STATUS, PAYMENT, INPUT, czk, daysLabel, fmtDate, Pill } from './gearShared'

// Řádek (desktop) a karta (telefon) jedné výpůjčky + editory stavu a interní poznámky.

function sizeText(sizes, key) {
  const v = sizes && typeof sizes === 'object' ? sizes[key] : null
  return v ? ` ${v}` : ''
}

export function ItemsList({ lines, prices }) {
  const labelOf = k => prices.find(p => p.key === k)?.label || k
  const list = Array.isArray(lines) ? lines : []
  if (!list.length) return <span style={{ color: '#6b7a72' }}>—</span>
  return (
    <div className="space-y-0.5">
      {list.map((l, i) => {
        const sizes = l.sizes || {}
        const detail = l.kind === 'set'
          ? Object.keys(sizes).map(k => `${String(labelOf(k)).toLowerCase()}${sizeText(sizes, k)}`).join(', ')
          : ''
        return (
          <div key={`${l.key}-${i}`} className="text-sm" style={{ color: '#0f1a14' }}>
            <strong>{l.kind === 'set' ? l.label : `${l.label}${sizeText(sizes, l.key)}`}</strong>
            {detail && <span> ({detail})</span>}
            <span className="text-xs" style={{ color: '#6b7a72' }}> · {czk(l.price_per_day)}/den</span>
          </div>
        )
      })}
    </div>
  )
}

export function StatusSelect({ value, disabled, onChange }) {
  const s = RENTAL_STATUS[value] || RENTAL_STATUS.reserved
  return (
    <select value={value} disabled={disabled} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold cursor-pointer outline-none max-lg:min-h-[40px]"
      style={{ padding: '5px 8px', background: s.bg, color: s.color, border: `1px solid ${s.bg}`, opacity: disabled ? 0.5 : 1 }}>
      {Object.entries(RENTAL_STATUS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
    </select>
  )
}

export function NoteEditor({ value, disabled, onSave }) {
  const [text, setText] = useState(value || '')
  useEffect(() => { setText(value || '') }, [value])
  const dirty = (text || '').trim() !== (value || '').trim()
  return (
    <div className="flex gap-1 items-start">
      <input value={text} disabled={disabled} onChange={e => setText(e.target.value)} placeholder="Interní poznámka…"
        onKeyDown={e => { if (e.key === 'Enter' && dirty) onSave(text) }}
        className="max-lg:min-h-[40px]" style={{ ...INPUT, fontSize: 13, padding: '5px 8px', flex: 1, minWidth: 0, width: '100%' }} />
      {dirty && (
        <button type="button" disabled={disabled} onClick={() => onSave(text)}
          className="rounded-btn text-xs font-extrabold cursor-pointer border-none shrink-0 max-lg:min-h-[40px]"
          style={{ padding: '6px 10px', background: '#1a2e22', color: '#74FB71' }}>Uložit</button>
      )}
    </div>
  )
}

function timing(r, today) {
  if (r.status === 'cancelled' || r.status === 'returned') return null
  if (r.start_date === today) return { label: 'Začíná dnes', color: '#b45309', bg: '#fef3c7' }
  if (r.start_date < today && r.end_date >= today) return { label: 'Probíhá', color: '#2563eb', bg: '#dbeafe' }
  if (r.end_date === today) return { label: 'Končí dnes', color: '#b45309', bg: '#fef3c7' }
  return null
}

function Term({ r, today }) {
  const t = timing(r, today)
  return (
    <div>
      <div className="font-bold whitespace-nowrap">{fmtDate(r.start_date)} – {fmtDate(r.end_date)}</div>
      <div className="text-xs" style={{ color: '#6b7a72' }}>
        {r.days} {daysLabel(r.days)}{r.pickup_time ? ` · vyzvednutí ${String(r.pickup_time).slice(0, 5)}` : ''}
      </div>
      {t && <div className="mt-1"><Pill {...t} /></div>}
    </div>
  )
}

function Customer({ o }) {
  if (!o) return <span style={{ color: '#dc2626' }}>objednávka nenalezena</span>
  return (
    <div style={{ overflowWrap: 'anywhere' }}>
      <div className="font-bold">{o.customer_name || '—'}</div>
      {o.customer_email && <a href={`mailto:${o.customer_email}`} className="block text-xs" style={{ color: '#1a2e22' }}>{o.customer_email}</a>}
      {o.customer_phone && <a href={`tel:${o.customer_phone}`} className="block text-xs" style={{ color: '#1a2e22' }}>{o.customer_phone}</a>}
    </div>
  )
}

function Payment({ o }) {
  const p = PAYMENT[o?.payment_status] || { label: o?.payment_status || '—', color: '#1a2e22', bg: '#f3f4f6' }
  return (
    <div>
      <div className="font-extrabold whitespace-nowrap">{czk(o?.total)}</div>
      <div className="mt-1"><Pill {...p} /></div>
      {o?.order_number && <div className="text-xs font-mono mt-1" style={{ color: '#6b7a72' }}>{o.order_number}</div>}
    </div>
  )
}

const unpaidStyle = o => (o?.payment_status === 'paid' ? {} : { opacity: 0.55 })

export function RentalRow({ r, prices, today, busy, onStatus, onNote }) {
  return (
    <TRow>
      <TD style={unpaidStyle(r.order)}><Term r={r} today={today} /></TD>
      <TD style={unpaidStyle(r.order)}>{r.branch?.name || '—'}</TD>
      <TD style={unpaidStyle(r.order)}><Customer o={r.order} /></TD>
      <TD style={{ ...unpaidStyle(r.order), maxWidth: 340 }}>
        <ItemsList lines={r.lines} prices={prices} />
        {r.note && <div className="text-xs mt-1" style={{ color: '#b45309' }}>💬 {r.note}</div>}
      </TD>
      <TD><Payment o={r.order} /></TD>
      <TD><StatusSelect value={r.status} disabled={busy} onChange={v => onStatus(r, v)} /></TD>
      <TD style={{ minWidth: 200 }}><NoteEditor value={r.admin_note} disabled={busy} onSave={t => onNote(r, t)} /></TD>
    </TRow>
  )
}

export function RentalCard({ r, prices, today, busy, onStatus, onNote }) {
  return (
    <div className="bg-white rounded-card shadow-card" style={{ padding: 12 }}>
      <div style={unpaidStyle(r.order)}>
        <div className="flex items-start justify-between gap-2">
          <Term r={r} today={today} />
          <div className="text-right shrink-0"><Payment o={r.order} /></div>
        </div>
        <div className="text-sm mt-2" style={{ color: '#1a2e22' }}>📍 {r.branch?.name || '—'}</div>
        <div className="text-sm mt-2"><Customer o={r.order} /></div>
        <div className="mt-2"><ItemsList lines={r.lines} prices={prices} /></div>
        {r.note && <div className="text-sm mt-1" style={{ color: '#b45309' }}>💬 {r.note}</div>}
      </div>
      <div className="flex flex-col gap-2 mt-3">
        <StatusSelect value={r.status} disabled={busy} onChange={v => onStatus(r, v)} />
        <NoteEditor value={r.admin_note} disabled={busy} onSave={t => onNote(r, t)} />
      </div>
    </div>
  )
}
