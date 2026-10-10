import Badge from '../../components/ui/Badge'
import DocsStatusPills from '../../components/DocsStatusPills'
import AppInstallBadge from '../../components/AppInstallBadge'

// Seznam zákazníků pod 1024 px (telefon 1 sloupec, tablet 2 sloupce) — stejné údaje
// jako sloupce tabulky v Customers.jsx, jen jako karty. Desktop dál vykresluje tabulku.
// stat = { avgPrice, avgDays, topMoto, topBranch } — stejné výpočty jako sloupce tabulky.
export default function CustomerListMobile({ customers, selected, onToggle, onToggleAll, appInstalls, scanStatus, stat, onOpen }) {
  const allChecked = customers.length > 0 && customers.every(c => selected.has(c.id))
  return (
    <div>
      {customers.length > 0 && (
        <label className="inline-flex items-center gap-2 mb-3 cursor-pointer rounded-btn"
          style={{ padding: '8px 14px', minHeight: 40, background: '#fff', boxShadow: '0 2px 8px rgba(15,26,20,.08)' }}>
          <input type="checkbox" className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }}
            checked={allChecked} onChange={e => onToggleAll(e.target.checked)} />
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Vybrat vše</span>
        </label>
      )}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {customers.map(c => {
          const sel = selected.has(c.id)
          return (
            <div key={c.id} onClick={() => onOpen(c.id)} className="rounded-card cursor-pointer min-w-0"
              style={{ padding: 14, background: sel ? '#fef9c3' : '#fff', boxShadow: '0 2px 10px rgba(15,26,20,.08)' }}>
              <div className="flex items-start gap-2">
                {/* Zaškrtávátko pro hromadnou správu — vlastní dotyková plocha 40 px, klik neotevře detail */}
                <label onClick={e => e.stopPropagation()} className="flex items-center justify-center shrink-0 cursor-pointer"
                  style={{ width: 40, height: 40, margin: '-8px 0 0 -8px' }}>
                  <input type="checkbox" className="accent-[#1a8a18] cursor-pointer" style={{ width: 20, height: 20 }}
                    checked={sel} onChange={e => onToggle(c, e.target.checked)} />
                </label>
                <div className="flex-1 min-w-0">
                  <div className="font-bold break-words" style={{ fontSize: 15, color: '#0f1a14' }}>
                    {c.full_name || '—'}<AppInstallBadge install={appInstalls[c.id]} />
                  </div>
                  <div className="text-sm break-all" style={{ color: '#1a2e22' }}>{c.email || '—'}</div>
                  <div className="text-sm font-mono" style={{ color: '#1a2e22' }}>{c.phone || '—'}</div>
                </div>
                <SourceTag source={c.registration_source} />
              </div>
              <div className="flex flex-wrap items-center gap-2 mt-2">
                {c.license_group?.length > 0
                  ? c.license_group.map(g => <Badge key={g} label={g} color="#1a8a18" bg="#dcfce7" />)
                  : <span className="text-xs font-bold" style={{ color: '#6b7280' }}>Skupiny: —</span>}
                <span className="ml-auto flex items-center gap-1.5">
                  <span className="text-xs font-bold" style={{ color: '#6b7280' }}>Doklady</span>
                  <DocsStatusPills profile={c} scan={scanStatus[c.id]} />
                </span>
              </div>
              <div className="grid grid-cols-2 gap-x-3 gap-y-2 mt-3 pt-3" style={{ borderTop: '1px solid #e3efe9' }}>
                <Stat label="Město" value={c.city} />
                <Stat label="Země" value={c.country} />
                <Stat label="Registrace" value={c.created_at?.slice(0, 10)} />
                <Stat label="Rezervací" value={c.bookings?.[0]?.count ?? 0} bold />
                <Stat label="Ø částka" value={stat.avgPrice(c.id)} />
                <Stat label="Ø délka" value={stat.avgDays(c.id)} />
                <Stat label="Top motorka" value={stat.topMoto(c.id)} />
                <Stat label="Top pobočka" value={stat.topBranch(c.id)} />
              </div>
            </div>
          )
        })}
      </div>
      {customers.length === 0 && (
        <div className="rounded-card p-4 text-sm" style={{ background: '#fff', color: '#0f1a14' }}>Žádní zákazníci</div>
      )}
    </div>
  )
}

function SourceTag({ source }) {
  if (source === 'app') return <span className="shrink-0 text-[10px] font-extrabold px-2 py-0.5 rounded-btn" style={{ background: '#dcfce7', color: '#16a34a' }}>APP</span>
  if (source === 'web') return <span className="shrink-0 text-[10px] font-extrabold px-2 py-0.5 rounded-btn" style={{ background: '#dbeafe', color: '#2563eb' }}>WEB</span>
  return null
}

function Stat({ label, value, bold = false }) {
  const empty = value === null || value === undefined || value === ''
  return (
    <div className="min-w-0">
      <div className="text-[11px] font-extrabold uppercase tracking-wide" style={{ color: '#4a6357' }}>{label}</div>
      <div className="text-sm break-words" style={{ color: '#0f1a14', fontWeight: bold ? 700 : 500 }}>{empty ? '—' : value}</div>
    </div>
  )
}
