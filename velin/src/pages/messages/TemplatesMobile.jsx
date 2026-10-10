import SearchInput from '../../components/ui/SearchInput'
import { MobileCardList, MobileCard, MobileActions, MobileActionButton } from './MobileCard'

// Šablony zpráv na telefonu/tabletu (≤ 1023 px): hlavička pod sebou, hledání přes celou šířku,
// karty místo tabulky. Data i akce dodává MessageTemplatesTab — tady je jen rozvržení.
const PILL = { fontSize: 11, padding: '2px 8px', lineHeight: '16px' }

// Náhled těla: u e-mailu (HTML) jen čistý text, aby karta neukazovala značky.
function plainText(body) {
  if (!body) return ''
  if (!body.includes('<')) return body
  try {
    return (new DOMParser().parseFromString(body, 'text/html').body.textContent || '').replace(/\s+/g, ' ').trim()
  } catch {
    return body.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim()
  }
}

function Pill({ label, color, bg, mono = false }) {
  return (
    <span
      className={`rounded-btn font-extrabold tracking-wide ${mono ? 'font-mono' : 'uppercase'}`}
      style={{ ...PILL, display: 'inline-block', color, background: bg, overflowWrap: 'anywhere', maxWidth: '100%' }}
    >
      {label}
    </span>
  )
}

export default function TemplatesMobile({
  channel, channelLabel, totalCount, filtered, loading, error, debugMode, search, setSearch,
  langLabel, onAdd, onEdit, onDuplicate, onToggle, onDelete,
}) {
  return (
    <div style={{ minWidth: 0 }}>
      <div className="mb-4">
        <div className="flex items-center" style={{ gap: 8, minWidth: 0 }}>
          <h2 className="font-extrabold uppercase tracking-wide" style={{ fontSize: 14, color: '#1a2e22', minWidth: 0, overflowWrap: 'anywhere' }}>
            {channelLabel} Šablony
          </h2>
          <span className="rounded-btn font-extrabold shrink-0" style={{ fontSize: 13, padding: '3px 10px', color: '#1a2e22', background: '#f1faf7' }}>
            {totalCount}
          </span>
        </div>
        <button
          type="button"
          onClick={onAdd}
          className="w-full rounded-btn font-extrabold uppercase tracking-wide cursor-pointer border-none"
          style={{ marginTop: 10, minHeight: 44, padding: '10px 16px', fontSize: 14, background: '#74FB71', color: '#1a2e22', boxShadow: '0 4px 16px rgba(116,251,113,.35)' }}
        >
          + Nová šablona
        </button>
        <div style={{ marginTop: 10 }}>
          <SearchInput value={search} onChange={setSearch} placeholder="Hledat šablonu…" fullWidth />
        </div>
      </div>

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 12, fontFamily: 'monospace', color: '#78350f', overflowWrap: 'anywhere' }}>
          <strong>DIAGNOSTIKA MessageTemplatesTab ({channel})</strong><br />
          <div>templates: {totalCount}, filtered: {filtered.length}, search: "{search}"</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 14, overflowWrap: 'anywhere' }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : filtered.length === 0 ? (
        <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '28px 16px' }}>
          <div style={{ fontSize: 40, marginBottom: 8 }}>📝</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>
            {search ? 'Žádné šablony odpovídající hledání' : `Zatím žádné ${channelLabel} šablony. Vytvořte první!`}
          </div>
        </div>
      ) : (
        <MobileCardList tabletGrid>
          {filtered.map(tpl => {
            const preview = plainText(tpl.body_template || tpl.content || '')
            return (
              <MobileCard key={tpl.id}>
                <div className="flex items-start justify-between" style={{ gap: 8 }}>
                  <div className="font-extrabold" style={{ fontSize: 15, lineHeight: 1.35, color: '#0f1a14', minWidth: 0, overflowWrap: 'anywhere' }}>
                    {tpl.name || '—'}
                  </div>
                  <span
                    className="rounded-btn font-extrabold uppercase tracking-wide shrink-0"
                    style={{ ...PILL, marginTop: 1, color: tpl.is_active ? '#1a8a18' : '#6b7280', background: tpl.is_active ? '#dcfce7' : '#f3f4f6' }}
                  >
                    {tpl.is_active ? 'Aktivní' : 'Neaktivní'}
                  </span>
                </div>
                <div className="font-mono" style={{ fontSize: 12, color: '#1a2e22', marginTop: 2, overflowWrap: 'anywhere' }}>{tpl.slug || '—'}</div>

                <div className="flex flex-wrap" style={{ gap: 6, marginTop: 8 }}>
                  {tpl.is_marketing
                    ? <Pill label="Marketing" color="#7c3aed" bg="#ede9fe" />
                    : <Pill label="Transakční" color="#1a8a18" bg="#dcfce7" />}
                  <Pill label={langLabel(tpl.language)} color="#1a2e22" bg="#f1faf7" />
                  {tpl.trigger_type
                    ? <Pill label={tpl.trigger_type} color="#b45309" bg="#fef3c7" mono />
                    : <span style={{ fontSize: 12, color: '#6b7280', alignSelf: 'center' }}>Bez triggeru</span>}
                </div>

                {channel === 'email' && (tpl.subject_template || tpl.subject) && (
                  <div style={{ fontSize: 13, color: '#0f1a14', marginTop: 8, fontWeight: 700, overflowWrap: 'anywhere' }}>
                    Předmět: {tpl.subject_template || tpl.subject}
                  </div>
                )}
                {/* Odsazení na obalu: ořez 3 řádků je pak na hraně textu a 4. řádek nepřesahuje do spodního odsazení */}
                <div style={{ marginTop: 8, padding: '8px 10px', borderRadius: 12, background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
                  <div
                    style={{
                      fontSize: 14, lineHeight: 1.45, color: preview ? '#0f1a14' : '#6b7280', overflowWrap: 'anywhere',
                      display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
                    }}
                  >
                    {preview || '(prázdná)'}
                  </div>
                </div>

                <MobileActions>
                  <MobileActionButton onClick={() => onEdit(tpl)}>Upravit</MobileActionButton>
                  <MobileActionButton onClick={() => onDuplicate(tpl)} color="#2563eb" bg="#dbeafe" border="#bfdbfe">Duplikovat</MobileActionButton>
                  <MobileActionButton
                    onClick={() => onToggle(tpl)}
                    color={tpl.is_active ? '#dc2626' : '#1a8a18'}
                    bg={tpl.is_active ? '#fee2e2' : '#dcfce7'}
                    border={tpl.is_active ? '#fecaca' : '#bbf7d0'}
                  >
                    {tpl.is_active ? 'Deaktivovat' : 'Aktivovat'}
                  </MobileActionButton>
                  <MobileActionButton onClick={() => onDelete(tpl)} color="#dc2626" bg="#fee2e2" border="#fecaca">Smazat</MobileActionButton>
                </MobileActions>
              </MobileCard>
            )
          })}
        </MobileCardList>
      )}
    </div>
  )
}
