// Seznam rezervací na mobilu a tabletu (< 1024 px) — karty místo 14sloupcové tabulky
// (na tabletu tabulka schovávala vše za sloupcem Částka). Stejná data i akce jako
// BookingsTable: klik = detail, zaškrtnutí pro hromadnou správu, Storno / Smazat.
import DocsStatusPills from '../../components/DocsStatusPills'
import { bookingBranchId } from './BranchChips'
import { bookingDaysInfo, DaysDelta, SourceTags, PaymentPill, StatusTags } from './bookingsListParts'

const FS = 'text-[11px]'
const lbl = { fontSize: 11, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.03em', color: '#4a6357' }
const actBtn = { minHeight: 38, borderRadius: 8, padding: '6px 12px', fontWeight: 700, fontSize: 14, cursor: 'pointer' }

export default function BookingsListMobile({ bookings, navigate, fmtDateRange, dpTotals, scanStatus, appInstalls, setDeleteConfirm, setCancelTarget, selected, allSelected, toggleAll, toggleOne, branchName, onBulk }) {
  if (bookings.length === 0) {
    return <div className="bg-white rounded-card shadow-card text-sm" style={{ padding: '14px 16px', color: '#0f1a14' }}>Žádné rezervace</div>
  }
  return (
    <div>
      {selected && (
        // s výběrem lišta drží nahoře (hromadná správa dosažitelná i u karet níž v seznamu)
        <div className="flex items-center gap-2 mb-2 px-1" style={{ minHeight: 40, ...(selected.size > 0 ? { position: 'sticky', top: 0, zIndex: 5, background: '#dff0ec', padding: '6px 4px', boxShadow: '0 6px 10px -8px rgba(15,26,20,.25)' } : {}) }}>
          <label className="flex items-center gap-2.5 cursor-pointer" style={{ minHeight: 40 }}>
            <input type="checkbox" checked={allSelected} onChange={toggleAll}
              className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }} />
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Vybrat vše na stránce</span>
          </label>
          {selected.size > 0 && !onBulk && <span className="ml-auto text-sm font-bold" style={{ color: '#92400e' }}>Vybráno: {selected.size}</span>}
          {/* telefon: hromadná správa u výběru (v liště by zabírala místo) */}
          {selected.size > 0 && onBulk && (
            <button onClick={onBulk}
              className="ml-auto rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer leading-tight"
              style={{ minHeight: 40, padding: '6px 14px', background: '#fde68a', color: '#92400e', border: 'none' }}>
              ☰ Hromadná správa ({selected.size})
            </button>
          )}
        </div>
      )}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
        {bookings.map(b => {
          const info = bookingDaysInfo(b)
          const isSelected = selected?.has(b.id)
          const bg = isSelected ? '#fef9c3' : b.booking_source === 'web' ? '#eff6ff' : b.booking_source === 'app' ? '#f0fff0' : '#fff'
          const amount = (dpTotals[b.id] || b.total_price) ? `${Number(dpTotals[b.id] || b.total_price).toLocaleString('cs-CZ')} Kč` : '—'
          const canCancel = setCancelTarget && (b.status === 'pending' || b.status === 'reserved' || b.status === 'active')
          return (
            <div key={b.id} onClick={() => navigate(`/rezervace/${b.id}`)}
              className="rounded-card cursor-pointer flex flex-col"
              style={{ background: bg, padding: '12px 14px', boxShadow: '0 2px 10px rgba(15,26,20,.08)', border: isSelected ? '2px solid #fbbf24' : '1px solid #d4e8e0' }}>
              <div className="flex items-start gap-2.5">
                {selected && (
                  <label onClick={e => e.stopPropagation()} className="shrink-0 cursor-pointer flex items-center justify-center" style={{ width: 36, height: 36, margin: '-6px 0 0 -6px' }}>
                    <input type="checkbox" checked={!!isSelected} onChange={e => toggleOne(b, e.target.checked)}
                      className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }} />
                  </label>
                )}
                <div className="min-w-0 flex-1">
                  <div className="font-extrabold" style={{ fontSize: 15, color: '#0f1a14', lineHeight: 1.35 }}>
                    {b.customer_name || b.profiles?.full_name || '—'}<SourceTags b={b} install={appInstalls[b.user_id]} fs={FS} />
                  </div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>
                    {b.motorcycles?.model || '—'} <span className="font-mono">{b.motorcycles?.spz}</span>
                  </div>
                </div>
                <div className="shrink-0 text-right font-extrabold" style={{ fontSize: 15, color: '#0f1a14' }}>{amount}</div>
              </div>

              <div className="flex flex-wrap items-center gap-y-1.5 mt-2" style={{ columnGap: 6 }}>
                <StatusTags b={b} fs={FS} /><PaymentPill b={b} />
              </div>

              <div className="text-sm mt-2" style={{ color: '#0f1a14' }}>
                <span style={lbl}>Termín </span>
                <b>{fmtDateRange(b.start_date)} – {fmtDateRange(b.end_date)}</b>
                <span style={{ color: '#4a6357' }}> · {info.days} {typeof info.days === 'number' && info.days < 5 ? (info.days === 1 ? 'den' : 'dny') : 'dní'}</span>
                <DaysDelta info={info} fs={FS} />
              </div>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm mt-1" style={{ color: '#0f1a14' }}>
                <span><span style={lbl}>Pobočka </span>{branchName[bookingBranchId(b)] || '—'}{b.pickup_method === 'delivery' ? <span className="ml-1">🚚 přistavení</span> : null}</span>
                <span className="inline-flex items-center gap-1.5"><span style={lbl}>Doklady</span>
                  <DocsStatusPills profile={b.profiles} scan={scanStatus[b.user_id]}
                    requireLicense={String(b.motorcycles?.license_required || '').toUpperCase() !== 'N'} />
                </span>
              </div>

              <div className="flex-1" style={{ minHeight: 10 }} />
              <div className="flex items-center gap-2 pt-2" style={{ borderTop: '1px solid #e3efe9' }}>
                <div className="min-w-0" style={{ lineHeight: 1.3 }}>
                  <div className="font-mono text-sm" style={{ color: '#0f1a14' }}>#{b.id?.slice(-8).toUpperCase()}</div>
                  <div style={{ fontSize: 12, color: '#4a6357' }}>vytvořeno {b.created_at ? new Date(b.created_at).toLocaleString('cs-CZ') : '—'}</div>
                </div>
                <div className="ml-auto flex items-center gap-2 shrink-0">
                  {canCancel && (
                    <button onClick={e => { e.stopPropagation(); setCancelTarget(b) }}
                      style={{ ...actBtn, color: '#dc2626', background: '#fef2f2', border: '1px solid #fecaca' }}>Storno</button>
                  )}
                  <button onClick={e => { e.stopPropagation(); setDeleteConfirm(b) }}
                    style={{ ...actBtn, color: '#dc2626', background: 'transparent', border: '1px solid transparent' }}>Smazat</button>
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
