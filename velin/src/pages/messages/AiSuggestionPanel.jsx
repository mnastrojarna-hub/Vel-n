import { useState } from 'react'
import { supabase } from '../../lib/supabase'

const CONFIDENCE_STYLES = {
  high:   { bg: '#dcfce7', border: '#86efac', text: '#166534', label: 'high' },
  medium: { bg: '#fef3c7', border: '#fbbf24', text: '#92400e', label: 'medium' },
  low:    { bg: '#fee2e2', border: '#fca5a5', text: '#991b1b', label: 'low' },
}

const STATUS_LABELS = {
  pending:   'AI návrh — čeká na schválení',
  approved:  'Schváleno (čeká na odeslání)',
  edited:    'Upraveno adminem',
  rejected:  'Zamítnuto',
  sent:      'Odesláno zákazníkovi',
  auto_sent: 'Automaticky odesláno',
  failed:    'AI generování selhalo',
}

/**
 * Panel s AI návrhem pod inbound zprávou.
 * Stavy:
 *  - žádný návrh: tlačítko "Navrhnout odpověď" (volá edge fn ai-customer-messages-suggest)
 *  - pending: zobrazí návrh + Schválit / Upravit / Zamítnout / Vygenerovat znovu
 *  - approved/edited/sent/auto_sent: read-only badge s textem (ai_final_reply nebo ai_suggested_reply)
 *  - rejected: badge "Zamítnuto"
 *  - failed: badge "Chyba" + ai_error + tlačítko "Zkusit znovu"
 */
