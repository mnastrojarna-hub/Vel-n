import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { Spinner, EmptyState } from './BranchHelpers'

// ─── Tab: Samoobsluha (kiosk) ─────────────────────────────────────────────
// Konfigurace samoobslužné pobočky pro kiosk appku:
//  - kiosk token + hudba + časování (branch_kiosk_config)
//  - mapování dveří na Shelly relé/světlo (branch_doors)
//  - servisní hesla (branch_service_codes)
function TabSelfService({ branchId, branchName, motos }) {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [cfg, setCfg] = useState(null)
  const [doors, setDoors] = useState([])
  const [codes, setCodes] = useState([])
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [c, d, s] = await Promise.all([
        supabase.from('branch_kiosk_config').select('*').eq('branch_id', branchId).maybeSingle(),
        supabase.from('branch_doors').select('*').eq('branch_id', branchId).order('door_kind').order('box_number'),
        supabase.from('branch_service_codes').select('*').eq('branch_id', branchId).order('created_at'),
      ])
      setCfg(c.data || null)
      setDoors(d.data || [])
      setCodes(s.data || [])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [branchId])

  useEffect(() => { load() }, [load])

  async function ensureConfig() {
    setBusy(true)
    try {
      const { error } = await supabase.from('branch_kiosk_config').insert({ branch_id: branchId })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function saveCfg(patch) {
    setCfg(c => ({ ...c, ...patch }))
    try {
      const { error } = await supabase.from('branch_kiosk_config').update(patch).eq('branch_id', branchId)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }

  async function regenToken() {
    if (!window.confirm('Vygenerovat nový kiosk token? Tablet bude nutné znovu spárovat.')) return
    const token = crypto.randomUUID()
    await saveCfg({ kiosk_token: token })
  }

  async function ensureDoors() {
    setBusy(true)
    try {
      const existing = new Set(doors.filter(d => d.door_kind === 'motorcycle').map(d => d.box_number))
      const rows = []
      ;(motos || []).filter(m => m.box_number != null).forEach(m => {
        if (!existing.has(m.box_number)) {
          rows.push({ branch_id: branchId, door_kind: 'motorcycle', box_number: m.box_number, label: `Garáž #${m.box_number} — ${m.model || ''}`.trim() })
        }
      })
      if (!doors.some(d => d.door_kind === 'accessories')) {
        rows.push({ branch_id: branchId, door_kind: 'accessories', box_number: null, label: 'Skříň oblečení' })
      }
      if (rows.length) {
        const { error } = await supabase.from('branch_doors').insert(rows)
        if (error) throw error
      }
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function saveDoor(id, patch) {
    setDoors(ds => ds.map(d => d.id === id ? { ...d, ...patch } : d))
    try {
      const { error } = await supabase.from('branch_doors').update(patch).eq('id', id)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }

  async function deleteDoor(id) {
    if (!window.confirm('Smazat tyto dveře?')) return
    await supabase.from('branch_doors').delete().eq('id', id)
    await load()
  }

  async function addCode(code, label) {
    if (!code.trim()) return
    setBusy(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const { error } = await supabase.from('branch_service_codes').insert({
        branch_id: branchId, code: code.trim(), label: label.trim() || null, created_by: user?.id || null,
      })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function toggleCode(c) {
    await supabase.from('branch_service_codes').update({ is_active: !c.is_active }).eq('id', c.id)
    await load()
  }

  async function deleteCode(id) {
    if (!window.confirm('Smazat servisní heslo?')) return
    await supabase.from('branch_service_codes').delete().eq('id', id)
    await load()
  }

  if (loading) return <Spinner />

  return (
    <div className="space-y-5">
      {error && <div className="p-2 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

      {!cfg ? (
        <div className="p-4 rounded-card text-center" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>Tato pobočka zatím nemá nastavený kiosk samoobsluhy.</p>
          <button onClick={ensureConfig} disabled={busy} className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '8px 16px', background: '#1a2e22', color: '#74FB71' }}>
            {busy ? 'Zakládám…' : 'Aktivovat samoobsluhu'}
          </button>
        </div>
      ) : (
        <>
          <KioskConfigBlock cfg={cfg} onSave={saveCfg} onRegen={regenToken} branchName={branchName} />
          <DoorsBlock doors={doors} onEnsure={ensureDoors} onSave={saveDoor} onDelete={deleteDoor} busy={busy} />
          <ServiceCodesBlock codes={codes} onAdd={addCode} onToggle={toggleCode} onDelete={deleteCode} busy={busy} />
        </>
      )}
    </div>
  )
}

function Section({ title, hint, children, action }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{title}</div>
          {hint && <div className="text-[12px]" style={{ color: '#6b8c7a' }}>{hint}</div>}
        </div>
        {action}
      </div>
      {children}
    </div>
  )
}

function Field({ label, value, onCommit, placeholder, type = 'text', width }) {
  const [v, setV] = useState(value ?? '')
  useEffect(() => { setV(value ?? '') }, [value])
  return (
    <label className="flex flex-col gap-0.5" style={{ width }}>
      <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>{label}</span>
      <input type={type} value={v} placeholder={placeholder}
        onChange={e => setV(e.target.value)}
        onBlur={() => { if ((v ?? '') !== (value ?? '')) onCommit(type === 'number' ? (parseInt(v) || 0) : v) }}
        className="rounded-btn text-sm outline-none"
        style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
    </label>
  )
}

function KioskConfigBlock({ cfg, onSave, onRegen, branchName }) {
  return (
    <Section title="Kiosk — párování & hudba"
      hint="Token zadejte do tabletu při prvním spuštění (5× klepnutí na logo → nastavení).">
      <div className="p-3 rounded-card space-y-3" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>KIOSK TOKEN</span>
          <span className="font-mono text-sm font-bold" style={{ color: '#0f1a14', background: '#dcfce7', padding: '4px 8px', borderRadius: 6 }}>
            {cfg.kiosk_token}
          </span>
          <button onClick={() => navigator.clipboard?.writeText(cfg.kiosk_token)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
            style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb' }}>Kopírovat</button>
          <button onClick={onRegen} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
            style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626' }}>Nový token</button>
        </div>
        <div className="flex gap-3 flex-wrap">
          <Field label="Hudba — URL spuštění" value={cfg.music_on_url} onCommit={v => onSave({ music_on_url: v })} placeholder="http://192.168.1.50/relay/0?turn=on" width={300} />
          <Field label="Hudba — URL zastavení (volitelné)" value={cfg.music_off_url} onCommit={v => onSave({ music_off_url: v })} placeholder="http://192.168.1.50/relay/0?turn=off" width={300} />
        </div>
        <div className="flex gap-3 flex-wrap">
          <Field label="Otevření dveří (s)" type="number" value={cfg.door_open_seconds} onCommit={v => onSave({ door_open_seconds: v })} width={130} />
          <Field label="Světlo (s)" type="number" value={cfg.light_seconds} onCommit={v => onSave({ light_seconds: v })} width={130} />
          <Field label="Hudba (s)" type="number" value={cfg.music_seconds} onCommit={v => onSave({ music_seconds: v })} width={130} />
        </div>
      </div>
    </Section>
  )
}

function DoorsBlock({ doors, onEnsure, onSave, onDelete, busy }) {
  return (
    <Section title="Dveře → relé & světlo (Shelly LAN)"
      hint="Pro každou kóji (dle čísla boxu motorky) a dveře oblečení nastavte URL relé a světla."
      action={
        <button onClick={onEnsure} disabled={busy} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', opacity: busy ? 0.5 : 1 }}>
          {busy ? 'Pracuji…' : 'Vytvořit dveře z kojí'}
        </button>
      }>
      {doors.length === 0 ? (
        <EmptyState text="Žádné dveře. Nejdřív přiřaďte čísla kojí (záložka Motorky & Koje), pak klikněte „Vytvořit dveře z kojí“." />
      ) : (
        <div className="space-y-1 max-h-72 overflow-y-auto">
          {doors.map(d => (
            <div key={d.id} className="flex items-end gap-2 p-2 rounded-lg flex-wrap"
              style={{ background: d.door_kind === 'accessories' ? '#eff6ff' : '#f1faf7', border: '1px solid #d4e8e0' }}>
              <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase self-center"
                style={{ padding: '2px 6px', background: d.door_kind === 'accessories' ? '#dbeafe' : '#dcfce7', color: d.door_kind === 'accessories' ? '#2563eb' : '#1a8a18', minWidth: 64, textAlign: 'center' }}>
                {d.door_kind === 'accessories' ? 'Oblečení' : `Koje #${d.box_number}`}
              </span>
              <Field label="Popis" value={d.label} onCommit={v => onSave(d.id, { label: v })} width={150} />
              <Field label="URL relé (otevření)" value={d.relay_url} onCommit={v => onSave(d.id, { relay_url: v })} placeholder="http://192.168.1.51/relay/0?turn=on" width={240} />
              <Field label="URL světla" value={d.light_url} onCommit={v => onSave(d.id, { light_url: v })} placeholder="http://192.168.1.51/relay/1?turn=on" width={240} />
              <button onClick={() => onDelete(d.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none self-center"
                style={{ padding: '6px 8px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

function ServiceCodesBlock({ codes, onAdd, onToggle, onDelete, busy }) {
  const [code, setCode] = useState('')
  const [label, setLabel] = useState('')
  return (
    <Section title="Servisní hesla" hint="Otevírají všechny dveře. Appka se zeptá, které dveře otevřít.">
      <div className="flex items-end gap-2 mb-2 flex-wrap">
        <label className="flex flex-col gap-0.5" style={{ width: 160 }}>
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>Heslo</span>
          <input value={code} onChange={e => setCode(e.target.value)} placeholder="např. servis2026"
            className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </label>
        <label className="flex flex-col gap-0.5" style={{ width: 200 }}>
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>Komu patří (volitelné)</span>
          <input value={label} onChange={e => setLabel(e.target.value)} placeholder="Technik Petr"
            className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </label>
        <button onClick={() => { onAdd(code, label); setCode(''); setLabel('') }} disabled={busy || !code.trim()}
          className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '6px 12px', background: '#1a2e22', color: '#74FB71', opacity: (busy || !code.trim()) ? 0.5 : 1 }}>Přidat</button>
      </div>
      {codes.length === 0 ? (
        <EmptyState text="Žádná servisní hesla" />
      ) : (
        <div className="space-y-1">
          {codes.map(c => (
            <div key={c.id} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
              <span className="font-mono font-extrabold text-sm" style={{ color: '#0f1a14' }}>{c.code}</span>
              {c.label && <span className="text-sm" style={{ color: '#1a2e22' }}>{c.label}</span>}
              <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
                style={{ padding: '2px 6px', background: c.is_active ? '#dcfce7' : '#f3f4f6', color: c.is_active ? '#1a8a18' : '#6b8c7a' }}>
                {c.is_active ? 'Aktivní' : 'Vypnuté'}
              </span>
              <div className="ml-auto flex gap-1">
                <button onClick={() => onToggle(c)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
                  style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb' }}>{c.is_active ? 'Vypnout' : 'Zapnout'}</button>
                <button onClick={() => onDelete(c.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
                  style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

export { TabSelfService }
