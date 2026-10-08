import { useMediaQuery } from '../../hooks/useIsMobile'
import Button from '../../components/ui/Button'

// Průvodce novou kampaní na telefonu/tabletu: kompaktní ukazatel kroků
// a lišta tlačítek přilepená ke spodní hraně okna (Zpět / Další / Odeslat…).
const STEPS = ['Základní info', 'Příjemci', 'Náhled', 'Odeslání']

export function CampaignsMobileStepper({ step }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${STEPS.length}, minmax(0, 1fr))`, marginBottom: 18 }}>
      {STEPS.map((label, i) => {
        const num = i + 1
        const isActive = step === num
        const isDone = step > num
        return (
          <div key={num} className="relative flex flex-col items-center" style={{ minWidth: 0 }}>
            {i > 0 && (
              <div aria-hidden style={{ position: 'absolute', top: 13, left: '-50%', right: '50%', height: 2, background: step >= num ? '#1a8a18' : '#d1d5db' }} />
            )}
            <div
              className="relative flex items-center justify-center font-bold"
              style={{
                width: 28, height: 28, borderRadius: '50%', fontSize: 13, zIndex: 1,
                background: isDone ? '#1a8a18' : isActive ? '#74FB71' : '#f3f4f6',
                color: isDone ? '#fff' : isActive ? '#0f1a14' : '#9ca3af',
                border: isActive ? '2px solid #1a8a18' : '2px solid transparent',
              }}
            >
              {isDone ? '✓' : num}
            </div>
            <span
              className="font-bold text-center"
              style={{ fontSize: 11, lineHeight: 1.25, marginTop: 4, padding: '0 2px', color: isActive ? '#0f1a14' : isDone ? '#1a8a18' : '#9ca3af' }}
            >
              {label}
            </span>
          </div>
        )
      })}
    </div>
  )
}

const BTN = { minHeight: 44, width: '100%', justifyContent: 'center', padding: '10px 14px', textAlign: 'center' }

export function CampaignsMobileFooter({ step, setStep, canNext, step4Valid, sending, scheduleMode, onSubmit }) {
  // Odsazení okna Modal: p-4 na telefonu, sm:p-7 od 640 px — lišta ho přetahuje až k okraji.
  const pad = useMediaQuery('(min-width: 640px)') ? 28 : 16
  const back = step > 1 && <Button onClick={() => setStep(s => s - 1)} style={BTN}>← Zpět</Button>

  return (
    <div
      style={{
        position: 'sticky', bottom: -pad, zIndex: 2, margin: `20px -${pad}px -${pad}px`, padding: `10px ${pad}px 12px`,
        background: '#fff', borderTop: '1px solid #e5e7eb', display: 'flex', flexDirection: 'column', gap: 8,
      }}
    >
      {step < 4 ? (
        <div style={{ display: 'grid', gridTemplateColumns: back ? 'minmax(0, 1fr) minmax(0, 1fr)' : 'minmax(0, 1fr)', gap: 8 }}>
          {back}
          <Button green onClick={() => setStep(s => s + 1)} disabled={!canNext} style={BTN}>Další →</Button>
        </div>
      ) : (
        <>
          <Button green onClick={() => onSubmit(false)} disabled={!step4Valid || sending} style={BTN}>
            {sending ? 'Odesílám…' : scheduleMode === 'scheduled' ? 'Naplánovat' : 'Odeslat'}
          </Button>
          <div style={{ display: 'grid', gridTemplateColumns: 'auto minmax(0, 1fr)', gap: 8 }}>
            {back}
            <Button onClick={() => onSubmit(true)} disabled={sending} style={{ ...BTN, letterSpacing: '0.02em' }}>
              {sending ? 'Ukládám…' : 'Uložit jako koncept'}
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
