import { useMediaQuery } from '../../hooks/useIsMobile'
import Badge from '../../components/ui/Badge'
import { CHANNEL_LABELS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS, calcSmsSegments } from './messageHelpers'

// Kroky 2–4 průvodce kampaní na telefonu/tabletu — stejné props a chování jako CampaignStep2–4,
// jen rozvržení pro prst: volby pod sebou, pole 44 px, souhrn „popisek nad hodnotou“.
const SEGMENTS = [
  { value: 'all', icon: '📋', label: 'Všichni zákazníci', desc: 'Zákazníci se souhlasem s marketingem' },
  { value: 'vip', icon: '⭐', label: 'VIP zákazníci', desc: 'Reliability skóre > 80 nebo VIP tag' },
  { value: 'past_customers', icon: '🏍️', label: 'Minulí zákazníci', desc: 'Alespoň 1 dokončená rezervace' },
  { value: 'new_no_booking', icon: '👋', label: 'Noví bez rezervace', desc: 'Registrovaní, ale dosud si nepůjčili' },
]
// Texty s diakritikou pro mobilní zobrazení (hodnoty filtrů zůstávají z messageHelpers)
const COUNTRY_TEXT = { '': 'Všechny země', CZ: 'Česko', SK: 'Slovensko', DE: 'Německo', AT: 'Rakousko', PL: 'Polsko' }
const LANG_TEXT = { '': 'Všechny jazyky', cs: 'Čeština', en: 'English', de: 'Deutsch' }
const countryText = v => COUNTRY_TEXT[v] ?? COUNTRY_OPTIONS.find(o => o.value === v)?.label
const langText = v => LANG_TEXT[v] ?? LANGUAGE_OPTIONS.find(o => o.value === v)?.label
const H = { fontSize: 12, color: '#1a2e22', marginBottom: 8 }
const LABEL = { fontSize: 13, color: '#1a2e22', marginBottom: 4 }
const FIELD = { width: '100%', minWidth: 0, minHeight: 44, padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', display: 'block' }
const NOTE = { padding: 12, fontSize: 14, lineHeight: 1.45, overflowWrap: 'anywhere' }

// Dva sloupce jen tam, kde se vejdou (tablet); na telefonu pod sebou.
function useCols() {
  return useMediaQuery('(min-width: 640px)') ? 'minmax(0, 1fr) minmax(0, 1fr)' : 'minmax(0, 1fr)'
}

function Choice({ active, onClick, children }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className="w-full text-left cursor-pointer rounded-card"
      style={{ minHeight: 52, padding: '10px 12px', border: active ? '2px solid #74FB71' : '2px solid #d4e8e0', background: active ? '#f0fdf0' : '#fff', minWidth: 0 }}
    >
      {children}
    </button>
  )
}

