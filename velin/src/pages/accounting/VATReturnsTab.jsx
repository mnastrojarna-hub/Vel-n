/**
 * Flexi Reports Tab — pulls reports from Abra Flexi
 * DPH (prepared but inactive), Tax summary, Account balances, Depreciation
 */
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import {
  isFlexiConfigured, getFlexiConfig, testFlexiConnection,
  pullVATReport, pullDepreciationSchedule, pullAccountBalances,
} from '../../lib/abraFlexi'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'

export default function FlexiReportsTab() {
  const [flexiOk, setFlexiOk] = useState(null)
  const [flexiInfo, setFlexiInfo] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [config, setConfig] = useState(null)
  const [showConfig, setShowConfig] = useState(false)
  const [syncLog, setSyncLog] = useState([])
  const [vatStatus, setVatStatus] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const [configured, cfg] = await Promise.all([
        isFlexiConfigured(),
        getFlexiConfig(),
      ])
      setFlexiOk(configured)
      setConfig(cfg)
      setVatStatus(cfg?.vat_payer ? 'active' : 'inactive')

      if (configured) {
        const conn = await testFlexiConnection()
        setFlexiInfo(conn)
      }

      // Load recent sync log
      const { data: logs } = await supabase.from('flexi_sync_log')
        .select('*').order('created_at', { ascending: false }).limit(20)
      setSyncLog(logs || [])
    } catch (e) { setError(e.message) }
    finally { setLoading(false) }
  }

  async function handleTestConnection() {
    setError(null)
    const result = await testFlexiConnection()
    setFlexiInfo(result)
    if (!result.ok) setError('Pripojeni selhalo: ' + result.error)
  }

  const now = new Date()

  return (
    <div>
      {/* Connection status */}
      <Card className="mb-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Abra Flexi</h3>
            {flexiOk ? (
              <div className="flex items-center gap-2 mt-1">
                <span className="inline-block w-2 h-2 rounded-full" style={{ background: flexiInfo?.ok ? '#1a8a18' : '#dc2626' }} />
                <span className="text-sm font-bold" style={{ color: flexiInfo?.ok ? '#1a8a18' : '#dc2626' }}>
                  {flexiInfo?.ok ? `Pripojeno (${flexiInfo.company || config?.company})` : 'Odpojeno'}
                </span>
                {flexiInfo?.version && <span className="text-sm" style={{ color: '#6b7280' }}>v{flexiInfo.version}</span>}
              </div>
            ) : (
              <p className="text-sm mt-1" style={{ color: '#b45309' }}>Abra Flexi neni nakonfigurovano</p>
            )}
          </div>
          <div className="flex gap-2">
            <Button onClick={handleTestConnection}>Test pripojeni</Button>
            <Button green onClick={() => setShowConfig(true)}>Nastaveni</Button>
          </div>
        </div>
      </Card>

      {/* DPH status */}
      <Card className="mb-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>DPH</h3>
            <p className="text-sm mt-1" style={{ color: '#6b7280' }}>
              {vatStatus === 'inactive'
                ? 'Firma neni platce DPH — struktura pripravena pro budouci registraci'
                : 'Firma je platce DPH — data se tahaji z Abra Flexi'}
            </p>
          </div>
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '6px 14px', background: vatStatus === 'inactive' ? '#fef3c7' : '#dcfce7', color: vatStatus === 'inactive' ? '#b45309' : '#1a8a18' }}>
            {vatStatus === 'inactive' ? 'Neaktivni' : 'Aktivni'}
          </span>
        </div>
      </Card>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Sync log */}
      <Card className="mb-4">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Posledni synchronizace</h3>
        {syncLog.length === 0 ? (
          <p className="text-sm" style={{ color: '#6b7280' }}>Zadne zaznamy</p>
        ) : (
          <Table>
            <thead>
              <TRow header>
                <TH>Cas</TH><TH>Smer</TH><TH>Endpoint</TH><TH>Metoda</TH><TH>Status</TH><TH>Trvani</TH>
              </TRow>
            </thead>
            <tbody>
              {syncLog.map(l => (
                <TRow key={l.id}>
                  <TD>{new Date(l.created_at).toLocaleString('cs-CZ')}</TD>
                  <TD>
                    <span className="text-sm font-bold" style={{ color: l.direction === 'push' ? '#2563eb' : '#059669' }}>
                      {l.direction === 'push' ? 'PUSH' : 'PULL'}
                    </span>
                  </TD>
                  <TD mono>{l.endpoint?.split('/').slice(-1)[0] || l.endpoint}</TD>
                  <TD>{l.method}</TD>
                  <TD>
                    <span className="text-sm font-bold" style={{ color: (l.response_status >= 200 && l.response_status < 300) ? '#1a8a18' : '#dc2626' }}>
                      {l.response_status || 'ERR'}
                    </span>
                    {l.error_message && <span className="text-sm ml-1" style={{ color: '#dc2626' }}>{l.error_message}</span>}
                  </TD>
                  <TD>{l.duration_ms ? `${l.duration_ms}ms` : '—'}</TD>
                </TRow>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      {/* Config modal */}
      {showConfig && <FlexiConfigModal config={config} onClose={() => setShowConfig(false)} onSaved={() => { setShowConfig(false); load() }} />}
    </div>
  )
}

function FlexiConfigModal({ config, onClose, onSaved }) {
  const [form, setForm] = useState({
    url: config?.url || '',
    company: config?.company || 'motogo24',
    username: config?.username || '',
    api_token: config?.api_token || '',
    auto_sync: config?.auto_sync ?? true,
    confidence_threshold: config?.confidence_threshold || 0.85,
    vat_payer: config?.vat_payer || false,
    default_vat_rate: config?.default_vat_rate || 0,
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('app_settings').upsert({
        key: 'flexi_config',
        value: form,
      }, { onConflict: 'key' })
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nastaveni Abra Flexi" onClose={onClose}>
      <div className="space-y-3">
        <div><Label>URL instance</Label>
          <input type="text" value={form.url} onChange={e => set('url', e.target.value)} placeholder="https://demo.flexibee.eu" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div><Label>Nazev firmy (company)</Label>
          <input type="text" value={form.company} onChange={e => set('company', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div><Label>Uzivatelske jmeno</Label>
          <input type="text" value={form.username} onChange={e => set('username', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div><Label>API Token</Label>
          <input type="password" value={form.api_token} onChange={e => set('api_token', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div className="flex items-center gap-2">
          <input type="checkbox" checked={form.auto_sync} onChange={e => set('auto_sync', e.target.checked)} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Automaticky synchronizovat do Flexi</span>
        </div>
        <div><Label>Prah duvery AI ({(form.confidence_threshold * 100).toFixed(0)}%)</Label>
          <input type="range" min="0.5" max="1" step="0.05" value={form.confidence_threshold} onChange={e => set('confidence_threshold', Number(e.target.value))} className="w-full" />
        </div>
        <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fbbf24' }}>
          <div className="flex items-center gap-2">
            <input type="checkbox" checked={form.vat_payer} onChange={e => { set('vat_payer', e.target.checked); if (e.target.checked) set('default_vat_rate', 21) }} />
            <span className="text-sm font-bold" style={{ color: '#78350f' }}>Platce DPH</span>
          </div>
          <p className="text-sm mt-1" style={{ color: '#92400e' }}>
            {form.vat_payer ? 'DPH bude aktivne pocitano' : 'DPH je neaktivni — pripraveno pro budouci registraci'}
          </p>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
