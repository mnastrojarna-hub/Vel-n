// Zprávy → Hodnocení: sdílené prvky pro desktop (RatingsTab) i mobil (RatingsCards).
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { RATING_FILTERS, fmtDateTime } from './ratingsData'

export const LOW_BG = '#fef2f2'
export const LOW_BORDER = '#dc2626'
const STAR_ON = '#f59e0b'
const STAR_OFF = '#d1d5db'

export function Stars({ value, size = 16 }) {
  return (
    <span aria-label={`${value} z 5 hvězdiček`} title={`${value}/5`} style={{ whiteSpace: 'nowrap', fontSize: size, lineHeight: 1, letterSpacing: 1 }}>
      {[1, 2, 3, 4, 5].map(i => <span key={i} style={{ color: i <= value ? STAR_ON : STAR_OFF }}>★</span>)}
    </span>
  )
}

const pill = (bg, color) => ({ display: 'inline-block', padding: '2px 8px', borderRadius: 6, background: bg, color, fontSize: 11, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.03em', whiteSpace: 'nowrap' })

const HANDLED_LABEL = { manual: 'označeno ručně', reply: 'odpověď v chatu', closed: 'konverzace uzavřena' }

export function StatusPill({ row }) {
  if (row.handled) {
    const when = row.handled.at ? ` · ${fmtDateTime(row.handled.at)}` : ''
    return <span style={pill('#dcfce7', '#1a8a18')} title={`Vyřízeno — ${HANDLED_LABEL[row.handled.kind]}${when}`}>✓ Vyřízeno</span>
  }
  if (row.low) return <span style={pill('#fee2e2', '#b91c1c')}>K vyřízení</span>
  if (row.unread.length) return <span style={pill('#e8fee7', '#1a2e22')}>Nový komentář</span>
  return <span style={{ color: '#6b7a72', fontSize: 13 }}>—</span>
}

export function LowBadge() {
  return <span style={pill(LOW_BORDER, '#fff')} title="Hodnocení 1–3 hvězdičky — vyřiďte a ozvěte se zákazníkovi">Nízké</span>
}

// Text „co máme zlepšit“ = zprávy zákazníka z vlákna rezervace; nepřečtené zvýrazněné.
export function Comments({ row, clamp = 3 }) {
  const [open, setOpen] = useState(false)
  if (!row.comments.length) return <span style={{ color: '#6b7a72', fontSize: 13 }}>bez komentáře</span>
  const list = open ? row.comments : row.comments.slice(-1)
  const hidden = row.comments.length - list.length
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      {list.map(m => (
        <div key={m.id} style={{ fontSize: 13, color: '#0f1a14', minWidth: 0 }}>
          <div style={{
            whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', fontWeight: m.read_at ? 500 : 700,
            ...(open ? {} : { display: '-webkit-box', WebkitLineClamp: clamp, WebkitBoxOrient: 'vertical', overflow: 'hidden' }),
          }}>
            {!m.read_at && <span title="Nepřečteno" style={{ display: 'inline-block', width: 8, height: 8, borderRadius: 4, background: '#74FB71', marginRight: 6, verticalAlign: 'middle' }} />}
            {m.content}
          </div>
          <div style={{ fontSize: 11, color: '#6b7a72', marginTop: 2 }}>{fmtDateTime(m.created_at)}</div>
        </div>
      ))}
      {(hidden > 0 || open || (row.comments[row.comments.length - 1]?.content || '').length > 160) && (
        <button type="button" onClick={() => setOpen(o => !o)} className="cursor-pointer text-left"
          style={{ background: 'none', border: 'none', padding: 0, color: '#2563eb', fontSize: 12, fontWeight: 700 }}>
          {open ? 'Sbalit' : hidden > 0 ? `Zobrazit vše (${row.comments.length})` : 'Zobrazit celé'}
        </button>
      )}
    </div>
  )
}

export function BookingLink({ row }) {
  return <Link to={`/rezervace/${row.id}`} style={{ color: '#2563eb', fontWeight: 800, fontFamily: 'monospace' }}>#{row.short}</Link>
}

export function CustomerLink({ booking }) {
  const name = booking.profiles?.full_name || booking.profiles?.email || 'Zákazník'
  if (!booking.user_id) return <span>{name}</span>
  return <Link to={`/zakaznici/${booking.user_id}`} style={{ color: '#2563eb', fontWeight: 700 }}>{name}</Link>
}

export function FilterChips({ value, counts, onChange, mobile = false }) {
  return (
    <div className="flex flex-wrap" style={{ gap: 6 }}>
      {RATING_FILTERS.map(f => {
        const on = value === f.key
        const alert = (f.key === 'open' || f.key === 'unread') && counts[f.key] > 0
        return (
          <button key={f.key} type="button" onClick={() => onChange(f.key)} aria-pressed={on}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap"
            style={{
              minHeight: mobile ? 40 : undefined, padding: '6px 12px', color: '#1a2e22',
              background: on ? '#e8fee7' : '#f1faf7',
              border: on ? '1px solid #74FB71' : '1px solid transparent',
              boxShadow: on ? '0 2px 8px rgba(116,251,113,.2)' : 'none',
            }}>
            {f.label}
            <span style={{ marginLeft: 6, padding: '0 6px', borderRadius: 8, fontSize: 11, background: alert ? '#dc2626' : '#d4e8e0', color: alert ? '#fff' : '#1a2e22' }}>
              {counts[f.key] ?? 0}
            </span>
          </button>
        )
      })}
    </div>
  )
}

export function SummaryBar({ summary, mode }) {
  const max = Math.max(1, ...summary.dist.slice(1))
  return (
    <div className="bg-white rounded-card shadow-card flex flex-wrap items-center" style={{ padding: '12px 16px', gap: 18, marginBottom: 12 }}>
      <div>
        <div style={{ fontSize: 26, fontWeight: 800, color: '#0f1a14', lineHeight: 1 }}>{summary.total ? summary.avg.toFixed(2).replace('.', ',') : '—'}</div>
        <div style={{ marginTop: 4 }}><Stars value={Math.round(summary.avg)} size={14} /></div>
        <div style={{ fontSize: 12, color: '#1a2e22', marginTop: 2 }}>{summary.total} hodnocení jízd</div>
      </div>
      <div style={{ display: 'grid', gap: 3, minWidth: 160, flex: '1 1 160px', maxWidth: 260 }}>
        {[5, 4, 3, 2, 1].map(n => (
          <div key={n} className="flex items-center" style={{ gap: 6, fontSize: 12, color: '#1a2e22' }}>
            <span style={{ width: 22, fontWeight: 700 }}>{n}★</span>
            <div style={{ flex: 1, height: 8, background: '#f1faf7', borderRadius: 4, overflow: 'hidden' }}>
              <div style={{ width: `${(summary.dist[n] / max) * 100}%`, height: '100%', background: n <= 3 ? '#f87171' : '#74FB71' }} />
            </div>
            <span style={{ width: 28, textAlign: 'right' }}>{summary.dist[n]}</span>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap" style={{ gap: 10 }}>
        <Kpi label="Nízká k vyřízení" value={summary.lowOpen} alert={summary.lowOpen > 0} />
        <Kpi label="Nepřečtené komentáře" value={summary.unread} alert={summary.unread > 0} />
      </div>
      <div style={{ flexBasis: '100%', fontSize: 12, color: '#1a2e22' }}>
        Komentáře „co máme zlepšit“ jsou soukromé — přicházejí do chatu zákazníka, nikdy se nezveřejňují.
        {mode !== 'db' && ' Ruční „vyřízeno“ se zatím ukládá jen v tomto prohlížeči (sdílení mezi adminy vyžaduje schválenou SQL migraci).'}
      </div>
    </div>
  )
}

function Kpi({ label, value, alert }) {
  return (
    <div className="rounded-btn" style={{ padding: '8px 12px', background: alert ? '#fee2e2' : '#f1faf7', border: `1px solid ${alert ? '#fca5a5' : '#d4e8e0'}` }}>
      <div style={{ fontSize: 20, fontWeight: 800, color: alert ? '#b91c1c' : '#0f1a14', lineHeight: 1.1 }}>{value}</div>
      <div style={{ fontSize: 11, fontWeight: 800, textTransform: 'uppercase', color: '#1a2e22' }}>{label}</div>
    </div>
  )
}
