import { MobileCardList, MobileCard } from './MobileCard'
import MessageLogMobileFilters from './MessageLogMobileFilters'
import MessageLogMobileDetail from './MessageLogMobileDetail'

// Log zpráv na telefonu/tabletu (≤ 1023 px): skládací filtry, karty místo tabulky,
// velké dotykové plochy. Data i akce dodává MessageLogTab — tady je jen rozvržení.
const PILL = { fontSize: 11, padding: '2px 8px', lineHeight: '16px' }

export default function MessageLogMobile({
  channel, channelLabel, filters, setFilters, typeOptions, statusOptions, statusMap, onReset,
  logs, total, loading, error, debugMode, page, totalPages, onPageChange,
  selected, onToggleOne, onToggleAll, onDeleteSelected, deleting,
  detail, onOpenDetail, onCloseDetail, recipientOf, formatDate,
}) {
  const allChecked = logs.length > 0 && selected.size === logs.length

  return (
    <div style={{ minWidth: 0 }}>
      <MessageLogMobileFilters
        channel={channel} filters={filters} setFilters={setFilters}
        typeOptions={typeOptions} statusOptions={statusOptions} onReset={onReset}
      />

      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 12, fontFamily: 'monospace', color: '#78350f', overflowWrap: 'anywhere' }}>
          <strong>DIAGNOSTIKA MessageLogTab ({channel})</strong>
          <div>logs: {logs.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
          <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, type={filters.type}, sort={filters.sort}, search="{filters.search}"</div>
          <div>dateFrom={filters.dateFrom || '—'}, dateTo={filters.dateTo || '—'}</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 14, overflowWrap: 'anywhere' }}>{error}</div>}

      {/* Mazání výběru zůstává při posouvání seznamu nahoře */}
      {selected.size > 0 && (
        <button
          type="button"
          onClick={onDeleteSelected}
          disabled={deleting}
          className="w-full rounded-btn font-extrabold uppercase tracking-wide cursor-pointer mb-3"
          style={{ minHeight: 44, fontSize: 14, background: '#dc2626', border: '1px solid #b91c1c', color: '#fff', opacity: deleting ? 0.6 : 1, position: 'sticky', top: 0, zIndex: 5, boxShadow: '0 4px 14px rgba(220,38,38,.25)' }}
        >
          {deleting ? 'Mažu…' : `Smazat vybrané (${selected.size})`}
        </button>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          {logs.length > 0 && (
            <div className="flex items-center justify-between" style={{ gap: 8, marginBottom: 8 }}>
              <label className="flex items-center cursor-pointer" style={{ minHeight: 40, gap: 10, paddingLeft: 14, paddingRight: 8 }}>
                <input type="checkbox" checked={allChecked} onChange={onToggleAll} className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }} />
                <span className="font-extrabold" style={{ fontSize: 14, color: '#1a2e22' }}>Vybrat vše</span>
              </label>
              <span style={{ fontSize: 12, color: '#1a2e22', fontWeight: 600 }}>
                {selected.size > 0 ? `Vybráno ${selected.size} · ` : ''}Zobrazeno {logs.length} z {total}
              </span>
            </div>
          )}

          <MobileCardList empty={`Žádné ${channelLabel} zprávy`}>
            {logs.map(log => (
              <LogCard
                key={log.id}
                log={log}
                st={statusMap[log.status] || { label: log.status || '—', color: '#1a2e22', bg: '#f3f4f6' }}
                checked={selected.has(log.id)}
                onToggle={() => onToggleOne(log.id)}
                onOpen={() => onOpenDetail(log)}
                recipient={recipientOf(log)}
                time={formatDate(log.created_at)}
              />
            ))}
          </MobileCardList>

          <Pager page={page} totalPages={totalPages} onPageChange={onPageChange} />
        </>
      )}

      <MessageLogMobileDetail
        detail={detail} channelLabel={channelLabel} statusMap={statusMap}
        recipientOf={recipientOf} formatDate={formatDate} onClose={onCloseDetail}
      />
    </div>
  )
}

