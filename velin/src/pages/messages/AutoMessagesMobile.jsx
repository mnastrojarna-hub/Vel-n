import { MobileCardList, MobileCard, MobileField, MobileActions, MobileActionButton } from './MobileCard'

// Automatické zprávy na telefonu/tabletu (≤ 1023 px): karty místo tabulky.
// Data i akce dodává AutoMessagesTab — tady je jen rozvržení.
const PILL = { fontSize: 11, padding: '2px 8px', lineHeight: '16px' }

export default function AutoMessagesMobile({
  channelLabel, rules, loading, onAdd, onEdit, onToggle, onDelete,
  triggerIcon, triggerLabel, formatTriggerConfig,
}) {
  return (
    <div style={{ minWidth: 0 }}>
      <div className="mb-4">
        <div className="flex items-center" style={{ gap: 8, minWidth: 0 }}>
          <h2 className="font-extrabold uppercase tracking-wide" style={{ fontSize: 14, color: '#1a2e22', minWidth: 0, overflowWrap: 'anywhere' }}>
            Automatické zprávy — {channelLabel}
          </h2>
          <span className="rounded-btn font-extrabold shrink-0" style={{ fontSize: 13, padding: '3px 10px', color: '#1a2e22', background: '#f1faf7' }}>
            {rules.length}
          </span>
        </div>
        <button
          type="button"
          onClick={onAdd}
          className="w-full rounded-btn font-extrabold uppercase tracking-wide cursor-pointer border-none"
          style={{ marginTop: 10, minHeight: 44, padding: '10px 16px', fontSize: 14, background: '#74FB71', color: '#1a2e22', boxShadow: '0 4px 16px rgba(116,251,113,.35)' }}
        >
          + Přidat automatickou zprávu
        </button>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : rules.length === 0 ? (
        <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '28px 16px' }}>
          <div style={{ fontSize: 40, marginBottom: 8 }}>🤖</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>
            Zatím žádné automatické zprávy pro {channelLabel}.
          </div>
          <div style={{ color: '#6b7280', fontSize: 13, marginTop: 4 }}>
            Vytvořte pravidlo, které automaticky odešle zprávu při splnění podmínky.
          </div>
        </div>
      ) : (
        <MobileCardList tabletGrid>
          {rules.map(rule => (
            <MobileCard key={rule.id}>
              <div className="flex items-start justify-between" style={{ gap: 8 }}>
                <div className="font-extrabold" style={{ fontSize: 15, lineHeight: 1.35, color: '#0f1a14', minWidth: 0, overflowWrap: 'anywhere' }}>
                  {rule.name || '—'}
                </div>
                <span
                  className="rounded-btn font-extrabold uppercase tracking-wide shrink-0"
                  style={{ ...PILL, marginTop: 1, color: rule.is_active ? '#1a8a18' : '#6b7280', background: rule.is_active ? '#dcfce7' : '#f3f4f6' }}
                >
                  {rule.is_active ? 'Aktivní' : 'Neaktivní'}
                </span>
              </div>

              <MobileField label="Trigger">
                <span style={{ marginRight: 4 }}>{triggerIcon(rule.trigger_type)}</span>{triggerLabel(rule.trigger_type) || '—'}
              </MobileField>
              <MobileField label="Podmínka">{formatTriggerConfig(rule)}</MobileField>
              <MobileField label="Šablona">
                {rule.template_slug
                  ? <span className="rounded-btn font-mono" style={{ ...PILL, display: 'inline-block', maxWidth: '100%', fontWeight: 700, color: '#1a2e22', background: '#f1faf7', overflowWrap: 'anywhere' }}>{rule.template_slug}</span>
                  : <span style={{ color: '#6b7280' }}>Vlastní text</span>}
              </MobileField>

              <MobileActions>
                <MobileActionButton onClick={() => onEdit(rule)}>Upravit</MobileActionButton>
                <MobileActionButton
                  onClick={() => onToggle(rule)}
                  color={rule.is_active ? '#dc2626' : '#1a8a18'}
                  bg={rule.is_active ? '#fee2e2' : '#dcfce7'}
                  border={rule.is_active ? '#fecaca' : '#bbf7d0'}
                >
                  {rule.is_active ? 'Vypnout' : 'Zapnout'}
                </MobileActionButton>
                <MobileActionButton onClick={() => onDelete(rule)} color="#dc2626" bg="#fee2e2" border="#fecaca">
                  Smazat
                </MobileActionButton>
              </MobileActions>
            </MobileCard>
          ))}
        </MobileCardList>
      )}
    </div>
  )
}
