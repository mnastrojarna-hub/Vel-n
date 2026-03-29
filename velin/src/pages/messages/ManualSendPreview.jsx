import { CHANNEL_LABELS, CHAR_LIMITS } from './messageHelpers'

export default function ManualSendPreview({ channel, finalText, smsInfo, subject }) {
  return (
    <div className="flex-shrink-0" style={{ width: 280, minWidth: 240 }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
        Náhled
      </div>

      {finalText ? (
        <div>
          {channel === 'sms' && (
            <div>
              <div className="rounded-card" style={{ padding: '14px 16px', background: '#dcfce7', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>
                {finalText}
              </div>
              <div className="mt-2 space-y-0.5" style={{ fontSize: 11, color: '#1a2e22' }}>
                <div>{smsInfo.chars} znaků · {smsInfo.isUcs2 ? 'UCS-2 (diakritika)' : 'GSM 7-bit'}</div>
                <div>{smsInfo.segments} {smsInfo.segments === 1 ? 'segment' : smsInfo.segments < 5 ? 'segmenty' : 'segmentů'} ({smsInfo.perSegment} znaků/segment)</div>
                <div>Odhadovaná cena: ~{(smsInfo.segments * 0.5).toFixed(1)} Kč</div>
              </div>
            </div>
          )}

          {channel === 'whatsapp' && (
            <div>
              <div className="rounded-card" style={{ padding: '10px 14px', background: '#e7feed', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>
                {finalText}
              </div>
              <div className="mt-2" style={{ fontSize: 11, color: '#1a2e22' }}>
                {finalText.length} / {CHAR_LIMITS.whatsapp} znaků
              </div>
            </div>
          )}

          {channel === 'email' && (
            <div className="rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', overflow: 'hidden' }}>
              {subject && (
                <div className="text-sm font-bold" style={{ padding: '8px 12px', borderBottom: '1px solid #d4e8e0', color: '#0f1a14' }}>
                  {subject}
                </div>
              )}
              <div style={{ padding: '10px 12px', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', color: '#0f1a14', maxHeight: 300, overflow: 'auto' }}>
                {finalText}
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="rounded-card flex items-center justify-center"
          style={{ padding: 24, background: '#f1faf7', border: '1px dashed #d4e8e0', color: '#1a2e22', fontSize: 12, minHeight: 120 }}>
          Začněte psát pro zobrazení náhledu
        </div>
      )}
    </div>
  )
}
