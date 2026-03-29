import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import { WorkflowBtn, TYPE_LABELS } from './SOSDetailConstants'

export function ActionsCard({ incident, isActive, isAccident, isMajor, motoInService, moto, timelineActions, loadTimelineActions, setMotoToService, onRefresh, policeNumber, setPoliceNumber, saveField }) {
  if (!isActive) return null
  return (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wider mb-3" style={{ color: '#1a2e22' }}>
            Akce pro tento incident
          </h4>
          <div className="flex flex-wrap gap-2">
            {/* Kontaktovat zákazníka */}
            <WorkflowBtn
              label="Zákazník kontaktován"
              icon="📞"
              done={timelineActions.some(a => a.toLowerCase().includes('kontaktován') || a.toLowerCase().includes('zpráva odeslána'))}
              onClick={async () => {
                const { data: { user } } = await supabase.auth.getUser()
                await supabase.from('sos_timeline').insert({
                  incident_id: incident.id,
                  action: 'Zákazník telefonicky kontaktován',
                  performed_by: user?.email || 'Admin', admin_id: user?.id,
                })
                await loadTimelineActions()
                onRefresh?.()
              }}
            />

            {/* Odtah — pro těžké nehody a poruchy */}
            {(incident.type === 'accident_major' || incident.type === 'breakdown_major' || incident.type === 'theft') && (
              <WorkflowBtn
                label="Odeslat odtah"
                icon="🚛"
                done={!!incident.tow_requested || timelineActions.some(a => a.toLowerCase().includes('dtah'))}
                onClick={async () => {
                  if (!window.confirm('Potvrdit objednání odtahové služby?')) return
                  await supabase.from('sos_incidents').update({ tow_requested: true }).eq('id', incident.id)
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: 'Odtahová služba objednána — motorka bude odtažena do servisu',
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}

            {/* Policie — pro krádeže a nehody */}
            {(incident.type === 'theft' || isAccident) && (
              <WorkflowBtn
                label="Policie kontaktována"
                icon="🚔"
                done={!!incident.police_report_number || timelineActions.some(a => a.toLowerCase().includes('olicie'))}
                onClick={async () => {
                  const num = window.prompt('Zadejte číslo policejního spisu (nebo nechte prázdné):')
                  if (num === null) return
                  const updates = {}
                  if (num.trim()) updates.police_report_number = num.trim()
                  if (Object.keys(updates).length > 0) {
                    await supabase.from('sos_incidents').update(updates).eq('id', incident.id)
                    setPoliceNumber(num.trim())
                  }
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: `Policie ČR kontaktována${num.trim() ? `, číslo spisu: ${num.trim()}` : ''}`,
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}

            {/* Pojišťovna — pro nehody */}
            {isAccident && (() => {
              const insuranceDone = timelineActions.some(a => a.toLowerCase().includes('ojišťovn'))
              const insuranceSkipped = timelineActions.some(a => a.toLowerCase().includes('ojišťovna přeskočen'))
              if (insuranceSkipped) return (
                <WorkflowBtn label="Pojišťovna přeskočena" icon="⏭️" done={true} onClick={() => {}} />
              )
              return (
                <>
                  <WorkflowBtn
                    label="Kontaktovat pojišťovnu"
                    icon="🏦"
                    done={insuranceDone}
                    onClick={async () => {
                      if (!window.confirm('Potvrdit kontaktování pojišťovny?')) return
                      const { data: { user } } = await supabase.auth.getUser()
                      await supabase.from('sos_timeline').insert({
                        incident_id: incident.id,
                        action: 'Pojišťovna kontaktována, hlášena škodná událost',
                        performed_by: user?.email || 'Admin', admin_id: user?.id,
                      })
                      await loadTimelineActions()
                      onRefresh?.()
                    }}
                  />
                  {!insuranceDone && (
                    <WorkflowBtn
                      label="Přeskočit pojišťovnu"
                      icon="⏭️"
                      done={false}
                      onClick={async () => {
                        if (!window.confirm('Přeskočit kontaktování pojišťovny?\n\nTento krok bude přeskočen v postupu řešení.')) return
                        const { data: { user } } = await supabase.auth.getUser()
                        await supabase.from('sos_timeline').insert({
                          incident_id: incident.id,
                          action: 'Pojišťovna přeskočena — není potřeba kontaktovat',
                          performed_by: user?.email || 'Admin', admin_id: user?.id,
                        })
                        await loadTimelineActions()
                        onRefresh?.()
                      }}
                    />
                  )}
                </>
              )
            })()}

            {/* Motorka do servisu — pro těžké typy */}
            {(isMajor || incident.type === 'theft') && !motoInService && moto?.status !== 'maintenance' && (
              <WorkflowBtn
                label="Motorka do servisu"
                icon="🔧"
                done={false}
                onClick={setMotoToService}
              />
            )}
            {(isMajor || incident.type === 'theft') && (motoInService || moto?.status === 'maintenance') && (
              <WorkflowBtn label="V servisu" icon="✅" done={true} onClick={() => {}} />
            )}

            {/* Servis navigace — pro lehké poruchy */}
            {(incident.type === 'breakdown_minor' || incident.type === 'defect_question') && (
              <WorkflowBtn
                label="Navigovat na servis"
                icon="🗺️"
                done={!!incident.nearest_service_name || timelineActions.some(a => a.toLowerCase().includes('servis'))}
                onClick={async () => {
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: 'Zákazník navigován na nejbližší servis',
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}
          </div>

          {/* Číslo policejního spisu — inline input */}
          {(incident.type === 'theft' || isAccident) && (
            <div className="flex items-center gap-2 mt-3">
              <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>
                Číslo PČR spisu:
              </span>
              <input type="text" value={policeNumber} onChange={e => setPoliceNumber(e.target.value)}
                placeholder="KRPX-12345/ČJ-2026"
                onBlur={() => saveField('police_report_number', policeNumber)}
                className="flex-1 rounded-btn text-sm outline-none font-mono"
                style={{ padding: '5px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              />
            </div>
          )}
        </Card>
  )
}
