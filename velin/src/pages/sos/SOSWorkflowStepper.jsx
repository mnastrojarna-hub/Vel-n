/**
 * SOSWorkflowStepper — vizuální průvodce kroky řešení SOS incidentu.
 * Zobrazuje kroky specifické pro daný typ incidentu a zvýrazňuje aktuální stav.
 */

export const WORKFLOWS = {
  theft: {
    label: 'Krádež motorky',
    steps: [
      { id: 'ack', label: 'Potvrdit příjem', check: i => i.status !== 'reported' },
      { id: 'start', label: 'Začít řešit', check: i => ['in_progress', 'resolved', 'closed'].includes(i.status) },
      { id: 'contact', label: 'Kontaktovat zákazníka', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva odeslána') },
      { id: 'police', label: 'Policie kontaktována', check: i => !!i.police_report_number || hasTimeline(i, 'olicie') },
      { id: 'service', label: 'Motorka do servisu', check: i => i._motoInService },
      { id: 'insurance', label: 'Kontaktovat pojišťovnu', check: i => hasTimeline(i, 'ojišťovn'), skip: i => hasTimeline(i, 'ojišťovna přeskočen') },
      { id: 'decision', label: 'Rozhodnutí o náhradě', check: i => !!i.customer_decision },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  accident_minor: {
    label: 'Lehká nehoda (pojízdná)',
    steps: [
      { id: 'ack', label: 'Potvrdit příjem', check: i => i.status !== 'reported' },
      { id: 'start', label: 'Začít řešit', check: i => ['in_progress', 'resolved', 'closed'].includes(i.status) },
      { id: 'contact', label: 'Kontaktovat zákazníka', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva odeslána') },
      { id: 'fault', label: 'Určit zavinění', check: i => i.customer_fault !== null && i.customer_fault !== undefined },
      { id: 'insurance', label: 'Kontaktovat pojišťovnu', check: i => hasTimeline(i, 'ojišťovn'), skip: i => hasTimeline(i, 'ojišťovna přeskočen') },
      { id: 'decision', label: 'Rozhodnutí zákazníka', check: i => !!i.customer_decision },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  accident_major: {
    label: 'Závažná nehoda (nepojízdná)',
    steps: [
      { id: 'ack', label: 'Potvrdit příjem', check: i => i.status !== 'reported' },
      { id: 'start', label: 'Začít řešit', check: i => ['in_progress', 'resolved', 'closed'].includes(i.status) },
      { id: 'contact', label: 'Kontaktovat zákazníka', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva odeslána') },
      { id: 'fault', label: 'Určit zavinění', check: i => i.customer_fault !== null && i.customer_fault !== undefined },
      { id: 'tow', label: 'Odeslat odtah', check: i => !!i.tow_requested || hasTimeline(i, 'dtah') || i.customer_decision === 'replacement_moto', skip: i => i.customer_decision === 'replacement_moto' },
      { id: 'insurance', label: 'Kontaktovat pojišťovnu', check: i => hasTimeline(i, 'ojišťovn'), skip: i => hasTimeline(i, 'ojišťovna přeskočen') },
      { id: 'service', label: 'Motorka do servisu', check: i => i._motoInService },
      { id: 'decision', label: 'Rozhodnutí zákazníka', check: i => !!i.customer_decision },
      { id: 'replacement', label: 'Náhradní motorka', check: i => i.customer_decision === 'end_ride' || ['approved', 'dispatched', 'delivered'].includes(i.replacement_status), skip: i => i.customer_decision === 'end_ride' },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  breakdown_minor: {
    label: 'Lehká porucha (pojízdná)',
    steps: [
      { id: 'ack', label: 'Potvrzeno (auto)', check: i => i.status !== 'reported' },
      { id: 'service_nav', label: 'Navigovat na servis', check: i => !!i.nearest_service_name || hasTimeline(i, 'servis') },
      { id: 'note', label: 'Zapsat poznámku', check: i => !!i.admin_notes || hasTimeline(i, 'admin_note') },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  breakdown_major: {
    label: 'Těžká porucha (nepojízdná)',
    steps: [
      { id: 'ack', label: 'Potvrdit příjem', check: i => i.status !== 'reported' },
      { id: 'start', label: 'Začít řešit', check: i => ['in_progress', 'resolved', 'closed'].includes(i.status) },
      { id: 'contact', label: 'Kontaktovat zákazníka', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva odeslána') },
      { id: 'fault_auto', label: 'Zavinění: MotoGo (porucha)', check: () => true },
      { id: 'tow', label: 'Odeslat odtah', check: i => !!i.tow_requested || hasTimeline(i, 'dtah') || i.customer_decision === 'replacement_moto', skip: i => i.customer_decision === 'replacement_moto' },
      { id: 'service', label: 'Motorka do servisu', check: i => i._motoInService },
      { id: 'decision', label: 'Rozhodnutí zákazníka', check: i => !!i.customer_decision },
      { id: 'replacement', label: 'Náhradní moto (zdarma)', check: i => i.customer_decision === 'end_ride' || ['approved', 'dispatched', 'delivered'].includes(i.replacement_status), skip: i => i.customer_decision === 'end_ride' },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  defect_question: {
    label: 'Dotaz na závadu',
    steps: [
      { id: 'ack', label: 'Potvrzeno (auto)', check: i => i.status !== 'reported' },
      { id: 'contact', label: 'Odpovědět zákazníkovi', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva') },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  location_share: {
    label: 'Sdílení polohy',
    steps: [
      { id: 'ack', label: 'Potvrzeno (auto)', check: i => i.status !== 'reported' },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
  other: {
    label: 'Jiný problém',
    steps: [
      { id: 'ack', label: 'Potvrzeno (auto)', check: i => i.status !== 'reported' },
      { id: 'contact', label: 'Kontaktovat zákazníka', check: i => hasTimeline(i, 'kontaktován') || hasTimeline(i, 'Zpráva odeslána') },
      { id: 'resolve', label: 'Vyřešit incident', check: i => ['resolved', 'closed'].includes(i.status) },
    ],
  },
}

export function hasTimeline(incident, keyword) {
  return (incident._timelineActions || []).some(a => a.toLowerCase().includes(keyword.toLowerCase()))
}

export default function SOSWorkflowStepper({ incident, timelineActions, motoInService }) {
  const workflow = WORKFLOWS[incident?.type]
  if (!workflow) return null

  // Enrich incident with helper data for checks
  const enriched = {
    ...incident,
    _timelineActions: timelineActions || [],
    _motoInService: motoInService || false,
  }

  const steps = workflow.steps.filter(s => !s.skip || !s.skip(enriched))
  const completedCount = steps.filter(s => s.check(enriched)).length
  const totalCount = steps.length
  const isResolved = ['resolved', 'closed'].includes(incident.status)

  // Find current step (first incomplete)
  let currentIdx = steps.findIndex(s => !s.check(enriched))
  if (currentIdx === -1) currentIdx = steps.length // all done

  return (
    <div className="rounded-card" style={{
      padding: '14px 16px',
      background: isResolved ? '#f0fdf4' : '#fffbeb',
      border: isResolved ? '2px solid #86efac' : '2px solid #fbbf24',
    }}>
      <div className="flex items-center justify-between mb-3">
        <span className="text-[10px] font-extrabold uppercase tracking-wider" style={{
          color: isResolved ? '#1a8a18' : '#b45309',
        }}>
          Postup řešení: {workflow.label}
        </span>
        <span className="text-[10px] font-extrabold uppercase tracking-wider" style={{
          color: isResolved ? '#1a8a18' : '#b45309',
        }}>
          {completedCount}/{totalCount}
        </span>
      </div>

      {/* Progress bar */}
      <div className="rounded-full mb-3" style={{ height: 4, background: '#e5e7eb' }}>
        <div className="rounded-full transition-all" style={{
          height: 4,
          width: `${totalCount > 0 ? (completedCount / totalCount) * 100 : 0}%`,
          background: isResolved ? '#22c55e' : '#f59e0b',
        }} />
      </div>

      {/* Steps */}
      <div className="space-y-0">
        {steps.map((step, idx) => {
          const done = step.check(enriched)
          const isCurrent = idx === currentIdx
          return (
            <div key={step.id} className="flex items-start gap-2" style={{ padding: '4px 0' }}>
              {/* Step indicator */}
              <div className="flex flex-col items-center" style={{ minWidth: 20 }}>
                <div className="flex items-center justify-center rounded-full" style={{
                  width: 20, height: 20,
                  background: done ? '#22c55e' : isCurrent ? '#f59e0b' : '#e5e7eb',
                  color: done ? '#fff' : isCurrent ? '#fff' : '#9ca3af',
                  fontSize: 10, fontWeight: 800,
                }}>
                  {done ? '✓' : idx + 1}
                </div>
                {idx < steps.length - 1 && (
                  <div style={{
                    width: 2, height: 12,
                    background: done ? '#22c55e' : '#e5e7eb',
                  }} />
                )}
              </div>
              {/* Step label */}
              <span className="text-sm" style={{
                fontWeight: isCurrent ? 800 : done ? 600 : 400,
                color: done ? '#15803d' : isCurrent ? '#92400e' : '#9ca3af',
                textDecoration: done ? 'line-through' : 'none',
                paddingTop: 1,
              }}>
                {step.label}
                {isCurrent && !isResolved && (
                  <span className="ml-1 text-[9px] font-extrabold uppercase tracking-wide px-1.5 py-0.5 rounded"
                    style={{ background: '#fef3c7', color: '#b45309' }}>
                    aktuální
                  </span>
                )}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