export default function AiSuggestionPanel({ message, threadId, currentAdminId, onApprovedSent }) {
  const [editing, setEditing] = useState(false)
  const [editedText, setEditedText] = useState(message.ai_suggested_reply || '')
  const [busy, setBusy] = useState('')

  const status = message.ai_suggestion_status
  const reply = message.ai_suggested_reply
  const final = message.ai_final_reply
  const conf = message.ai_confidence
  const note = message.ai_admin_note

  // Stav 1: žádný AI návrh / failed → tlačítko Navrhnout / Zkusit znovu
  if (!status || status === 'failed') {
    return (
      <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <button
          onClick={async () => {
            setBusy('request')
            try {
              const { error } = await supabase.functions.invoke('ai-customer-messages-suggest', {
                body: { message_id: message.id },
              })
              if (error) throw error
            } catch (e) { console.error('[ai-cm-suggest]', e) }
            setBusy('')
          }}
          disabled={busy === 'request'}
          style={{
            padding: '4px 10px', fontSize: 11, fontWeight: 700, borderRadius: 6, cursor: 'pointer',
            background: busy === 'request' ? '#e5e7eb' : '#eff6ff',
            color: '#1e40af', border: '1px solid #bfdbfe',
          }}
        >
          {busy === 'request' ? 'Posílám…' : (status === 'failed' ? '↻ Zkusit AI návrh znovu' : '🤖 Navrhnout odpověď přes AI')}
        </button>
        {status === 'failed' && message.ai_error && (
          <span style={{ fontSize: 10, color: '#991b1b' }}>Chyba: {message.ai_error}</span>
        )}
      </div>
    )
  }

  // Stav 2: pending → schvalovací box
  if (status === 'pending') {
    const cs = CONFIDENCE_STYLES[conf] || CONFIDENCE_STYLES.medium
    return (
      <div style={{
        marginTop: 8, padding: 10, borderRadius: 8,
        background: '#f8fafc', border: '1px dashed #94a3b8',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 10, fontWeight: 800, color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            🤖 AI návrh
          </span>
          <span style={{ fontSize: 9, padding: '1px 6px', borderRadius: 4, background: cs.bg, border: `1px solid ${cs.border}`, color: cs.text, fontWeight: 700 }}>
            {cs.label}
          </span>
          {message.ai_suggested_at && (
            <span style={{ fontSize: 10, color: '#64748b' }}>
              {new Date(message.ai_suggested_at).toLocaleString('cs-CZ')}
            </span>
          )}
        </div>

        {note && (
          <div style={{ fontSize: 10, color: '#92400e', background: '#fffbeb', padding: '4px 8px', borderRadius: 4, marginBottom: 6, lineHeight: 1.4 }}>
            <strong>Pozor:</strong> {note}
          </div>
        )}

        {editing ? (
          <textarea
            value={editedText}
            onChange={e => setEditedText(e.target.value)}
            rows={Math.max(3, Math.min(8, (editedText.match(/\n/g) || []).length + 2))}
            style={{
              width: '100%', fontSize: 12, padding: '6px 8px', borderRadius: 6,
              border: '1px solid #cbd5e1', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.4,
              marginBottom: 6, background: '#fff',
            }}
          />
        ) : (
          <div style={{ fontSize: 12, color: '#0f172a', padding: '6px 8px', borderRadius: 6, background: '#fff', border: '1px solid #e2e8f0', whiteSpace: 'pre-wrap', lineHeight: 1.5, marginBottom: 6 }}>
            {reply}
          </div>
        )}

        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {!editing && (
            <button
              onClick={async () => {
                setBusy('approve')
                try {
                  await approveAndSend(message.id, threadId, reply, currentAdminId, /*edited*/ false)
                  onApprovedSent?.()
                } catch (e) { console.error(e); alert('Odeslání selhalo: ' + (e?.message || 'unknown')) }
                setBusy('')
              }}
              disabled={!!busy}
              style={btnStyle('#16a34a', '#fff')}
            >
              {busy === 'approve' ? 'Odesílám…' : '✓ Schválit a odeslat'}
            </button>
          )}
          <button
            onClick={() => {
              if (editing) {
                // ulož + odešli
                setBusy('edited')
                approveAndSend(message.id, threadId, editedText, currentAdminId, /*edited*/ true)
                  .then(() => onApprovedSent?.())
                  .catch(e => { console.error(e); alert('Odeslání selhalo: ' + (e?.message || 'unknown')) })
                  .finally(() => setBusy(''))
              } else {
                setEditing(true)
              }
            }}
            disabled={!!busy}
            style={btnStyle('#2563eb', '#fff')}
          >
            {editing
              ? (busy === 'edited' ? 'Odesílám…' : '✓ Odeslat upravené')
              : '✎ Upravit'}
          </button>
          {editing && (
            <button
              onClick={() => { setEditing(false); setEditedText(reply || '') }}
              disabled={!!busy}
              style={btnStyle('#64748b', '#fff')}
            >
              Zrušit úpravu
            </button>
          )}
          <button
            onClick={async () => {
              setBusy('reject')
              try {
                await rejectSuggestion(message.id, currentAdminId)
                onApprovedSent?.()
              } catch (e) { console.error(e) }
              setBusy('')
            }}
            disabled={!!busy}
            style={btnStyle('#dc2626', '#fff')}
          >
            {busy === 'reject' ? '…' : '✕ Zamítnout'}
          </button>
          <button
            onClick={async () => {
              setBusy('regen')
              try {
                await regenerateSuggestion(message.id)
              } catch (e) { console.error(e) }
              setBusy('')
            }}
            disabled={!!busy}
            style={{ ...btnStyle('transparent', '#475569'), border: '1px solid #cbd5e1' }}
          >
            ↻ Vygenerovat znovu
          </button>
        </div>
      </div>
    )
  }

  // Stav 3: rozhodnuto (sent / auto_sent / approved / edited / rejected) → kompaktní badge
  const sentText = final || reply
  const isRejected = status === 'rejected'
  const decided = ['sent', 'auto_sent', 'approved', 'edited'].includes(status)

  return (
    <div style={{
      marginTop: 6, padding: '4px 8px', fontSize: 10, lineHeight: 1.4,
      borderRadius: 4,
      background: isRejected ? '#fef2f2' : '#f0fdf4',
      border: `1px solid ${isRejected ? '#fecaca' : '#bbf7d0'}`,
      color: isRejected ? '#991b1b' : '#166534',
    }}>
      <strong>{STATUS_LABELS[status] || status}</strong>
      {decided && message.ai_approved_at && (
        <span style={{ marginLeft: 6, color: '#64748b' }}>
          · {new Date(message.ai_approved_at).toLocaleString('cs-CZ')}
        </span>
      )}
      {decided && sentText && status === 'edited' && (
        <div style={{ marginTop: 2, color: '#0f172a', whiteSpace: 'pre-wrap' }}>
          „{sentText.slice(0, 200)}{sentText.length > 200 ? '…' : ''}"
        </div>
      )}
    </div>
  )
}

function btnStyle(bg, color) {
  return {
    padding: '4px 10px', fontSize: 11, fontWeight: 700, borderRadius: 6,
    cursor: 'pointer', border: 'none', background: bg, color,
  }
}

// ─── Akce ────────────────────────────────────────────────────────────────────

async function approveAndSend(messageId, threadId, finalText, adminId, edited) {
  const text = (finalText || '').trim()
  if (!text) throw new Error('Prázdný text odpovědi')
  const now = new Date().toISOString()

  // 1) Zapiš schválení do AI sloupců
  await supabase.from('messages').update({
    ai_suggestion_status: edited ? 'edited' : 'approved',
    ai_final_reply: text,
    ai_approved_by: adminId || null,
    ai_approved_at: now,
  }).eq('id', messageId)

  // 2) Vlož outbound zprávu (admin reply)
  const { data: outbound, error: insErr } = await supabase.from('messages').insert({
    thread_id: threadId,
    direction: 'admin',
    sender_name: 'Admin',
    content: text,
    read_at: now,
  }).select('id').single()
  if (insErr) throw insErr

  // 3) Posuň status na 'sent' + cross-link
  await supabase.from('messages').update({
    ai_suggestion_status: 'sent',
    ai_sent_message_id: outbound?.id || null,
  }).eq('id', messageId)

  // 4) Update thread
  await supabase.from('message_threads').update({
    last_message_at: now, status: 'open',
  }).eq('id', threadId)
}

async function rejectSuggestion(messageId, adminId) {
  await supabase.from('messages').update({
    ai_suggestion_status: 'rejected',
    ai_approved_by: adminId || null,
    ai_approved_at: new Date().toISOString(),
  }).eq('id', messageId)
}

async function regenerateSuggestion(messageId) {
  // Vyčistíme stávající návrh, aby edge fn nebyla idempotentní skip
  await supabase.from('messages').update({
    ai_suggested_reply: null,
    ai_suggestion_status: null,
    ai_confidence: null,
    ai_admin_note: null,
    ai_error: null,
  }).eq('id', messageId)
  await supabase.functions.invoke('ai-customer-messages-suggest', {
    body: { message_id: messageId },
  })
}
