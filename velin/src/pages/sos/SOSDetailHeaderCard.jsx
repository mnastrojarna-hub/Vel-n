import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSWorkflowStepper, { WORKFLOWS } from './SOSWorkflowStepper'
import { DECISION_LABELS, REPLACEMENT_STATUS_LABELS, REPLACEMENT_STATUS_COLORS, InfoRow, STATUS_COLORS, SEVERITY_MAP, TYPE_LABELS, TYPE_ICONS } from './SOSDetailConstants'

export function HeaderCard({ incident, sev, sc, displayTitle, isActive, admins, assignAdmin, updateIncidentStatus, timelineActions, motoInService, moto }) {
  const workflow = WORKFLOWS[incident?.type]
  let allPreResolveComplete = true
  if (workflow) {
    const enriched = {
      ...incident,
      _timelineActions: timelineActions || [],
      _motoInService: motoInService || moto?.status === 'maintenance' || false,
    }
    const activeSteps = workflow.steps.filter(s => s.id !== 'resolve' && (!s.skip || !s.skip(enriched)))
    allPreResolveComplete = activeSteps.every(s => s.check(enriched))
  }
  return (
      <Card>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <span className="text-2xl">{TYPE_ICONS[incident.type] || '⚠️'}</span>
            <div>
              <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>{displayTitle}</h3>
              {incident.title && (
                <span className="text-sm font-bold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
                  {TYPE_LABELS[incident.type] || incident.type}
                </span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sev.bg, color: sev.color }}>{sev.label}</span>
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sc.bg, color: sc.color }}>{sc.label}</span>
            <button onClick={onClose} className="text-sm font-bold cursor-pointer"
              style={{ color: '#1a2e22', background: 'none', border: 'none' }}>✕</button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 text-sm">
          <InfoRow label="ID" value={incident.id?.slice(0, 8)} mono />
          <InfoRow label="Nahlášeno" value={incident.created_at ? new Date(incident.created_at).toLocaleString('cs-CZ') : '—'} />
          <InfoRow label="Kontakt" value={incident.contact_phone || customer?.phone || incident.profiles?.phone} />
          {incident.moto_rideable !== null && incident.moto_rideable !== undefined && (
            <InfoRow label="Pojízdná" value={incident.moto_rideable ? 'Ano' : 'NE — nepojízdná'} />
          )}
        </div>

        {/* Popis od zákazníka */}
        {incident.description && (
          <div className="mt-3 rounded-lg text-sm" style={{
            padding: '10px 14px', background: '#f8fcfa', color: '#1a2e22',
            borderLeft: '3px solid #d4e8e0', lineHeight: 1.6,
          }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Popis od zákazníka
            </div>
            {incident.description}
          </div>
        )}

        {/* Preference zákazníka – prominentní zobrazení */}
        {(incident.customer_decision || incident.customer_fault !== null) && (
          <div className="mt-3 rounded-lg" style={{
            padding: '12px 14px',
            background: incident.customer_fault ? '#fef2f2' : '#f0fdf4',
            border: `2px solid ${incident.customer_fault ? '#fca5a5' : '#86efac'}`,
          }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{
              color: incident.customer_fault ? '#dc2626' : '#1a8a18'
            }}>
              Preference zákazníka
            </div>
            <div className="flex flex-wrap gap-2">
              {incident.customer_decision && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px',
                  background: incident.customer_fault ? '#fee2e2' : '#dcfce7',
                  color: incident.customer_fault ? '#b91c1c' : '#15803d',
                }}>
                  {DECISION_LABELS[incident.customer_decision] || incident.customer_decision}
                </span>
              )}
              {incident.customer_fault === true && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px', background: '#fee2e2', color: '#b91c1c',
                }}>
                  ⚠️ Zavinil zákazník (platí)
                </span>
              )}
              {incident.customer_fault === false && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px', background: '#dcfce7', color: '#15803d',
                }}>
                  Cizí zavinění (zdarma)
                </span>
              )}
              {incident.moto_rideable === false && (
                <>
                  <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                    padding: '4px 10px', background: '#fef3c7', color: '#b45309',
                  }}>
                    Motorka nepojízdná
                  </span>
                  {!motoInService && moto?.status !== 'maintenance' && (
                    <button onClick={setMotoToService} className="inline-block rounded-btn text-sm font-extrabold cursor-pointer" style={{
                      padding: '4px 10px', background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5',
                    }}>
                      🔧 Přesunout do servisu
                    </button>
                  )}
                  {(motoInService || moto?.status === 'maintenance') && (
                    <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                      padding: '4px 10px', background: '#dcfce7', color: '#15803d',
                    }}>
                      ✅ V servisu
                    </span>
                  )}
                </>
              )}
            </div>
            {incident.replacement_status && (
              <div className="mt-2">
                <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{
                  padding: '3px 8px',
                  ...(REPLACEMENT_STATUS_COLORS[incident.replacement_status] || { bg: '#f1faf7', color: '#1a2e22' }),
                  background: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).bg,
                  color: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).color,
                }}>
                  {REPLACEMENT_STATUS_LABELS[incident.replacement_status] || incident.replacement_status}
                </span>
              </div>
            )}
          </div>
        )}

        {/* Přiřadit */}
        <div className="mt-3 flex items-center gap-2">
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Přiřadit:</span>
          <select value={incident.assigned_to || ''} onChange={e => assignAdmin(e.target.value)}
            className="rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '4px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="">Nepřiřazeno</option>
            {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>

        {/* Status forward buttons */}
        {isActive && (() => {
          // Check if all workflow steps (except resolve itself) are complete
          const workflow = WORKFLOWS[incident?.type]
          let allPreResolveComplete = true
          if (workflow) {
            const enriched = {
              ...incident,
              _timelineActions: timelineActions || [],
              _motoInService: motoInService || moto?.status === 'maintenance' || false,
            }
            const activeSteps = workflow.steps.filter(s => s.id !== 'resolve' && (!s.skip || !s.skip(enriched)))
            allPreResolveComplete = activeSteps.every(s => s.check(enriched))
          }
          return (
            <div className="mt-3 flex flex-wrap gap-2">
              {incident.status === 'reported' && (
                <button onClick={() => updateIncidentStatus('acknowledged')}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{ padding: '8px 16px', background: '#fef3c7', color: '#b45309' }}>
                  Potvrdit příjem
                </button>
              )}
              {(incident.status === 'reported' || incident.status === 'acknowledged') && (
                <button onClick={() => updateIncidentStatus('in_progress')}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{ padding: '8px 16px', background: '#dbeafe', color: '#2563eb' }}>
                  Začít řešit
                </button>
              )}
              {incident.status !== 'resolved' && (
                <button
                  onClick={allPreResolveComplete ? () => updateIncidentStatus('resolved') : undefined}
                  disabled={!allPreResolveComplete}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '8px 16px',
                    background: allPreResolveComplete ? '#dcfce7' : '#e5e7eb',
                    color: allPreResolveComplete ? '#1a8a18' : '#9ca3af',
                    cursor: allPreResolveComplete ? 'pointer' : 'not-allowed',
                    opacity: allPreResolveComplete ? 1 : 0.6,
                  }}>
                  {allPreResolveComplete ? 'Vyřešeno' : 'Vyřešeno (dokončete kroky)'}
                </button>
              )}
            </div>
          )
        })()}
      </Card>
  )
}

