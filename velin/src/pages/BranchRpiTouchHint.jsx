import { useState } from 'react'
import { useIsMobile } from '../hooks/useIsMobile'

// ─── Vysvětlivky polí Samoobsluhy na dotykovém zařízení (telefon/tablet < 1024 px) ──────────
// Na PC je vysvětlivka v bublině po najetí myší (`title`). Na dotyku bublina neexistuje — proto u popisku
// tlačítko „i“, které text vysvětlivky rozbalí pod polem. Desktop (≥ 1024 px) se nemění: hook nic nevykreslí.
// Vrací { toggle, body } — toggle = tlačítko (null na desktopu / bez textu), body = rozbalený text (null = zavřeno).
export function useTouchHint(text) {
  const mobile = useIsMobile()
  const [open, setOpen] = useState(false)
  if (!mobile || !text) return { toggle: null, body: null }
  // Cíl prstu 36 × 36 px (záporný okraj → řádek popisku se nezvětší), viditelný kroužek 24 px
  const toggle = (
    <button type="button" aria-label="Vysvětlivka" aria-expanded={open}
      onClick={e => { e.preventDefault(); e.stopPropagation(); setOpen(o => !o) }}
      className="inline-flex items-center justify-center cursor-pointer border-none shrink-0 align-middle"
      style={{ width: 36, height: 36, margin: '-6px -6px', padding: 0, background: 'transparent' }}>
      <span className="inline-flex items-center justify-center rounded-full"
        style={{ width: 24, height: 24, background: open ? '#1a2e22' : '#dbeafe', color: open ? '#74FB71' : '#2563eb', boxShadow: '0 0 0 1px rgba(37,99,235,.35)', fontSize: 13, fontWeight: 800, fontStyle: 'italic', fontFamily: 'Georgia, serif' }}>
        i
      </span>
    </button>
  )
  const body = open
    ? <span className="block text-[12px] rounded-lg" style={{ background: '#eff6ff', color: '#1d4ed8', padding: '6px 8px', fontWeight: 500, lineHeight: 1.4 }}>{text}</span>
    : null
  return { toggle, body }
}

// Rozbalená vysvětlivka jako samostatná položka flex řádku (přes celou šířku) — null když je zavřená
export const HintRow = ({ body }) => (body ? <span className="basis-full w-full">{body}</span> : null)

// Více vysvětlivek pod JEDNÍM „i“ — řada tlačítek/čipů, kde má na PC každý prvek vlastní bublinu `title`
// (příkazy karty jednotky, dlaždice zóny, řádek výstupu…). Jedno „i“ na řadu místo „i“ u každého tlačítka.
// `items` = [[popisek, text], …]; položky bez textu (false/null) se vynechají, bez položek „i“ není.
export function useTouchHintList(items) {
  const list = (items || []).filter(it => it && it[1])
  return useTouchHint(list.length ? (
    <>{list.map(([label, text], i) => <span key={i} className={`block${i ? ' mt-1' : ''}`}><b>{label}</b> — {text}</span>)}</>
  ) : null)
}

// Totéž jako prvek flex-wrap řádku: „i“ + rozbalený seznam hned za ním (přes celou šířku). Desktop: nic.
export function HintList({ items }) {
  const h = useTouchHintList(items)
  return <>{h.toggle}<HintRow body={h.body} /></>
}

// Blok/řádek s vysvětlivkou v `title` (stavové řádky karty jednotky, dlaždice zóny…).
// Desktop: přesně <Tag className style title>{children}</Tag>. Dotyk: na konci „i“ a pod ním rozbalený text.
// `hint={null}` = na dotyku bez „i“ (např. technická vysvětlivka mimo servisní režim).
export function HintBlock({ as: Tag = 'div', className, style, title, hint = title, children }) {
  const h = useTouchHint(hint)
  return (
    <Tag className={className} style={style} title={title}>
      {children}
      {h.toggle && <> {h.toggle}</>}
      {h.body && <span className="block basis-full w-full mt-1">{h.body}</span>}
    </Tag>
  )
}

// <label> formuláře s vlastním popiskem (vysvětlivka v `hint` = title popisku na PC).
// Desktop: <label className style><span … title>{text}</span>{children}</label>; dotyk: „i“ u popisku,
// rozbalený text pod polem a pole přes celý řádek (basis-full), ať se text nemačká do úzkého sloupce.
export function HintedLabel({ className = '', style, hint, text, textStyle = { color: '#6b8c7a' }, children }) {
  const h = useTouchHint(hint)
  const span = <span className="text-[11px] font-bold" style={textStyle} title={hint}>{text}</span>
  return (
    <label className={`${className}${h.body ? ' basis-full' : ''}`} style={style}>
      {h.toggle ? <span className="flex items-center gap-1.5">{span}{h.toggle}</span> : span}
      {children}
      {h.body}
    </label>
  )
}
