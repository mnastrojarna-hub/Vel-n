import { useEffect, useRef, useState } from 'react'
import useVisualViewport from './useVisualViewport'
import ChatMobileMessages from './ChatMobileBubble'
import ChatMobileComposer from './ChatMobileComposer'

// Otevřená konverzace na mobilu/tabletu (≤ 1023 px): celoobrazovkový překryv jako v messengeru.
// Výška = vizuální viewport, takže pole pro odpověď zůstává nad klávesnicí. Logika zůstává v ChatPanel.

const FOCUSABLE = 'button:not([disabled]),select:not([disabled]),textarea:not([disabled]),input:not([disabled]),a[href],[tabindex]:not([tabindex="-1"])'

// „Zpět“ musí být nepřehlédnutelné: pilulka s výrazným šípem a textem (ne jen tenký znak).
const BACK_BTN = {
  height: 44,
  padding: '0 14px 0 8px',
  borderRadius: 999,
  background: '#f1faf7',
  border: '1px solid #d4e8e0',
  color: '#1a2e22',
  fontSize: 15,
  fontWeight: 800,
  cursor: 'pointer',
  flexShrink: 0,
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
}

const ICON_BTN = {
  width: 44,
  height: 44,
  borderRadius: 12,
  border: 'none',
  color: '#1a2e22',
  cursor: 'pointer',
  flexShrink: 0,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
}

