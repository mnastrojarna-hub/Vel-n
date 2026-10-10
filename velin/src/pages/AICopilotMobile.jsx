import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import useVisualViewport from './messages/useVisualViewport'

// AI Copilot — části jen pro telefon/tablet (< 1024 px). Desktop je nepoužívá.

// Markdown odpovědi AI pro úzký displej: tabulky (| a | b |) jako skutečná tabulka
// s vodorovným posunem uvnitř bubliny (ne syrové řádky se svislítky), nadpisy (#…) tučně.
// Zbytek textu převede původní renderMarkdown (předaný parametrem).
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const inline = s => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/`([^`]+)`/g, '<code style="background:#f1faf7;padding:1px 4px;border-radius:3px;font-size:12px">$1</code>')
const cells = line => line.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim())
const isSep = line => /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(line)

function tableHtml(rows) {
  const [head, ...body] = rows
  const th = head.map(c => `<th style="text-align:left;padding:6px 10px;border-bottom:2px solid #d4e8e0;white-space:nowrap">${inline(c)}</th>`).join('')
  const tr = body.map(r => `<tr>${r.map(c => `<td style="padding:6px 10px;border-bottom:1px solid #eef5f1;white-space:nowrap">${inline(c)}</td>`).join('')}</tr>`).join('')
  return `<div style="overflow-x:auto;-webkit-overflow-scrolling:touch;margin:6px 0;border:1px solid #d4e8e0;border-radius:10px"><table style="border-collapse:collapse;font-size:13px;min-width:100%"><thead style="background:#f1faf7"><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div>`
}

export function renderMarkdownMobile(text, renderMarkdown) {
  if (!text) return ''
  const lines = text.split('\n')
  const parts = []
  let buf = []
  // mezi položkami seznamu žádné <br/> (jinak řídké odrážky)
  const flush = () => { if (buf.length) parts.push(renderMarkdown(buf.join('\n')).replace(/<\/li><br\/>/g, '</li>')); buf = [] }
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*\|/.test(lines[i]) && i + 1 < lines.length && isSep(lines[i + 1])) {
      const rows = [cells(lines[i])]
      i += 2
      while (i < lines.length && /^\s*\|/.test(lines[i])) rows.push(cells(lines[i++]))
      i--
      flush()
      parts.push(tableHtml(rows))
      continue
    }
    const h = lines[i].match(/^\s*#{1,6}\s+(.+)$/)
    if (h) { flush(); parts.push(`<div style="font-weight:800;font-size:15px;margin:8px 0 2px">${inline(h[1])}</div>`); continue }
    buf.push(lines[i])
  }
  flush()
  return parts.join('')
}

// Klávesnice na telefonu/tabletu: dokud se píše a klávesnice je otevřená, karta chatu
// se přesune do pevného překryvu přesně přes viditelnou plochu (visualViewport) —
// pole pro psaní zůstane nad klávesnicí (iOS i Android), stejně jako ve Zprávách.
export function useCopilotKeyboard(enabled) {
  const { height, offsetTop } = useVisualViewport()
  const [focused, setFocused] = useState(false)
  const open = enabled && focused && height > 0 && typeof window !== 'undefined' && height < window.innerHeight - 120
  const style = open ? { position: 'fixed', left: 0, right: 0, top: offsetTop, height, zIndex: 60, borderRadius: 0 } : null
  return { open, style, height, setFocused }
}

// Pole pro psaní: roste s textem (1–5 řádků), kulaté tlačítko Odeslat; tlačítko nebere fokus,
// takže klávesnice po odeslání zůstane otevřená a rozvržení se pod prstem nepřeskládá.
const LINE = 22
const MAX_H = LINE * 5 + 22

export function CopilotComposerMobile({ value, onChange, onSend, sending, setFocused }) {
  const ta = useRef(null)
  const root = useRef(null)
  useLayoutEffect(() => {
    const el = ta.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = Math.min(el.scrollHeight + 2, MAX_H) + 'px'
  }, [value])
  useEffect(() => () => setFocused(false), [setFocused])
  const disabled = sending || !value.trim()
  return (
    <div ref={root} className="p-2 flex gap-2 items-end" style={{ borderTop: '1px solid #d4e8e0', background: '#fff' }}
      onFocus={() => setFocused(true)}
      onBlur={() => requestAnimationFrame(() => setFocused(!!root.current && root.current.contains(document.activeElement)))}>
      <textarea ref={ta} rows={1} value={value} onChange={e => onChange(e.target.value)} placeholder="Napište dotaz nebo příkaz…"
        className="flex-1 min-w-0 text-sm outline-none"
        style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 22, minHeight: 44, maxHeight: MAX_H, lineHeight: `${LINE}px`, resize: 'none', overflowY: 'auto' }}
        onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); onSend() } }} />
      <button type="button" aria-label="Odeslat" title="Odeslat" disabled={disabled}
        onPointerDown={e => e.preventDefault()} onMouseDown={e => e.preventDefault()} onClick={onSend}
        className="shrink-0 cursor-pointer disabled:cursor-not-allowed"
        style={{ width: 44, height: 44, borderRadius: '50%', border: 'none', background: '#74FB71', color: '#1a2e22', fontSize: 18, fontWeight: 800, opacity: disabled ? 0.45 : 1, boxShadow: disabled ? 'none' : '0 4px 16px rgba(116,251,113,.35)' }}>
        {sending ? '…' : '➤'}
      </button>
    </div>
  )
}
