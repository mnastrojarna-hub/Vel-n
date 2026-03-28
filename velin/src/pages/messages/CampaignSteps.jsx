import Badge from '../../components/ui/Badge'
import Card from '../../components/ui/Card'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import { CHANNEL_LABELS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS } from './messageHelpers'

const SEGMENTS = [
  { value: 'all', icon: '\ud83d\udccb', label: 'Vsichni zakaznici', desc: 'Zakaznici se souhlasem s marketingem' },
  { value: 'vip', icon: '\u2b50', label: 'VIP zakaznici', desc: 'Reliability skore > 80 nebo VIP tag' },
  { value: 'past_customers', icon: '\ud83c\udfcd\ufe0f', label: 'Minuli zakaznici', desc: 'Alespon 1 dokoncena rezervace' },
  { value: 'new_no_booking', icon: '\ud83d\udc4b', label: 'Novi bez rezervace', desc: 'Registrovani, ale dosud si nepujcili' },
]

export { SEGMENTS }

export function CampaignStep2({ segment, setSegment, filterCountry, setFilterCountry, filterLanguage, setFilterLanguage, recipientCount, recipientCountLoading, channel }) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        {SEGMENTS.map(s => (
          <div
            key={s.value}
            onClick={() => setSegment(s.value)}
            className="cursor-pointer rounded-card"
            style={{
              padding: 12,
              border: segment === s.value ? '2px solid #74FB71' : '2px solid #d4e8e0',
              background: segment === s.value ? '#f0fdf0' : '#fff',
            }}
          >
            <div className="flex items-center gap-2 mb-1">
              <span style={{ fontSize: 20 }}>{s.icon}</span>
              <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{s.label}</span>
            </div>
            <div style={{ fontSize: 12, color: '#6b7280' }}>{s.desc}</div>
          </div>
        ))}
      </div>

      <div>
        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
          Filtrovat podle
        </div>
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Země původu</label>
            <select
              value={filterCountry}
              onChange={e => setFilterCountry(e.target.value)}
              className="w-full rounded-btn text-sm outline-none cursor-pointer"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            >
              {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>
          <div className="flex-1">
            <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Jazyk aplikace</label>
            <select
              value={filterLanguage}
              onChange={e => setFilterLanguage(e.target.value)}
              className="w-full rounded-btn text-sm outline-none cursor-pointer"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            >
              {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>
        </div>
        {(filterCountry || filterLanguage) && (
          <div className="flex items-center gap-2 mt-2">
            <Badge label={filterCountry ? `Země: ${COUNTRY_OPTIONS.find(o => o.value === filterCountry)?.label}` : ''} color="#2563eb" bg="#dbeafe" />
            {filterLanguage && <Badge label={`Jazyk: ${LANGUAGE_OPTIONS.find(o => o.value === filterLanguage)?.label}`} color="#7c3aed" bg="#ede9fe" />}
            <button
              onClick={() => { setFilterCountry(''); setFilterLanguage('') }}
              className="text-sm font-bold cursor-pointer border-none rounded-btn"
              style={{ padding: '3px 8px', background: '#fee2e2', color: '#dc2626' }}
            >
              Zrušit filtry
            </button>
          </div>
        )}
      </div>

      <div className="flex items-center gap-3 py-2">
        {recipientCountLoading ? (
          <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" />
        ) : (
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 24 }}>👥</span>
            <span className="text-2xl font-black" style={{ color: '#1a8a18' }}>{recipientCount}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>příjemců</span>
          </div>
        )}
      </div>

      {recipientCount === 0 && !recipientCountLoading && (
        <div className="rounded-card" style={{ padding: 12, background: '#fee2e2', border: '1px solid #fca5a5', fontSize: 13, color: '#dc2626' }}>
          Žádní příjemci v tomto segmentu. Zvolte jiný segment.
        </div>
      )}

      <div className="rounded-card" style={{ padding: 12, background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, color: '#78350f' }}>
        ⚠️ Kampaň bude odeslána pouze zákazníkům s aktivním marketingovým souhlasem.
        Zákazníci bez souhlasu (marketing_consent=false) jsou automaticky vyloučeni.
      </div>

      {channel === 'whatsapp' && (
        <div className="rounded-card" style={{ padding: 12, background: '#dbeafe', border: '1px solid #93c5fd', fontSize: 13, color: '#1e40af' }}>
          ℹ️ WhatsApp marketingové zprávy vyžadují šablonu schválenou Metou.
          Pokud šablona nemá wa_template_id, zprávy nebudou doručeny.
        </div>
      )}
    </div>
  )
}

