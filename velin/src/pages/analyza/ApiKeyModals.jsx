/**
 * MotoGo24 Velín — API Key management modals
 *
 * Umožňuje adminovi:
 *   - Vytvořit nový REST API klíč pro partnera (create_api_key RPC)
 *   - Zobrazit plain text klíče JEDNOU (dál už jen prefix)
 *   - Zneplatnit existující klíč (revoke_api_key RPC)
 *
 * Klíč se zobrazí v "show-once" modalu s tlačítkem "Zkopírovat" a
 * varováním že další zobrazení nebude.
 */
import { useState } from 'react'
import { supabase } from '../../lib/supabase'

const SCOPES_OPTIONS = [
  { id: 'read',  label: 'Read (motorcycles, branches, faq)' },
  { id: 'quote', label: 'Quote (kalkulace ceny)' },
  { id: 'book',  label: 'Book (vytvoření rezervace)' },
]

export function CreateApiKeyModal({ onClose, onCreated }) {
  const [form, setForm] = useState({
    partner_name: '', partner_email: '', partner_url: '',
    rate_limit_rpm: 1000, scopes: ['read'],
  })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [createdKey, setCreatedKey] = useState(null)
  const [copied, setCopied] = useState(false)

  async function save() {
    if (!form.partner_name || !form.partner_email) {
      setError('Vyplň název partnera a e-mail.')
      return
    }
    if (form.scopes.length === 0) {
      setError('Vyber alespoň jeden scope.')
      return
    }
    setSaving(true); setError(null)
    try {
      const { data, error: err } = await supabase.rpc('create_api_key', {
        p_partner_name: form.partner_name,
        p_partner_email: form.partner_email,
        p_partner_url: form.partner_url || null,
        p_rate_limit_rpm: parseInt(form.rate_limit_rpm) || 1000,
        p_scopes: form.scopes,
      })
      if (err) throw err
      setCreatedKey(data)
      onCreated && onCreated()
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  function copyKey() {
    if (!createdKey?.api_key) return
    navigator.clipboard.writeText(createdKey.api_key)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  function toggleScope(id) {
    setForm(f => ({
      ...f,
      scopes: f.scopes.includes(id) ? f.scopes.filter(s => s !== id) : [...f.scopes, id],
    }))
  }

  return (
    <div style={overlayStyle} onClick={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div style={modalStyle}>
        {!createdKey ? (
          <>
            <h2 style={{ color: '#1a2e22', fontWeight: 800, fontSize: 20, margin: 0 }}>Nový API klíč</h2>
            <p style={{ color: '#888', fontSize: 12, marginTop: 4 }}>Klíč se zobrazí pouze jednou — bezpečně ho ulož.</p>

            <div style={{ marginTop: 16, display: 'grid', gap: 10 }}>
              <Field label="Název partnera *" value={form.partner_name} onChange={(v) => setForm(f => ({ ...f, partner_name: v }))} placeholder="např. RentMotorbikes.eu" />
              <Field label="E-mail *" type="email" value={form.partner_email} onChange={(v) => setForm(f => ({ ...f, partner_email: v }))} placeholder="dev@partner.com" />
              <Field label="URL (volitelné)" type="url" value={form.partner_url} onChange={(v) => setForm(f => ({ ...f, partner_url: v }))} placeholder="https://partner.com" />
              <Field label="Rate limit (req/min)" type="number" value={form.rate_limit_rpm} onChange={(v) => setForm(f => ({ ...f, rate_limit_rpm: v }))} placeholder="1000" />

              <div>
                <label style={labelStyle}>Scopes (oprávnění)</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {SCOPES_OPTIONS.map(s => (
                    <label key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
                      <input type="checkbox" checked={form.scopes.includes(s.id)} onChange={() => toggleScope(s.id)} />
                      <span><strong>{s.id}</strong> — {s.label}</span>
                    </label>
                  ))}
                </div>
              </div>
            </div>

            {error && <div style={{ marginTop: 12, padding: 10, background: '#fecaca', color: '#991b1b', borderRadius: 8, fontSize: 12 }}>{error}</div>}

            <div style={{ display: 'flex', gap: 8, marginTop: 16, justifyContent: 'flex-end' }}>
              <button onClick={onClose} disabled={saving} style={btnSecondary}>Zrušit</button>
              <button onClick={save} disabled={saving} style={{ ...btnPrimary, opacity: saving ? 0.5 : 1 }}>
                {saving ? 'Vytvářím...' : 'Vytvořit klíč'}
              </button>
            </div>
          </>
        ) : (
          <>
            <h2 style={{ color: '#1a2e22', fontWeight: 800, fontSize: 20, margin: 0 }}>✅ Klíč vytvořen</h2>
            <div style={{ marginTop: 16, padding: 16, background: '#fefce8', border: '2px solid #facc15', borderRadius: 10 }}>
              <p style={{ fontSize: 13, fontWeight: 700, color: '#854d0e', margin: 0 }}>⚠️ Tento klíč se zobrazí pouze jednou. Ulož ho hned.</p>
            </div>

            <div style={{ marginTop: 16 }}>
              <label style={labelStyle}>API klíč</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'stretch' }}>
                <code style={{
                  flex: 1, padding: 10, background: '#1a2e22', color: '#74FB71',
                  borderRadius: 8, fontSize: 12, fontFamily: 'monospace',
                  wordBreak: 'break-all', maxHeight: 80, overflow: 'auto',
                }}>{createdKey.api_key}</code>
                <button onClick={copyKey} style={{ ...btnPrimary, minWidth: 100 }}>
                  {copied ? '✓ Zkopírováno' : 'Zkopírovat'}
                </button>
              </div>
            </div>

            <div style={{ marginTop: 12, padding: 12, background: '#f1faf7', borderRadius: 8, fontSize: 11 }}>
              <p style={{ margin: 0, marginBottom: 6 }}><strong>Použití v requestu:</strong></p>
              <code style={{ display: 'block', padding: 8, background: '#fff', borderRadius: 6, color: '#1a2e22' }}>
                curl -H "X-Api-Key: {createdKey.api_key.slice(0, 24)}..." \<br />
                &nbsp;&nbsp;https://api.motogo24.cz/api/v1/motorcycles
              </code>
            </div>

            <div style={{ display: 'flex', gap: 8, marginTop: 16, justifyContent: 'flex-end' }}>
              <button onClick={onClose} style={btnPrimary}>Hotovo</button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

export function RevokeApiKeyConfirm({ apiKey, onClose, onRevoked }) {
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  async function revoke() {
    setSaving(true); setError(null)
    try {
      const { error: err } = await supabase.rpc('revoke_api_key', {
        p_id: apiKey.id, p_reason: reason || null,
      })
      if (err) throw err
      onRevoked && onRevoked()
      onClose()
    } catch (e) {
      setError(e.message); setSaving(false)
    }
  }

  return (
    <div style={overlayStyle} onClick={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div style={{ ...modalStyle, maxWidth: 460 }}>
        <h2 style={{ color: '#991b1b', fontWeight: 800, fontSize: 18, margin: 0 }}>Zneplatnit API klíč</h2>
        <p style={{ color: '#666', fontSize: 13, marginTop: 8 }}>
          Klíč pro <strong>{apiKey.partner_name}</strong> ({apiKey.key_prefix}...) bude okamžitě nepoužitelný. Tato akce nelze vrátit.
        </p>

        <div style={{ marginTop: 12 }}>
          <label style={labelStyle}>Důvod (volitelné)</label>
          <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="např. partner ukončen, abuse..." style={inputStyle} />
        </div>

        {error && <div style={{ marginTop: 12, padding: 10, background: '#fecaca', color: '#991b1b', borderRadius: 8, fontSize: 12 }}>{error}</div>}

        <div style={{ display: 'flex', gap: 8, marginTop: 16, justifyContent: 'flex-end' }}>
          <button onClick={onClose} disabled={saving} style={btnSecondary}>Zrušit</button>
          <button onClick={revoke} disabled={saving} style={{ ...btnPrimary, background: '#dc2626', color: '#fff', opacity: saving ? 0.5 : 1 }}>
            {saving ? 'Revokuji...' : 'Zneplatnit'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ---- Styling ----
const overlayStyle = {
  position: 'fixed', inset: 0, background: 'rgba(0,0,0,.5)', zIndex: 9999,
  display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20,
}
const modalStyle = {
  background: '#fff', borderRadius: 14, padding: 24, maxWidth: 560, width: '100%',
  maxHeight: '90vh', overflowY: 'auto',
}
const labelStyle = { display: 'block', fontSize: 11, fontWeight: 700, color: '#1a2e22', textTransform: 'uppercase', marginBottom: 4 }
const inputStyle = { width: '100%', padding: 10, border: '1px solid #d4e8e0', borderRadius: 8, fontSize: 13, fontFamily: 'inherit' }
const btnPrimary = { padding: '8px 18px', background: '#74FB71', color: '#1a2e22', border: 'none', borderRadius: 18, fontWeight: 700, fontSize: 13, cursor: 'pointer' }
const btnSecondary = { padding: '8px 18px', background: '#f1faf7', color: '#1a2e22', border: 'none', borderRadius: 18, fontWeight: 700, fontSize: 13, cursor: 'pointer' }

function Field({ label, value, onChange, placeholder, type = 'text' }) {
  return (
    <div>
      <label style={labelStyle}>{label}</label>
      <input type={type} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} style={inputStyle} />
    </div>
  )
}
