import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import RadioOption from './RadioOption'
import ManualSendMobilePreview from './ManualSendMobilePreview'
import { ManualSendMobileSingle, ManualSendMobileBulk, MS_LABEL, MS_LABEL_STYLE, MS_INPUT } from './ManualSendMobileRecipient'
import { CHANNEL_LABELS, CHAR_LIMITS } from './messageHelpers'

// Ruční odeslání (SMS / E-mail / WhatsApp) na telefonu a tabletu (≤ 1023 px).
// Formulář přes celou šířku, náhled pod ním, velké tlačítko Odeslat. Veškerý stav,
// validaci i odesílání dodává ManualSendTab — tady je jen rozvržení pro dotyk.

function Choices({ children }) {
  return <div className="flex flex-wrap" style={{ gap: 8 }}>{children}</div>
}

// Co ještě chybí k odeslání (jen nápověda pod neaktivním tlačítkem)
function missingHints({ channel, sendType, bulk, single, mode, selectedTemplateId, finalText, body, subject }) {
  const out = []
  if (sendType === 'bulk') {
    if (!bulk.bulkCountLoading && bulk.bulkRecipientCount === 0) out.push('skupina nemá žádné příjemce')
  } else if (!single.selectedCustomer) out.push('vyberte příjemce')
  if (mode === 'template') {
    if (!selectedTemplateId) out.push('vyberte šablonu')
    else if (!finalText.trim()) out.push('šablona nemá text')
  } else if (!body.trim()) out.push('napište text zprávy')
  if (channel === 'email' && !subject.trim()) {
    out.push(mode === 'template' ? 'zadejte předmět (v režimu „Vlastní text“)' : 'vyplňte předmět')
  }
  return out
}

