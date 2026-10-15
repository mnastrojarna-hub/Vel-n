// Zprávy → Hodnocení: hvězdičky z appky (bookings.rating) + soukromý text „co máme zlepšit“
// (zpráva zákazníka v jeho chatu, nikdy veřejně). 1–3 ★ jsou zvýrazněné a počítají se do odznaku
// záložky, dokud nejsou vyřízené (odpověď v chatu, uzavřená konverzace nebo ruční „Vyřízeno“).
import { useState, useEffect } from 'react'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { useIsMobile } from '../../hooks/useIsMobile'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Stars, LowBadge, StatusPill, Comments, BookingLink, CustomerLink, FilterChips, SummaryBar, LOW_BG, LOW_BORDER } from './RatingsParts'
import RatingsCards from './RatingsCards'
import { breakable } from './MobileCard'
import RatingReplyModal from './RatingReplyModal'
import { filterRows, filterCounts, branchName, fmtDateTime, fmtRange } from './ratingsData'

const PER_PAGE = 25
const STORAGE_KEY = 'velin_ratings_filters'
const DEFAULT_FILTERS = { filter: 'all', search: '' }
const ACT = { padding: '6px 12px', fontSize: 12 }

export default function RatingsTab({ ratings, onOpenThread }) {
  const isMobile = useIsMobile()
  const debugMode = useDebugMode()
  const { rows, summary, loading, error, mode, busy } = ratings
  const [filters, setFilters] = useState(() => {
    try { return { ...DEFAULT_FILTERS, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') } } catch { return DEFAULT_FILTERS }
  })
  const [page, setPage] = useState(1)
  const [replyRow, setReplyRow] = useState(null)
  const [opening, setOpening] = useState(null)

  useEffect(() => { try { localStorage.setItem(STORAGE_KEY, JSON.stringify(filters)) } catch { /* blokované úložiště */ } }, [filters])
  useEffect(() => { setPage(1) }, [filters])

  const counts = filterCounts(rows)
  const list = filterRows(rows, filters.filter, filters.search)
  const totalPages = Math.ceil(list.length / PER_PAGE)
  const safePage = Math.min(page, Math.max(1, totalPages))
  const pageRows = list.slice((safePage - 1) * PER_PAGE, safePage * PER_PAGE)
  const openRows = list.filter(r => r.attention)

  async function reply(row) {
    if (!row.thread) { setReplyRow(row); return }
    setOpening(row.id)
    try { onOpenThread(await ratings.fetchThread(row.thread.id)) } catch (e) { window.alert('Konverzaci se nepodařilo otevřít: ' + (e.message || e)) }
    setOpening(null)
  }

  async function sendFirst(row, text) {
    const thread = await ratings.startThread(row, text) // chyba → zobrazí modál
    setReplyRow(null)
    onOpenThread(thread)
  }

  function markAll() {
    if (!openRows.length) return
    if (!window.confirm(`Označit ${openRows.length} hodnocení jako vyřízená? Nepřečtené komentáře se označí jako přečtené.`)) return
    ratings.markHandled(openRows)
  }

  const toolbar = (
    <div className={isMobile ? 'flex flex-col mb-3' : 'flex flex-wrap items-center mb-4'} style={{ gap: isMobile ? 8 : 12 }}>
      <SearchInput value={filters.search} onChange={v => setFilters(f => ({ ...f, search: v }))}
        placeholder="Jméno, #ID, SPZ, text…" fullWidth={isMobile} />
      <FilterChips value={filters.filter} counts={counts} onChange={v => setFilters(f => ({ ...f, filter: v }))} mobile={isMobile} />
      {filters.filter === 'open' && openRows.length > 1 && (
        <button type="button" onClick={markAll} disabled={busy}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer disabled:opacity-50"
          style={{ minHeight: isMobile ? 40 : undefined, padding: '6px 12px', background: '#fff', border: '1px solid #74FB71', color: '#1a2e22' }}>
          ✓ Označit vše jako vyřízené ({openRows.length})
        </button>
      )}
    </div>
  )

  return (
    <div>
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA RatingsTab</strong><br />
          <div>hodnocení: {rows.length}, filtr: {filters.filter} → {list.length}, odznak: {summary.badge}, vyřízeno ukládá: {mode === 'db' ? 'DB booking_rating_reviews' : 'localStorage'}</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      <SummaryBar summary={summary} mode={mode} />
      {toolbar}
      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>Načtení hodnocení selhalo: {error}</div>}

      {loading && rows.length === 0 ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : isMobile ? (
        <RatingsCards rows={pageRows} busy={busy} opening={opening} onReply={reply}
          onHandled={r => ratings.markHandled([r])} onUnhandled={ratings.unmarkHandled} />
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Hodnocení</TH><TH>Zákazník</TH><TH>Rezervace</TH><TH>Motorka</TH><TH>Pobočka</TH>
              <TH>Co máme zlepšit</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {pageRows.map(r => {
              const b = r.booking
              const hot = r.low && !r.handled
              const cell = { background: hot ? LOW_BG : undefined, verticalAlign: 'top' }
              return (
                <TRow key={r.id}>
                  <TD style={{ ...cell, borderLeft: r.low ? `4px solid ${hot ? LOW_BORDER : '#fca5a5'}` : '4px solid transparent', whiteSpace: 'nowrap' }}>
                    <div className="flex items-center" style={{ gap: 6 }}><Stars value={r.rating} />{r.low && <LowBadge />}</div>
                    <div style={{ fontSize: 12, color: '#1a2e22', marginTop: 4 }}>{fmtDateTime(r.ratedAt)}</div>
                  </TD>
                  <TD style={cell}>
                    <CustomerLink booking={b} />
                    <div style={{ fontSize: 12, color: '#1a2e22', overflowWrap: 'anywhere' }}>{breakable(b.profiles?.email || '')}</div>
                    {b.profiles?.phone && <div style={{ fontSize: 12, color: '#1a2e22' }}>{b.profiles.phone}</div>}
                  </TD>
                  <TD style={{ ...cell, whiteSpace: 'nowrap' }}>
                    <BookingLink row={r} />
                    <div style={{ fontSize: 12, color: '#1a2e22' }}>{fmtRange(b.start_date, b.end_date)}</div>
                  </TD>
                  <TD style={cell}>
                    <div style={{ fontWeight: 700 }}>{b.motorcycles?.model || '—'}</div>
                    {b.motorcycles?.spz && <div style={{ fontSize: 12, fontFamily: 'monospace', color: '#1a2e22' }}>{b.motorcycles.spz}</div>}
                  </TD>
                  <TD style={cell}>{branchName(b) || '—'}</TD>
                  <TD style={{ ...cell, minWidth: 220, maxWidth: 380 }}><Comments row={r} /></TD>
                  <TD style={cell}><StatusPill row={r} /></TD>
                  <TD style={cell}>
                    <div className="flex flex-col" style={{ gap: 6, alignItems: 'stretch' }}>
                      <button type="button" onClick={() => reply(r)} disabled={opening === r.id}
                        className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap disabled:opacity-50"
                        style={{ ...ACT, background: '#74FB71', border: 'none', color: '#1a2e22' }}>
                        {opening === r.id ? 'Otevírám…' : r.thread ? 'Odpovědět' : 'Napsat zákazníkovi'}
                      </button>
                      {r.manual ? (
                        <button type="button" onClick={() => ratings.unmarkHandled(r)} disabled={busy}
                          className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap disabled:opacity-50"
                          style={{ ...ACT, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
                          Vrátit
                        </button>
                      ) : r.attention && (
                        <button type="button" onClick={() => ratings.markHandled([r])} disabled={busy}
                          className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap disabled:opacity-50"
                          style={{ ...ACT, background: '#fff', border: '1px solid #74FB71', color: '#1a2e22' }}>
                          ✓ Vyřízeno
                        </button>
                      )}
                    </div>
                  </TD>
                </TRow>
              )
            })}
            {pageRows.length === 0 && (
              <TRow><TD colSpan={8}>{rows.length ? 'Žádná hodnocení pro zvolený filtr' : 'Zatím žádná hodnocení jízd'}</TD></TRow>
            )}
          </tbody>
        </Table>
      )}
      <Pagination page={safePage} totalPages={totalPages} onPageChange={setPage} />

      {replyRow && <RatingReplyModal row={replyRow} onClose={() => setReplyRow(null)} onSend={sendFirst} />}
    </div>
  )
}