export function NotesCard({ incidentNotes, noteText, setNoteText, addNote, savingNote }) {
  return (
      <Card>
        <div style={{
          padding: '2px',
          background: '#fffbeb',
          border: '2px solid #fbbf24',
          borderRadius: 8,
        }}>
          <div style={{ padding: '12px 14px' }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>
              Poznámky k incidentu (tel. komunikace apod.)
            </div>
            {incidentNotes.length > 0 && (
              <div className="space-y-2 mb-3">
                {incidentNotes.map(n => (
                  <div key={n.id} className="rounded-lg text-sm" style={{
                    padding: '8px 10px', background: '#fff', border: '1px solid #fde68a', lineHeight: 1.6,
                  }}>
                    <div style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{n.description}</div>
                    <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                      {n.created_at ? new Date(n.created_at).toLocaleString('cs-CZ') : ''}
                      {n.performed_by && ` · ${n.performed_by}`}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {incidentNotes.length === 0 && (
              <div className="text-sm mb-3" style={{ color: '#92400e', fontStyle: 'italic' }}>
                Zatím žádné poznámky.
              </div>
            )}
            <textarea value={noteText} onChange={e => setNoteText(e.target.value)}
              rows={2} placeholder="Napište poznámku (např. z telefonátu se zákazníkem)…"
              className="w-full rounded-btn text-sm outline-none mb-2"
              style={{ padding: '8px 12px', background: '#fff', border: '1px solid #fde68a', resize: 'vertical' }}
            />
            <Button onClick={addNote} disabled={savingNote || !noteText.trim()}
              style={{ background: '#fbbf24', color: '#78350f', fontSize: 13, padding: '6px 16px' }}>
              {savingNote ? 'Ukládám…' : 'Přidat poznámku'}
            </Button>
          </div>
        </div>
      </Card>
  )
}

export function WorkflowStepperCard({ incident, timelineActions, motoInService, moto }) {
  return (
    <SOSWorkflowStepper
      incident={incident}
      timelineActions={timelineActions}
      motoInService={motoInService || moto?.status === 'maintenance'}
    />
  )
}
