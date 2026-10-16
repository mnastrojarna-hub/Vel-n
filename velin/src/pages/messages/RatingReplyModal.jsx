// Zprávy → Hodnocení: první zpráva zákazníkovi, když k rezervaci ještě není konverzace
// (zákazník dal jen hvězdičky). Po odeslání se otevře běžný Chat s tímto vláknem.
import { useState } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { useIsMobile } from '../../hooks/useIsMobile'
import { Stars } from './RatingsParts'
import { feedbackSubject } from './ratingsData'

const M_BTN = { flex: '1 1 0', justifyContent: 'center', minHeight: 44 }

export default function RatingReplyModal({ row, onClose, onSend }) {
  const isMobile = useIsMobile()
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(null)
  if (!row) return null
  const b = row.booking

  async function send() {
    if (!text.trim() || sending) return
    setSending(true); setError(null)
    try { await onSend(row, text) } catch (e) { setError(e.message || String(e)); setSending(false) }
  }

  return (
    <Modal open title="Napsat zákazníkovi" onClose={onClose}>
      <div className="space-y-3">
        <div className="rounded-card" style={{ padding: 12, background: row.low ? '#fef2f2' : '#f1faf7', border: `1px solid ${row.low ? '#fca5a5' : '#d4e8e0'}`, fontSize: 13, color: '#1a2e22' }}>
          <div className="flex items-center flex-wrap" style={{ gap: 8 }}>
            <Stars value={row.rating} />
            <strong>{b.profiles?.full_name || b.profiles?.email || 'Zákazník'}</strong>
            <span style={{ fontFamily: 'monospace' }}>#{row.short}</span>
          </div>
          <div style={{ marginTop: 6 }}>
            Zákazník k hodnocení zatím nic nenapsal. Zpráva založí konverzaci <strong>„{feedbackSubject(b.profiles?.language, b.id)}“</strong>,
            zákazníkovi přijde do appky jako notifikace a odpověď uvidíte v záložce Chat.
          </div>
        </div>
        <textarea value={text} onChange={e => setText(e.target.value)} autoFocus maxLength={4000}
          placeholder="Napište zprávu zákazníkovi…"
          className="w-full rounded-btn text-sm outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 110, resize: 'vertical' }} />
        {error && <div className="p-2 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>Odeslání selhalo: {error}</div>}
        <div className="flex justify-end gap-2 pt-1">
          <Button onClick={onClose} style={isMobile ? M_BTN : undefined}>Zrušit</Button>
          <Button green onClick={send} disabled={sending || !text.trim()} style={isMobile ? M_BTN : undefined}>
            {sending ? 'Odesílám…' : 'Odeslat a otevřít chat'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
