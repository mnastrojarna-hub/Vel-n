import { useState } from 'react'
import { describeSku, SKU_CONVENTION, SKU_RULES } from '../../lib/sku'

function ConventionBox() {
  return (
    <div style={{ minWidth: 280, maxWidth: 360 }}>
      <div className="text-sm font-extrabold mb-1" style={{ color: '#0f1a14' }}>Konvence SKU</div>
      <div className="text-xs mb-2" style={{ color: '#1a2e22', opacity: 0.75 }}>
        Formát <span className="font-mono">kategorie-typ-varianta</span> — malá písmena, číslice, pomlčky.
      </div>
      <div className="flex flex-col gap-1 mb-2">
        {SKU_CONVENTION.map(r => (
          <div key={r.pattern} className="text-xs" style={{ color: '#1a2e22' }}>
            <b>{r.label}:</b> <span className="font-mono">{r.pattern}</span>
            <span style={{ opacity: 0.6 }}> → {r.example}</span>
          </div>
        ))}
      </div>
      <ul className="text-xs list-disc pl-4" style={{ color: '#1a2e22', opacity: 0.75 }}>
        {SKU_RULES.map((r, i) => <li key={i}>{r}</li>)}
      </ul>
    </div>
  )
}

function Popover({ children, onClose }) {
  return (
    <>
      <div className="fixed inset-0 z-40" onClick={onClose} />
      <div className="absolute z-50 rounded-card shadow-card" onClick={e => e.stopPropagation()}
        style={{ top: '100%', left: 0, marginTop: 4, background: '#fff', padding: 14, border: '1px solid #d4e8e0' }}>
        {children}
      </div>
    </>
  )
}

const InfoIcon = ({ onClick }) => (
  <button onClick={onClick} title="Konvence SKU"
    className="inline-flex items-center justify-center cursor-pointer shrink-0"
    style={{ width: 15, height: 15, borderRadius: '50%', border: '1px solid #9bbcad', background: '#eef7f2', color: '#1a8a18', fontSize: 10, fontWeight: 900, lineHeight: 1 }}>
    i
  </button>
)

// SKU buňka s klikací nápovědou (parsovaný význam + konvence).
export default function SkuTag({ sku }) {
  const [open, setOpen] = useState(false)
  if (!sku) return <span style={{ color: '#9ca3af' }}>—</span>
  const desc = describeSku(sku)
  return (
    <span className="relative inline-flex items-center gap-1">
      <span className="font-mono font-bold cursor-pointer" style={{ color: '#0f1a14' }} onClick={() => setOpen(o => !o)} title="Klikni pro význam SKU">{sku}</span>
      <InfoIcon onClick={() => setOpen(o => !o)} />
      {open && (
        <Popover onClose={() => setOpen(false)}>
          {desc && <div className="text-sm font-bold mb-2 pb-2" style={{ color: '#1a8a18', borderBottom: '1px solid #e2eee8' }}>{desc}</div>}
          <ConventionBox />
        </Popover>
      )}
    </span>
  )
}

// Samostatné „i" tlačítko s konvencí (do hlaviček tabulek/formulářů).
export function SkuConventionInfo({ label = 'Konvence SKU' }) {
  const [open, setOpen] = useState(false)
  return (
    <span className="relative inline-flex items-center gap-1">
      <button onClick={() => setOpen(o => !o)} className="text-sm font-bold cursor-pointer rounded-btn inline-flex items-center gap-1"
        style={{ padding: '6px 10px', border: '1px solid #d4e8e0', background: '#fff', color: '#1a2e22' }}>
        <span style={{ color: '#1a8a18' }}>ⓘ</span> {label}
      </button>
      {open && <Popover onClose={() => setOpen(false)}><ConventionBox /></Popover>}
    </span>
  )
}
