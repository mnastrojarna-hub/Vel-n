import { TRow, TH, TD, Table } from '../../components/ui/Table'
import StatusBadge, { getDisplayStatus } from '../../components/ui/StatusBadge'

export default function BookingsTable({ bookings, navigate, fmtDateRange, dpTotals, setDeleteConfirm, selectedIds, setSelectedIds }) {
  const allSelected = bookings.length > 0 && selectedIds && bookings.every(b => selectedIds.has(b.id))
  const toggleAll = e => {
    if (!setSelectedIds) return
    const next = new Set(selectedIds)
    if (e.target.checked) bookings.forEach(b => next.add(b.id))
    else bookings.forEach(b => next.delete(b.id))
    setSelectedIds(next)
  }
  const toggleOne = (id, checked) => {
    if (!setSelectedIds) return
    const next = new Set(selectedIds)
    if (checked) next.add(id); else next.delete(id)
    setSelectedIds(next)
  }
  return (
    <Table>
      <thead>
        <TRow header>
          {selectedIds && (
            <TH>
              <input type="checkbox" checked={allSelected} onChange={toggleAll}
                className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }} />
            </TH>
          )}
          <TH>ID</TH><TH>Zákazník</TH><TH>Motorka</TH>
          <TH>Od</TH><TH>Do</TH><TH>Dní</TH><TH>Částka</TH><TH>Platba</TH><TH>Stav</TH><TH>Vytvořeno</TH><TH>Akce</TH>
        </TRow>
      </thead>
      <tbody>
        {bookings.map(b => {
          const toLocalDate = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
          const _nm = d => { const dt = new Date(d); dt.setHours(0,0,0,0); return dt }
          const days = b.start_date && b.end_date ? Math.max(1, Math.round((_nm(b.end_date) - _nm(b.start_date)) / 86400000) + 1) : '—'
          const hasDateChange = b.original_start_date && b.original_end_date &&
            (toLocalDate(b.start_date) !== toLocalDate(b.original_start_date) || toLocalDate(b.end_date) !== toLocalDate(b.original_end_date))
          const origDays = hasDateChange ? Math.max(1, Math.round((_nm(b.original_end_date) - _nm(b.original_start_date)) / 86400000) + 1) : null
          const daysDelta = origDays !== null && typeof days === 'number' ? days - origDays : null
          const isSelected = selectedIds?.has(b.id)
          const rowBg = isSelected ? '#fef9c3'
            : b.booking_source === 'web' ? '#eff6ff'
            : b.booking_source === 'app' ? '#f0fff0' : undefined
          return (
            <tr key={b.id} onClick={() => navigate(`/rezervace/${b.id}`)}
              className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
              style={{ borderBottom: '1px solid #d4e8e0', background: rowBg }}>
              {selectedIds && (
                <TD>
                  <input type="checkbox" checked={!!isSelected}
                    onClick={e => e.stopPropagation()}
                    onChange={e => toggleOne(b.id, e.target.checked)}
                    className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }} />
                </TD>
              )}
              <TD mono>{b.id?.slice(-8).toUpperCase()}</TD>
              <TD bold>{b.customer_name || b.profiles?.full_name || '—'}{b.booking_source === 'web' ? <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#dbeafe', color: '#2563eb' }}>WEB</span> : b.booking_source === 'app' ? <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#dcfce7', color: '#16a34a' }}>APP</span> : null}{b.created_via_ai ? <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#fef3c7', color: '#92400e' }} title="Vytvořeno přes AI asistenta">🤖 AI</span> : null}</TD>
              <TD>{b.motorcycles?.model || '—'} <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span></TD>
              <TD>{fmtDateRange(b.start_date)}</TD>
              <TD>{fmtDateRange(b.end_date)}</TD>
              <TD>{days}{hasDateChange && daysDelta !== 0 && (() => {
                const lbl = daysDelta > 0 ? `+${daysDelta}d` : `${daysDelta}d`
                const lbg = daysDelta > 0 ? '#dbeafe' : '#fee2e2'
                const lcol = daysDelta > 0 ? '#2563eb' : '#dc2626'
                return <span className="ml-1 text-[9px] font-extrabold px-1 py-0.5 rounded-btn" style={{ background: lbg, color: lcol }}>{lbl}</span>
              })()}</TD>
              <TD bold>{(dpTotals[b.id] || b.total_price) ? `${Number(dpTotals[b.id] || b.total_price).toLocaleString('cs-CZ')} Kč` : '—'}</TD>
              <TD>
                {(() => {
                  const isPaid = b.payment_status === 'paid' && b.status !== 'pending'
                  return (
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{ padding: '3px 8px', background: isPaid ? '#dcfce7' : '#fee2e2', color: isPaid ? '#1a8a18' : '#dc2626' }}>
                      {isPaid ? 'Zaplaceno' : 'Nezaplaceno'}
                    </span>
                  )
                })()}
              </TD>
              <TD>
                <StatusBadge status={getDisplayStatus(b)} />
                {b.sos_replacement && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#dcfce7', color: '#1a8a18' }}>SOS</span>}
                {b.ended_by_sos && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#fee2e2', color: '#b91c1c' }}>SOS</span>}
                {b.complaint_status && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#fef3c7', color: '#92400e' }}>RKL</span>}
              </TD>
              <TD><span className="text-sm" style={{ color: '#1a2e22' }}>{b.created_at ? new Date(b.created_at).toLocaleString('cs-CZ') : '—'}</span></TD>
              <TD>
                <button onClick={e => { e.stopPropagation(); setDeleteConfirm(b) }}
                  className="text-sm font-bold cursor-pointer"
                  style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 6px' }}>
                  Smazat
                </button>
              </TD>
            </tr>
          )
        })}
        {bookings.length === 0 && <TRow><TD>Žádné rezervace</TD></TRow>}
      </tbody>
    </Table>
  )
}