// E-mail se zalomí přednostně před „@", ne uprostřed slova (jinak overflowWrap kdekoli).
function breakable(text) {
  if (typeof text !== 'string' || !text.includes('@')) return text
  const at = text.indexOf('@')
  return [text.slice(0, at), <wbr key="w" />, text.slice(at)]
}

function LogCard({ log, st, checked, onToggle, onOpen, recipient, time }) {
  return (
    <MobileCard onClick={onOpen} selected={checked} style={{ padding: '0 12px 0 0' }}>
      <div className="flex" style={{ minWidth: 0 }}>
        {/* Celý levý pruh karty = výběr (velká dotyková plocha), zbytek karty otevře detail */}
        <label
          onClick={e => e.stopPropagation()}
          className="flex justify-center cursor-pointer shrink-0"
          style={{ width: 44, alignSelf: 'stretch', alignItems: 'flex-start', paddingTop: 14, minHeight: 44 }}
          aria-label="Vybrat zprávu"
        >
          <input type="checkbox" checked={checked} onChange={onToggle} className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }} />
        </label>

        <div style={{ flex: 1, minWidth: 0, padding: '12px 0' }}>
          <div className="flex items-start justify-between" style={{ gap: 8 }}>
            <div className="font-extrabold" style={{ fontSize: 15, lineHeight: 1.35, color: '#0f1a14', minWidth: 0, overflowWrap: 'anywhere' }}>
              {breakable(recipient)}
            </div>
            <span className="rounded-btn font-extrabold uppercase tracking-wide shrink-0" style={{ ...PILL, color: st.color, background: st.bg, marginTop: 1 }}>
              {st.label}
            </span>
          </div>

          <div style={{
            fontSize: 14, lineHeight: 1.45, color: '#1a2e22', marginTop: 4, overflowWrap: 'anywhere',
            display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
          }}>
            {log.content_preview || '—'}
          </div>

          {log.error_message && (
            <div className="truncate" style={{ fontSize: 12, color: '#dc2626', fontWeight: 700, marginTop: 4 }}>⚠ {log.error_message}</div>
          )}

          <div className="flex flex-wrap items-center" style={{ gap: 6, marginTop: 8, fontSize: 12, color: '#1a2e22' }}>
            <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{time}</span>
            {log.template_slug && (
              <span className="truncate rounded-btn font-bold" title={log.template_slug}
                style={{ ...PILL, minWidth: 0, maxWidth: '100%', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
                {log.template_slug}
              </span>
            )}
            {log.cost_amount != null && <span className="font-extrabold">{log.cost_amount} Kč</span>}
            {log.is_marketing && (
              <span className="rounded-btn font-extrabold uppercase tracking-wide" style={{ ...PILL, color: '#7c3aed', background: '#ede9fe' }}>Marketing</span>
            )}
          </div>
        </div>
      </div>
    </MobileCard>
  )
}

// Stránkování pro prst: šipky 44 px + výběr libovolné strany (nativní picker).
function Pager({ page, totalPages, onPageChange }) {
  if (totalPages <= 1) return null
  const btn = (disabled) => ({
    width: 48, minHeight: 44, fontSize: 18, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22',
    opacity: disabled ? 0.35 : 1,
  })
  return (
    <div className="flex items-center" style={{ gap: 8, marginTop: 14 }}>
      <button type="button" aria-label="Předchozí strana" disabled={page <= 1} onClick={() => onPageChange(page - 1)}
        className="rounded-btn font-extrabold cursor-pointer shrink-0 disabled:cursor-not-allowed" style={btn(page <= 1)}>←</button>
      <select
        value={page}
        onChange={e => onPageChange(Number(e.target.value))}
        aria-label="Strana"
        className="rounded-btn font-extrabold cursor-pointer outline-none"
        style={{ flex: 1, minWidth: 0, minHeight: 44, padding: '8px 12px', textAlign: 'center', textAlignLast: 'center', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
      >
        {Array.from({ length: totalPages }, (_, i) => (
          <option key={i + 1} value={i + 1}>Strana {i + 1} z {totalPages}</option>
        ))}
      </select>
      <button type="button" aria-label="Další strana" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}
        className="rounded-btn font-extrabold cursor-pointer shrink-0 disabled:cursor-not-allowed" style={btn(page >= totalPages)}>→</button>
    </div>
  )
}