export default function ManualSendMobile(p) {
  const {
    channel, debugMode, sendType, setSendType, bulk, single, mode, setMode, templates,
    selectedTemplateId, setSelectedTemplateId, templateVariables, templateVars, setTemplateVars,
    subject, setSubject, body, setBody, finalText, smsInfo, canSend, sending, result, onSend, diag,
  } = p
  const label = CHANNEL_LABELS[channel]
  const limit = CHAR_LIMITS[channel]
  const hints = !canSend && !sending && !result?.ok ? missingHints(p) : []

  return (
    <Card style={{ padding: 16, minWidth: 0 }}>
      <h2 className="font-extrabold uppercase tracking-wide" style={{ fontSize: 14, color: '#1a2e22', marginBottom: 16, overflowWrap: 'anywhere' }}>
        Ruční odeslání — {label}
      </h2>

      <div className="flex flex-col" style={{ gap: 18, minWidth: 0 }}>
        {/* 0. Typ odeslání */}
        <div>
          <div className={MS_LABEL} style={MS_LABEL_STYLE}>Typ odeslání</div>
          <Choices>
            <RadioOption touch checked={sendType === 'single'} onChange={() => setSendType('single')} label="Jednotlivé" />
            <RadioOption touch checked={sendType === 'bulk'} onChange={() => setSendType('bulk')} label="Hromadné" />
          </Choices>
        </div>

        {/* 1. Příjemce / skupina */}
        {sendType === 'bulk' ? <ManualSendMobileBulk {...bulk} /> : <ManualSendMobileSingle {...single} />}

        {/* 2. Způsob */}
        <div>
          <div className={MS_LABEL} style={MS_LABEL_STYLE}>Způsob</div>
          <Choices>
            <RadioOption touch checked={mode === 'template'} onChange={() => setMode('template')} label="Použít šablonu" disabled={templates.length === 0} />
            <RadioOption touch checked={mode === 'custom'} onChange={() => setMode('custom')} label="Vlastní text" />
          </Choices>
          {templates.length === 0 && (
            <div style={{ fontSize: 12, color: '#4a6357', marginTop: 6 }}>Pro {label} zatím nejsou aktivní šablony.</div>
          )}
        </div>

        {/* 2a. Šablona + proměnné */}
        {mode === 'template' && (
          <div className="flex flex-col" style={{ gap: 14 }}>
            <label className="block" style={{ minWidth: 0 }}>
              <span className={MS_LABEL} style={MS_LABEL_STYLE}>Šablona</span>
              <select
                value={selectedTemplateId}
                onChange={e => { setSelectedTemplateId(e.target.value); setTemplateVars({}) }}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ ...MS_INPUT, color: '#1a2e22' }}
              >
                <option value="">— Vyberte šablonu —</option>
                {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
              </select>
            </label>

            {templateVariables.length > 0 && (
              <div>
                <div className={MS_LABEL} style={MS_LABEL_STYLE}>Proměnné</div>
                <div className="flex flex-col" style={{ gap: 10 }}>
                  {templateVariables.map(v => (
                    <label key={v} className="block" style={{ minWidth: 0 }}>
                      <span className="block font-bold" style={{ fontSize: 13, color: '#1a2e22', marginBottom: 4, overflowWrap: 'anywhere' }}>{`{{${v}}}`}</span>
                      <input
                        type="text"
                        value={templateVars[v] || ''}
                        onChange={e => setTemplateVars(prev => ({ ...prev, [v]: e.target.value }))}
                        placeholder={`Hodnota pro ${v}…`}
                        className="w-full rounded-btn text-sm outline-none"
                        style={MS_INPUT}
                      />
                    </label>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* 2b. Vlastní text */}
        {mode === 'custom' && (
          <div className="flex flex-col" style={{ gap: 14 }}>
            {channel === 'email' && (
              <label className="block" style={{ minWidth: 0 }}>
                <span className={MS_LABEL} style={MS_LABEL_STYLE}>Předmět</span>
                <input type="text" value={subject} onChange={e => setSubject(e.target.value)} placeholder="Předmět e-mailu…"
                  className="w-full rounded-btn text-sm outline-none" style={MS_INPUT} />
              </label>
            )}
            <div style={{ minWidth: 0 }}>
              <label className="block">
                <span className={MS_LABEL} style={MS_LABEL_STYLE}>Zpráva</span>
                <textarea
                  value={body}
                  onChange={e => setBody(e.target.value)}
                  placeholder={`Napište ${label} zprávu…`}
                  className="w-full rounded-btn text-sm outline-none block"
                  style={{ ...MS_INPUT, minHeight: 160, lineHeight: 1.5, resize: 'vertical', borderRadius: 18 }}
                  maxLength={channel === 'email' ? undefined : limit || undefined}
                />
              </label>
              {channel !== 'email' && (
                <div className="flex justify-end font-bold" style={{ fontSize: 12, marginTop: 4, color: body.length >= limit ? '#b45309' : '#1a2e22' }}>
                  {body.length} / {limit} znaků
                </div>
              )}
            </div>
          </div>
        )}

        {/* Náhled */}
        <ManualSendMobilePreview channel={channel} finalText={finalText} subject={subject} smsInfo={smsInfo} />

        {/* 3. Odeslat */}
        <div>
          <Button green onClick={onSend} disabled={!canSend} className="w-full justify-center" style={{ minHeight: 48, fontSize: 15, padding: '12px 16px' }}>
            {sending ? 'Odesílám…' : sendType === 'bulk' ? `Hromadně odeslat (${bulk.bulkRecipientCount})` : `Odeslat ${label}`}
          </Button>
          {hints.length > 0 && (
            <div style={{ fontSize: 12, color: '#4a6357', marginTop: 8, textAlign: 'center', overflowWrap: 'anywhere' }}>
              Pro odeslání: {hints.join(' · ')}
            </div>
          )}
          {result && (
            <div role="status" className="rounded-card font-bold"
              style={{ marginTop: 10, padding: '10px 14px', fontSize: 14, overflowWrap: 'anywhere', color: result.ok ? '#1a6a18' : '#991b1b', background: result.ok ? '#dcfce7' : '#fee2e2' }}>
              {result.ok ? '✓ ' : '⚠ '}{result.msg}
            </div>
          )}
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mt-4 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 12, fontFamily: 'monospace', color: '#78350f', overflowWrap: 'anywhere' }}>
          <strong>DIAGNOSTIKA ManualSendTab ({channel})</strong><br />
          <div>customer: {diag.selectedCustomer ? `${diag.selectedCustomer.full_name} (${diag.selectedCustomer.id?.slice(-8)})` : 'žádný'}</div>
          <div>mode: {mode}, template: {selectedTemplateId || '—'}, vars: {JSON.stringify(templateVars)}</div>
          <div>canSend: {String(canSend)}, recipientValid: {String(diag.recipientValid)}, contentValid: {String(diag.contentValid)}</div>
        </div>
      )}
    </Card>
  )
}