export function CampaignsMobileStep2({ segment, setSegment, filterCountry, setFilterCountry, filterLanguage, setFilterLanguage, channel }) {
  const cols = useCols()
  return (
    <div className="space-y-4">
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 8 }}>
        {SEGMENTS.map(s => (
          <Choice key={s.value} active={segment === s.value} onClick={() => setSegment(s.value)}>
            <div className="flex items-start" style={{ gap: 10 }}>
              <span style={{ fontSize: 22, lineHeight: 1.1 }}>{s.icon}</span>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div className="font-extrabold" style={{ fontSize: 15, color: '#0f1a14' }}>{s.label}</div>
                <div style={{ fontSize: 13, color: '#4b5563', marginTop: 2 }}>{s.desc}</div>
              </div>
              {segment === s.value && <span className="font-black" style={{ color: '#1a8a18', fontSize: 16 }}>✓</span>}
            </div>
          </Choice>
        ))}
      </div>

      <div>
        <div className="font-extrabold uppercase tracking-wide" style={H}>Filtrovat podle</div>
        <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 10 }}>
          <label className="block" style={{ minWidth: 0 }}>
            <div className="font-bold" style={LABEL}>Země původu</div>
            <select value={filterCountry} onChange={e => setFilterCountry(e.target.value)} className="rounded-btn outline-none cursor-pointer" style={FIELD}>
              {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{countryText(o.value)}</option>)}
            </select>
          </label>
          <label className="block" style={{ minWidth: 0 }}>
            <div className="font-bold" style={LABEL}>Jazyk aplikace</div>
            <select value={filterLanguage} onChange={e => setFilterLanguage(e.target.value)} className="rounded-btn outline-none cursor-pointer" style={FIELD}>
              {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{langText(o.value)}</option>)}
            </select>
          </label>
        </div>
        {(filterCountry || filterLanguage) && (
          <div className="flex flex-wrap items-center" style={{ gap: 8, marginTop: 10 }}>
            {filterCountry && <Badge label={`Země: ${countryText(filterCountry)}`} color="#2563eb" bg="#dbeafe" />}
            {filterLanguage && <Badge label={`Jazyk: ${langText(filterLanguage)}`} color="#7c3aed" bg="#ede9fe" />}
            <button
              type="button"
              onClick={() => { setFilterCountry(''); setFilterLanguage('') }}
              className="font-bold cursor-pointer border-none rounded-btn"
              style={{ minHeight: 40, padding: '6px 14px', fontSize: 14, background: '#fee2e2', color: '#dc2626' }}
            >
              Zrušit filtry
            </button>
          </div>
        )}
      </div>

      {/* Počet příjemců (i upozornění na prázdný segment) ukazuje přilepená lišta průvodce nad tlačítky. */}
      <div className="rounded-card" style={{ ...NOTE, background: '#fffbeb', border: '1px solid #fbbf24', color: '#78350f' }}>
        ⚠️ Kampaň bude odeslána pouze zákazníkům s aktivním marketingovým souhlasem.
        Zákazníci bez souhlasu (marketing_consent=false) jsou automaticky vyloučeni.
      </div>
      {channel === 'whatsapp' && (
        <div className="rounded-card" style={{ ...NOTE, background: '#dbeafe', border: '1px solid #93c5fd', color: '#1e40af' }}>
          ℹ️ WhatsApp marketingové zprávy vyžadují šablonu schválenou Metou.
          Pokud šablona nemá wa_template_id, zprávy nebudou doručeny.
        </div>
      )}
    </div>
  )
}

