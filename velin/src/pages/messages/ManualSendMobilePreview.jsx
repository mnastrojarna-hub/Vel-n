import { useState } from 'react'
import { CHAR_LIMITS } from './messageHelpers'

// Náhled ruční zprávy na telefonu/tabletu: rozbalovací panel pod formulářem.
// Souhrn (znaky, segmenty, cena / předmět) je vidět i ve sbaleném stavu.
const BUBBLE = { padding: '12px 14px', color: '#0f1a14', fontSize: 14, lineHeight: 1.5, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', borderRadius: '16px 16px 4px 16px', maxHeight: 320, overflow: 'auto' }
const META = { fontSize: 12, color: '#1a2e22', marginTop: 8, lineHeight: 1.6 }

function segWord(n) {
  return n === 1 ? 'segment' : n >= 2 && n <= 4 ? 'segmenty' : 'segmentů'
}

function smsCost(info) {
  return (info.segments * 0.5).toFixed(1).replace('.', ',')
}

function summaryText(channel, finalText, subject, smsInfo) {
  if (channel === 'email') return subject ? `Předmět: ${subject}` : (finalText ? 'Bez předmětu' : 'Zatím prázdný e-mail')
  if (!finalText) return 'Začněte psát pro zobrazení náhledu'
  if (channel === 'sms') return `${smsInfo.chars} znaků · ${smsInfo.segments} ${segWord(smsInfo.segments)} · ~${smsCost(smsInfo)} Kč`
  return `${finalText.length} / ${CHAR_LIMITS.whatsapp} znaků`
}

function initialOpen() {
  // Tablet má místo → náhled rovnou otevřený; telefon začíná sbaleným panelem
  try { return window.matchMedia('(min-width: 768px)').matches } catch { return false }
}

export default function ManualSendMobilePreview({ channel, finalText, subject, smsInfo }) {
  const [open, setOpen] = useState(initialOpen)
  return (
    <div className="rounded-card" style={{ border: '1px solid #d4e8e0', background: '#f8fcfa', minWidth: 0 }}>
      <button type="button" onClick={() => setOpen(o => !o)} aria-expanded={open}
        className="w-full flex items-center text-left cursor-pointer border-none rounded-card"
        style={{ gap: 10, minHeight: 52, padding: '8px 14px', background: 'transparent' }}>
        <span className="shrink-0" style={{ fontSize: 18 }}>👁️</span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span className="block font-extrabold uppercase tracking-wide" style={{ fontSize: 13, color: '#1a2e22' }}>Náhled</span>
          {!open && <span className="block truncate" style={{ fontSize: 12, color: '#4a6357', marginTop: 1 }}>{summaryText(channel, finalText, subject, smsInfo)}</span>}
        </span>
        <span className="shrink-0 font-extrabold" style={{ fontSize: 12, color: '#1a2e22' }}>{open ? 'Skrýt ▴' : 'Zobrazit ▾'}</span>
      </button>

      {open && (
        <div style={{ padding: '0 14px 14px' }}>
          {!finalText ? (
            <div className="rounded-card flex items-center justify-center text-center"
              style={{ padding: 20, background: '#f1faf7', border: '1px dashed #d4e8e0', color: '#1a2e22', fontSize: 13, minHeight: 90 }}>
              Začněte psát pro zobrazení náhledu
            </div>
          ) : channel === 'sms' ? (
            <div>
              <div className="rounded-card" style={{ ...BUBBLE, background: '#dcfce7' }}>{finalText}</div>
              <div style={META}>
                <div>{smsInfo.chars} znaků · {smsInfo.isUcs2 ? 'UCS-2 (diakritika)' : 'GSM 7-bit'}</div>
                <div>{smsInfo.segments} {segWord(smsInfo.segments)} ({smsInfo.perSegment} znaků/segment)</div>
                <div className="font-bold">Odhadovaná cena: ~{smsCost(smsInfo)} Kč</div>
              </div>
            </div>
          ) : channel === 'whatsapp' ? (
            <div>
              <div className="rounded-card" style={{ ...BUBBLE, background: '#e7feed' }}>{finalText}</div>
              <div style={META}>{finalText.length} / {CHAR_LIMITS.whatsapp} znaků</div>
            </div>
          ) : (
            <div className="rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', overflow: 'hidden' }}>
              {subject && (
                <div className="font-bold" style={{ padding: '10px 12px', borderBottom: '1px solid #d4e8e0', color: '#0f1a14', fontSize: 14, overflowWrap: 'anywhere' }}>
                  {subject}
                </div>
              )}
              <div style={{ padding: '10px 12px', fontSize: 14, lineHeight: 1.5, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', color: '#0f1a14', maxHeight: 320, overflow: 'auto' }}>
                {finalText}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