export function CampaignStep4({ name, selectedTemplate, recipientCount, channel, scheduleMode, setScheduleMode, scheduledAt, setScheduledAt, confirmed, setConfirmed, estimatePrice }) {
  return (
    <div className="space-y-4">
      <Card>
        <div className="space-y-2" style={{ fontSize: 13 }}>
          <div className="flex gap-2">
            <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Kampaň:</span>
            <span className="font-bold" style={{ color: '#0f1a14' }}>{name}</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Kanál:</span>
            <Badge label={CHANNEL_LABELS[channel]} color="#2563eb" bg="#dbeafe" />
          </div>
          <div className="flex gap-2">
            <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Šablona:</span>
            <span style={{ color: '#0f1a14' }}>{selectedTemplate?.name || '—'}</span>
          </div>
          <div className="flex gap-2">
            <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Příjemci:</span>
            <span className="font-bold" style={{ color: '#1a8a18' }}>{recipientCount}</span>
          </div>
          <div className="flex gap-2">
            <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Odhad ceny:</span>
            <span className="font-bold" style={{ color: '#1a8a18' }}>{estimatePrice()}</span>
          </div>
        </div>
      </Card>

      <div>
        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
          Způsob odeslání
        </div>
        <div className="flex gap-3">
          <div
            onClick={() => setScheduleMode('now')}
            className="cursor-pointer rounded-card flex-1"
            style={{
              padding: 12,
              border: scheduleMode === 'now' ? '2px solid #74FB71' : '2px solid #d4e8e0',
              background: scheduleMode === 'now' ? '#f0fdf0' : '#fff',
            }}
          >
            <div className="flex items-center gap-2">
              <span style={{ fontSize: 18 }}>🚀</span>
              <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Odeslat ihned</span>
            </div>
          </div>
          <div
            onClick={() => setScheduleMode('scheduled')}
            className="cursor-pointer rounded-card flex-1"
            style={{
              padding: 12,
              border: scheduleMode === 'scheduled' ? '2px solid #74FB71' : '2px solid #d4e8e0',
              background: scheduleMode === 'scheduled' ? '#f0fdf0' : '#fff',
            }}
          >
            <div className="flex items-center gap-2">
              <span style={{ fontSize: 18 }}>📅</span>
              <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Naplánovat</span>
            </div>
          </div>
        </div>
      </div>

      {scheduleMode === 'scheduled' && (
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Datum</label>
            <input
              type="date"
              value={scheduledAt ? scheduledAt.split('T')[0] : ''}
              onChange={e => {
                const time = scheduledAt ? scheduledAt.split('T')[1] || '09:00' : '09:00'
                setScheduledAt(e.target.value + 'T' + time)
              }}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            />
          </div>
          <div className="flex-1">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Čas</label>
            <input
              type="time"
              value={scheduledAt ? scheduledAt.split('T')[1] || '09:00' : '09:00'}
              onChange={e => {
                const date = scheduledAt ? scheduledAt.split('T')[0] : new Date().toISOString().split('T')[0]
                setScheduledAt(date + 'T' + e.target.value)
              }}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            />
          </div>
        </div>
      )}

      <label className="flex items-start gap-3 cursor-pointer rounded-card" style={{ padding: 12, background: confirmed ? '#f0fdf0' : '#f8fcfa', border: confirmed ? '2px solid #74FB71' : '2px solid #d4e8e0' }}>
        <input
          type="checkbox"
          checked={confirmed}
          onChange={e => setConfirmed(e.target.checked)}
          className="accent-[#1a8a18] mt-0.5"
          style={{ width: 18, height: 18 }}
        />
        <span className="text-sm" style={{ color: '#1a2e22', lineHeight: 1.5 }}>
          ✅ Rozumím, že odesílám <strong>{recipientCount}</strong> marketingových zpráv přes <strong>{CHANNEL_LABELS[channel]}</strong>.
          Tuto akci nelze vrátit zpět.
        </span>
      </label>
    </div>
  )
}
