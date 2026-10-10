import { TRow, TH, TD, Table } from '../../components/ui/Table'
import DocsStatusPills from '../../components/DocsStatusPills'
import { useIsMobile } from '../../hooks/useIsMobile'
import { shortBranchName, bookingBranchId } from './BranchChips'
import { bookingDaysInfo, DaysDelta, SourceTags, PaymentPill, StatusTags } from './bookingsListParts'
import BookingsListMobile from './BookingsListMobile'

export default function BookingsTable({ bookings, navigate, fmtDateRange, dpTotals, scanStatus = {}, appInstalls = {}, setDeleteConfirm, setCancelTarget, selected, setSelected, branches = [], onBulk = null }) {
  const isMobile = useIsMobile() // < 1024 px → karty (BookingsListMobile), desktop tabulka beze změny
  const branchName = Object.fromEntries((branches || []).map(br => [br.id, shortBranchName(br.name)]))
  // `selected` je Map<id, row> — drží celé řádky napříč stránkami, aby hromadná akce zahrnula i výběr z jiných stránek
  const allSelected = bookings.length > 0 && selected && bookings.every(b => selected.has(b.id))
  const toggleAll = e => {
    if (!setSelected) return
    const next = new Map(selected)
    if (e.target.checked) bookings.forEach(b => next.set(b.id, b))
    else bookings.forEach(b => next.delete(b.id))
    setSelected(next)
  }
  const toggleOne = (row, checked) => {
    if (!setSelected) return
    const next = new Map(selected)
    if (checked) next.set(row.id, row); else next.delete(row.id)
    setSelected(next)
  }
  if (isMobile) {
    return <BookingsListMobile bookings={bookings} navigate={navigate} fmtDateRange={fmtDateRange} dpTotals={dpTotals} scanStatus={scanStatus} appInstalls={appInstalls}
      setDeleteConfirm={setDeleteConfirm} setCancelTarget={setCancelTarget} selected={selected} allSelected={allSelected} toggleAll={toggleAll} toggleOne={toggleOne} branchName={branchName} onBulk={onBulk} />
  }
  return (
    <Table>
      <thead>
        <TRow header>
          {selected && (
            <TH>
              <input type="checkbox" checked={allSelected} onChange={toggleAll}
                className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }} />
            </TH>
          )}
          <TH>ID</TH><TH>Zákazník</TH><TH>Motorka</TH><TH>Pobočka</TH>
          <TH>Od</TH><TH>Do</TH><TH>Dní</TH><TH>Částka</TH><TH>Platba</TH><TH>Stav</TH><TH>Doklady</TH><TH>Vytvořeno</TH><TH>Akce</TH>
        </TRow>
      </thead>
      <tbody>
        {bookings.map(b => {
          const info = bookingDaysInfo(b)
          const isSelected = selected?.has(b.id)
          const rowBg = isSelected ? '#fef9c3'
            : b.booking_source === 'web' ? '#eff6ff'
            : b.booking_source === 'app' ? '#f0fff0' : undefined
          return (
            <tr key={b.id} onClick={() => navigate(`/rezervace/${b.id}`)}
              className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
              style={{ borderBottom: '1px solid #d4e8e0', background: rowBg }}>
              {selected && (
                <TD>
                  <input type="checkbox" checked={!!isSelected}
                    onClick={e => e.stopPropagation()}
                    onChange={e => toggleOne(b, e.target.checked)}
                    className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }} />
                </TD>
              )}
              <TD mono>{b.id?.slice(-8).toUpperCase()}</TD>
              <TD bold>{b.customer_name || b.profiles?.full_name || '—'}<SourceTags b={b} install={appInstalls[b.user_id]} /></TD>
              <TD>{b.motorcycles?.model || '—'} <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span></TD>
              {/* pobočka = pobočka motorky (přistavení na adresu = 🚚 + pobočka motorky) */}
              <TD>{branchName[bookingBranchId(b)] || '—'}{b.pickup_method === 'delivery' ? <span className="ml-1" title="Přistavení na adresu">🚚</span> : null}</TD>
              <TD>{fmtDateRange(b.start_date)}</TD>
              <TD>{fmtDateRange(b.end_date)}</TD>
              <TD>{info.days}<DaysDelta info={info} /></TD>
              <TD bold>{(dpTotals[b.id] || b.total_price) ? `${Number(dpTotals[b.id] || b.total_price).toLocaleString('cs-CZ')} Kč` : '—'}</TD>
              <TD><PaymentPill b={b} /></TD>
              <TD><StatusTags b={b} /></TD>
              <TD>
                {/* KROK 4 = čísla dokladů z profilu; SKEN = fotka/OCR. Bez ŘP u dětské
                    motorky (N). Sdílené UI s Customers.jsx (DocsStatusPills). */}
                <DocsStatusPills profile={b.profiles} scan={scanStatus[b.user_id]}
                  requireLicense={String(b.motorcycles?.license_required || '').toUpperCase() !== 'N'} />
              </TD>
              <TD><span className="text-sm" style={{ color: '#1a2e22' }}>{b.created_at ? new Date(b.created_at).toLocaleString('cs-CZ') : '—'}</span></TD>
              <TD>
                <div className="flex items-center gap-2">
                  {setCancelTarget && (b.status === 'pending' || b.status === 'reserved' || b.status === 'active') && (
                    <button onClick={e => { e.stopPropagation(); setCancelTarget(b) }}
                      className="text-sm font-bold cursor-pointer"
                      style={{ color: '#dc2626', background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 6, padding: '4px 8px' }}>
                      Storno
                    </button>
                  )}
                  <button onClick={e => { e.stopPropagation(); setDeleteConfirm(b) }}
                    className="text-sm font-bold cursor-pointer"
                    style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 6px' }}>
                    Smazat
                  </button>
                </div>
              </TD>
            </tr>
          )
        })}
        {bookings.length === 0 && <TRow><TD>Žádné rezervace</TD></TRow>}
      </tbody>
    </Table>
  )
}