export function CampaignsMobileStep3({ variables, templateVars, setTemplateVars, previewText, estimatePrice, sampleRecipients, recipientCount, channel }) {
  const sms = channel === 'sms' ? calcSmsSegments(previewText) : null
  return (
    <div className="space-y-4">
      {variables.length > 0 && (
        <div>
          <div className="font-extrabold uppercase tracking-wide" style={H}>Proměnné v šabloně</div>
          <div className="space-y-3">
            {variables.map(v => (
              <label key={v} className="block" style={{ minWidth: 0 }}>
                <div className="font-mono font-bold" style={{ ...LABEL, overflowWrap: 'anywhere' }}>{`{{${v}}}`}</div>
                <input
                  type="text"
                  value={templateVars[v] || ''}
                  onChange={e => setTemplateVars(prev => ({ ...prev, [v]: e.target.value }))}
                  placeholder={`Hodnota pro ${v}`}
                  className="rounded-btn outline-none"
                  style={FIELD}
                />
              </label>
            ))}
          </div>
        </div>
      )}

      <div>
        <div className="font-extrabold uppercase tracking-wide" style={H}>Náhled zprávy</div>
        <div className="rounded-card" style={{ padding: 12, background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 14, lineHeight: 1.45, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', maxHeight: 240, overflow: 'auto', color: '#0f1a14' }}>
          {previewText || '(prázdná zpráva)'}
        </div>
        {sms && (
          <div style={{ fontSize: 13, color: '#6b7280', marginTop: 4 }}>{sms.chars} znaků · {sms.segments} SMS segment(ů)</div>
        )}
      </div>

      <div className="rounded-card" style={{ ...NOTE, background: '#f0fdf0', border: '1px solid #86efac', color: '#166534', fontWeight: 700 }}>
        {estimatePrice()}
      </div>

      {sampleRecipients.length > 0 && (
        <div>
          <div className="font-extrabold uppercase tracking-wide" style={H}>Ukázka příjemců ({recipientCount} celkem)</div>
          <div className="rounded-card" style={{ border: '1px solid #d4e8e0', overflow: 'hidden' }}>
            {sampleRecipients.map((r, i) => (
              <div key={r.id} style={{ padding: '9px 12px', borderTop: i ? '1px solid #d4e8e0' : 'none', minWidth: 0 }}>
                <div className="font-bold" style={{ fontSize: 14, color: '#0f1a14', overflowWrap: 'anywhere' }}>{r.full_name || '—'}</div>
                <div className="font-mono" style={{ fontSize: 13, color: '#1a2e22', overflowWrap: 'anywhere' }}>{(channel === 'email' ? r.email : r.phone) || '—'}</div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function SummaryRow({ label, first, children }) {
  return (
    <div style={{ padding: '7px 0', borderTop: first ? 'none' : '1px solid #e5efe9', minWidth: 0 }}>
      <div className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#1a2e22' }}>{label}</div>
      <div style={{ fontSize: 15, color: '#0f1a14', marginTop: 2, overflowWrap: 'anywhere' }}>{children}</div>
    </div>
  )
}

export function CampaignsMobileStep4({ name, selectedTemplate, recipientCount, channel, scheduleMode, setScheduleMode, scheduledAt, setScheduledAt, confirmed, setConfirmed, estimatePrice }) {
  const cols = useCols()
  const datePart = scheduledAt ? scheduledAt.split('T')[0] : ''
  const timePart = scheduledAt ? scheduledAt.split('T')[1] || '09:00' : '09:00'
  return (
    <div className="space-y-4">
      <div className="bg-white rounded-card shadow-card" style={{ padding: '6px 14px' }}>
        <SummaryRow label="Kampaň" first><span className="font-bold">{name}</span></SummaryRow>
        <SummaryRow label="Kanál"><Badge label={CHANNEL_LABELS[channel]} color="#2563eb" bg="#dbeafe" /></SummaryRow>
        <SummaryRow label="Šablona">{selectedTemplate?.name || '—'}</SummaryRow>
        <SummaryRow label="Příjemci"><span className="font-bold" style={{ color: '#1a8a18' }}>{recipientCount}</span></SummaryRow>
        <SummaryRow label="Odhad ceny"><span className="font-bold" style={{ color: '#1a8a18' }}>{estimatePrice()}</span></SummaryRow>
      </div>

      <div>
        <div className="font-extrabold uppercase tracking-wide" style={H}>Způsob odeslání</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 8 }}>
          {[['now', '🚀', 'Odeslat ihned'], ['scheduled', '📅', 'Naplánovat']].map(([mode, icon, label]) => (
            <Choice key={mode} active={scheduleMode === mode} onClick={() => setScheduleMode(mode)}>
              <span className="flex flex-col items-center text-center" style={{ gap: 2 }}>
                <span style={{ fontSize: 20 }}>{icon}</span>
                <span className="font-extrabold" style={{ fontSize: 14, color: '#0f1a14' }}>{label}</span>
              </span>
            </Choice>
          ))}
        </div>
      </div>

      {scheduleMode === 'scheduled' && (
        <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 10 }}>
          <label className="block" style={{ minWidth: 0 }}>
            <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Datum</div>
            <input type="date" value={datePart} onChange={e => setScheduledAt(e.target.value + 'T' + timePart)} className="rounded-btn outline-none" style={FIELD} />
          </label>
          <label className="block" style={{ minWidth: 0 }}>
            <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Čas</div>
            <input
              type="time"
              value={timePart}
              onChange={e => setScheduledAt((scheduledAt ? datePart : new Date().toISOString().split('T')[0]) + 'T' + e.target.value)}
              className="rounded-btn outline-none"
              style={FIELD}
            />
          </label>
        </div>
      )}

      <label className="flex items-start cursor-pointer rounded-card" style={{ gap: 12, padding: 12, background: confirmed ? '#f0fdf0' : '#f8fcfa', border: confirmed ? '2px solid #74FB71' : '2px solid #d4e8e0' }}>
        <input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} className="accent-[#1a8a18] shrink-0" style={{ width: 22, height: 22, marginTop: 1 }} />
        <span style={{ fontSize: 14, color: '#1a2e22', lineHeight: 1.5 }}>
          ✅ Rozumím, že odesílám <strong>{recipientCount}</strong> marketingových zpráv přes <strong>{CHANNEL_LABELS[channel]}</strong>.
          Tuto akci nelze vrátit zpět.
        </span>
      </label>
    </div>
  )
}