export default function ChatMobilePanel({
  thread, messages, loading, admins, templates, currentAdminId, scrollRef,
  reply, setReply, sending, aiLoading,
  onSend, onToggleStatus, onAssign, onApplyTemplate, onAiSuggest, onAiAction, onBack, aiEdits,
}) {
  const { height, offsetTop } = useVisualViewport()
  const [showActions, setShowActions] = useState(false)
  const dialogRef = useRef(null)
  const contentRef = useRef(null)
  const atBottom = useRef(true)

  const isClosed = thread.status === 'closed'
  const name = thread.profiles?.full_name || 'Zákazník'
  const email = thread.profiles?.email

  // Fokus do překryvu a Tab jen uvnitř — seznam, záložky a menu pod ním jsou skryté a nesmí jít ovládat.
  // Pole pro odpověď se nefokusuje (na telefonu by vyskočila klávesnice). Po zavření se fokus vrátí.
  useEffect(() => {
    const prev = document.activeElement
    const dlg = dialogRef.current
    dlg?.focus({ preventScroll: true })
    const onFocusIn = e => { if (dlg && !dlg.contains(e.target)) dlg.focus({ preventScroll: true }) }
    document.addEventListener('focusin', onFocusIn)
    return () => {
      document.removeEventListener('focusin', onFocusIn)
      if (prev && prev.isConnected && typeof prev.focus === 'function') prev.focus({ preventScroll: true })
    }
  }, [])

  function onKeyDown(e) {
    if (e.key !== 'Tab') return
    const f = [...dialogRef.current.querySelectorAll(FOCUSABLE)].filter(el => el.offsetParent !== null)
    if (!f.length) return
    const first = f[0], last = f[f.length - 1]
    if (e.shiftKey && (document.activeElement === first || document.activeElement === dialogRef.current)) { e.preventDefault(); last.focus() }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
  }

  // Kdo byl dole, zůstane dole i po otevření klávesnice, růstu pole pro odpověď nebo AI panelu.
  // Výjimka: úprava AI návrhu (textarea v seznamu) — po změně výšky seznamu (klávesnice) ukaž začátek pole.
  useEffect(() => {
    const el = scrollRef.current
    if (!el || typeof ResizeObserver === 'undefined') return undefined
    let lastH = el.clientHeight
    const ro = new ResizeObserver(() => {
      const listResized = el.clientHeight !== lastH
      lastH = el.clientHeight
      const a = document.activeElement
      if (a && a.tagName === 'TEXTAREA' && el.contains(a)) {
        if (listResized) {
          if (atBottom.current) el.scrollTop = el.scrollHeight // vejde-li se, zůstanou vidět i tlačítka pod polem
          const r = a.getBoundingClientRect()
          const s = el.getBoundingClientRect()
          // Začátek pole pod hlavičku (i když je pole vyšší než seznam), jinak celé pole do viditelné části
          if (r.top < s.top + 8 || r.height > s.height - 16) el.scrollTop += r.top - s.top - 8
          else if (r.bottom > s.bottom - 8) el.scrollTop += r.bottom - s.bottom + 8
        }
        return // při psaní drží kurzor na očích prohlížeč sám
      }
      if (atBottom.current) el.scrollTop = el.scrollHeight
    })
    ro.observe(el)
    if (contentRef.current) ro.observe(contentRef.current)
    return () => ro.disconnect()
  }, [scrollRef])

  function onScroll(e) {
    const el = e.currentTarget
    atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48
  }

  return (
    <div
      ref={dialogRef}
      role="dialog"
      aria-modal="true"
      aria-label={`Konverzace – ${name}`}
      tabIndex={-1}
      onKeyDown={onKeyDown}
      className="flex flex-col"
      style={{
        outline: 'none',
        position: 'fixed',
        left: 0,
        right: 0,
        top: offsetTop,
        height: height || '100%',
        zIndex: 60,
        background: '#fff',
      }}
    >
      {/* Hlavička — pevně nahoře; tah prstem po ní neroluje stránku pod překryvem (touchAction none) */}
      <div className="flex items-center shrink-0" style={{ minHeight: 56, gap: 8, padding: '6px 8px', borderBottom: '1px solid #d4e8e0', background: '#fff', touchAction: 'none' }}>
        <button type="button" aria-label="Zpět na konverzace" onClick={onBack} style={BACK_BTN}>
          <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 18l-6-6 6-6" />
          </svg>
          Zpět
        </button>
        <div style={{ flex: '1 1 auto', minWidth: 0 }}>
          <div className="truncate" style={{ fontSize: 15, fontWeight: 800, color: '#0f1a14' }}>{name}</div>
          <div className="truncate" style={{ fontSize: 12, color: '#1a2e22' }}>{thread.subject || email || ''}</div>
        </div>
        <button
          type="button"
          aria-label="Akce konverzace"
          aria-expanded={showActions}
          onClick={() => setShowActions(v => !v)}
          style={{ ...ICON_BTN, background: showActions ? '#e8fee7' : '#f1faf7', border: showActions ? '1px solid #74FB71' : '1px solid transparent', fontSize: 22, fontWeight: 800 }}
        >
          ⋯
        </button>
      </div>

      {/* Akce konverzace (přiřazení, uzavření, kontakt) */}
      {showActions && (
        <div className="shrink-0" style={{ padding: 12, borderBottom: '1px solid #d4e8e0', background: '#f8fcfa', display: 'flex', flexDirection: 'column', gap: 10, maxHeight: '45%', overflowY: 'auto' }}>
          {(email || thread.subject) && (
            <div style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.45 }}>
              {email && <div style={{ overflowWrap: 'anywhere' }}><strong>E-mail:</strong> {email}</div>}
              {thread.subject && <div style={{ overflowWrap: 'anywhere' }}><strong>Předmět:</strong> {thread.subject}</div>}
            </div>
          )}
          {/* Telefon: pod sebou přes celou šířku; tablet: vedle sebe */}
          <div className="flex flex-wrap items-end" style={{ gap: 10 }}>
            <label className="block" style={{ flex: '1 1 240px', minWidth: 0 }}>
              <span className="block font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#1a2e22', marginBottom: 4 }}>Přiřazený admin</span>
              <select
                value={thread.assigned_admin || ''}
                onChange={e => onAssign(e.target.value)}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ minHeight: 44, padding: '8px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}
              >
                <option value="">Nepřiřazeno</option>
                {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
              </select>
            </label>
            <button
              type="button"
              onClick={onToggleStatus}
              className="font-bold cursor-pointer border-none rounded-btn"
              style={{ flex: '1 1 160px', minHeight: 44, fontSize: 14, background: isClosed ? '#dcfce7' : '#fee2e2', color: isClosed ? '#1a8a18' : '#991b1b' }}
            >
              {isClosed ? 'Znovu otevřít' : 'Uzavřít'}
            </button>
          </div>
        </div>
      )}

      {isClosed && (
        <div className="text-center text-sm font-bold py-2 shrink-0" style={{ background: '#f3f4f6', color: '#1a2e22' }}>
          Konverzace je uzavřena
        </div>
      )}

      {/* Zprávy */}
      <div
        ref={scrollRef}
        data-mg-chat-list=""
        onScroll={onScroll}
        style={{ flex: '1 1 auto', minHeight: 0, overflowY: 'auto', overscrollBehavior: 'contain', WebkitOverflowScrolling: 'touch', background: '#f8fcfa' }}
      >
        <div ref={contentRef} className="flex flex-col" style={{ padding: 12, gap: 8 }}>
          {loading && messages.length === 0 ? (
            <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
          ) : messages.length === 0 ? (
            <div className="text-center" style={{ padding: '32px 8px', fontSize: 14, color: '#1a2e22' }}>Zatím žádné zprávy</div>
          ) : (
            <ChatMobileMessages messages={messages} threadId={thread.id} currentAdminId={currentAdminId} onAiAction={onAiAction} aiEdits={aiEdits} />
          )}
        </div>
      </div>

      <ChatMobileComposer
        reply={reply}
        setReply={setReply}
        onSend={onSend}
        sending={sending}
        isClosed={isClosed}
        templates={templates}
        onApplyTemplate={onApplyTemplate}
        onAiSuggest={onAiSuggest}
        aiLoading={aiLoading}
        aiDisabled={messages.length === 0}
        viewportHeight={height}
        actionsOpen={showActions}
      />
    </div>
  )
}
