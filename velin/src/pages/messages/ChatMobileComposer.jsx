import { useLayoutEffect, useRef } from 'react'

// Pole pro odpověď v mobilním chatu: šablona + AI návrh v kompaktní řadě,
// rostoucí textarea (1–6 řádků) a kulaté tlačítko Odeslat.
// Enter: s klávesnicí a myší (užší okno desktopu) odesílá jako v rozděleném zobrazení (Shift+Enter = řádek);
// na dotykovém zařízení dělá nový řádek a odesílá se tlačítkem.
// Nízký viewport (telefon na šířku s klávesnicí): šablona/AI jako ikony vedle pole a výška pole
// omezená tak, aby Odeslat i kus konverzace zůstaly vidět.

const LINE = 22
const MAX_LINES = 6
const PAD_Y = 10
const MIN_FIELD = LINE + PAD_Y * 2 + 2
const COMPACT_BELOW = 300 // px výšky vizuálního viewportu (telefon na šířku s klávesnicí; na výšku zůstávají pilulky)
const MIN_MESSAGES = 48 // px seznamu zpráv, které pole nesmí zabrat

const roundIcon = {
  width: 44,
  height: 44,
  borderRadius: '50%',
  fontSize: 18,
  flexShrink: 0,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
}

const pill = {
  minHeight: 40,
  padding: '0 14px',
  borderRadius: 999,
  fontSize: 13,
  fontWeight: 700,
  whiteSpace: 'nowrap',
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
}

export default function ChatMobileComposer({
  reply, setReply, onSend, sending, isClosed,
  templates, onApplyTemplate, onAiSuggest, aiLoading, aiDisabled,
  viewportHeight = 0, actionsOpen = false,
}) {
  const rootRef = useRef(null)
  const taRef = useRef(null)
  const compact = viewportHeight > 0 && viewportHeight < COMPACT_BELOW

  // Výška textarey podle obsahu (1 až MAX_LINES řádků, pak se posouvá uvnitř), ale nejvýš tolik,
  // kolik zbývá v překryvu po hlavičce, pruzích a MIN_MESSAGES px konverzace.
  useLayoutEffect(() => {
    const ta = taRef.current
    const root = rootRef.current
    if (!ta || !root) return
    ta.style.height = 'auto'
    let max = LINE * MAX_LINES + PAD_Y * 2 + 2
    const dlg = root.parentElement
    if (dlg) {
      let others = 0
      for (const ch of dlg.children) {
        if (ch !== root && !ch.hasAttribute('data-mg-chat-list')) others += ch.offsetHeight
      }
      const chrome = root.offsetHeight - ta.offsetHeight
      const room = dlg.clientHeight - others - chrome - MIN_MESSAGES
      max = Math.max(MIN_FIELD, Math.min(max, room))
    }
    const h = Math.min(ta.scrollHeight + 2, max)
    ta.style.height = `${h}px`
    ta.style.overflowY = ta.scrollHeight + 2 > max ? 'auto' : 'hidden'
  }, [reply, isClosed, viewportHeight, compact, actionsOpen])

  const canSend = !sending && !!reply.trim()

  function onKeyDown(e) {
    if (e.key !== 'Enter' || e.shiftKey || e.nativeEvent.isComposing || e.keyCode === 229) return
    if (typeof window.matchMedia === 'function' && window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
      e.preventDefault()
      onSend()
    }
  }

  const templatePicker = (children, style) => (
    // Nativní výběr (neviditelný) přes „pilulku“/ikonu — na telefonu otevře systémový seznam šablon.
    <label className="relative cursor-pointer" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', flexShrink: 0, ...style }}>
      {children}
      <select
        aria-label="Použít šablonu"
        value=""
        onChange={e => {
          const tpl = templates.find(t => t.id === e.target.value)
          if (tpl) onApplyTemplate(tpl)
        }}
        className="cursor-pointer"
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: 0 }}
      >
        <option value="">— Použít šablonu —</option>
        {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
      </select>
    </label>
  )

  const aiStyle = {
    border: '1px solid #bfdbfe',
    background: aiLoading ? '#e5e7eb' : '#eff6ff',
    color: '#2563eb',
    opacity: aiDisabled && !aiLoading ? 0.5 : 1,
  }

  return (
    <div
      ref={rootRef}
      className="shrink-0"
      style={{
        borderTop: '1px solid #d4e8e0',
        background: '#fff',
        padding: '8px 10px',
        paddingBottom: 'max(8px, env(safe-area-inset-bottom))',
      }}
    >
      {!compact && (
        <div className="flex items-center" style={{ gap: 8, marginBottom: 8, minWidth: 0 }}>
          {templates.length > 0 && templatePicker(<span aria-hidden="true">📋 Šablona…</span>, pill)}
          <button
            type="button"
            onClick={onAiSuggest}
            disabled={aiLoading || aiDisabled}
            className="cursor-pointer disabled:cursor-not-allowed"
            style={{ ...pill, ...aiStyle }}
          >
            {aiLoading ? 'AI přemýšlí…' : '🤖 AI návrh'}
          </button>
        </div>
      )}

      <div className="flex items-end" style={{ gap: 8 }}>
        {compact && templates.length > 0 && templatePicker(<span aria-hidden="true">📋</span>, roundIcon)}
        {compact && (
          <button
            type="button"
            aria-label={aiLoading ? 'AI přemýšlí…' : 'AI návrh odpovědi'}
            title="AI návrh odpovědi"
            onClick={onAiSuggest}
            disabled={aiLoading || aiDisabled}
            className="cursor-pointer disabled:cursor-not-allowed"
            style={{ ...roundIcon, ...aiStyle }}
          >
            {aiLoading ? '…' : '🤖'}
          </button>
        )}
        <textarea
          ref={taRef}
          rows={1}
          value={reply}
          onChange={e => setReply(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={isClosed ? 'Odpovědí se konverzace znovu otevře…' : 'Napište odpověď…'}
          aria-label="Odpověď zákazníkovi"
          className="outline-none"
          style={{
            flex: '1 1 auto',
            minWidth: 0,
            fontSize: 16,
            lineHeight: `${LINE}px`,
            padding: `${PAD_Y}px 14px`,
            borderRadius: 22,
            background: '#f1faf7',
            border: '1px solid #d4e8e0',
            color: '#0f1a14',
            resize: 'none',
            overflowY: 'hidden',
            fontFamily: 'inherit',
          }}
        />
        <button
          type="button"
          aria-label="Odeslat"
          onClick={onSend}
          // Klepnutí neodebere fokus z textarey → klávesnice zůstane otevřená.
          onMouseDown={e => e.preventDefault()}
          disabled={!canSend}
          className="shrink-0 flex items-center justify-center cursor-pointer disabled:cursor-not-allowed"
          style={{
            width: 44,
            height: 44,
            borderRadius: '50%',
            border: 'none',
            background: '#74FB71',
            color: '#1a2e22',
            fontSize: 18,
            boxShadow: canSend ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            opacity: canSend ? 1 : 0.45,
          }}
        >
          {sending ? '…' : '➤'}
        </button>
      </div>
    </div>
  )
}
