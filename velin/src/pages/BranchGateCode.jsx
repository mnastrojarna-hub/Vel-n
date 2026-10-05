import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { RpiSection, Btn, Chip, Input } from './BranchRpiUi'
import { GATE_CODE_RE } from '../lib/branchGate'

// ─── Vjezdová brána — kód schránky s klíčem (branch_gate_access, 2026-10-04) ──────────────
// Řádek pobočky v `branch_gate_access` (RLS jen admin): kód schránky s klíčem od visacího zámku brány
// (Velké Němčice: HORNÍ schránka na pravém sloupku vrat). Bez řádku / vypnutý = pobočka se chová jako bez brány
// (zprávy, SMS/WA, e-maily i appka beze změny). Kód se nikam neloguje — audit nese jen „změněno“.
// Pozor: „Brána“ v diagnostice jednotky = síťová brána (gateway), tohle je fyzická vjezdová brána.

const HINT = 'Kód HORNÍ schránky na sloupku vrat, ve které je klíč od visacího zámku vjezdové brány. Zákazník ho dostává jako 1. kód '
  + '(brána → šatna → motorka) v aplikaci, e-mailu, SMS/WhatsApp a ve zprávách — jen u rezervací motorek této pobočky a až s vydaným kódem motorky. '
  + 'Kód NIKDY nepište do poznámek pobočky, FAQ ani textů webu — ty jsou veřejné. Vypnutý kód = pobočka se chová jako bez brány.'

const TABLE = 'branch_gate_access'
const boxStyle = { background: '#f8fcfa', border: '1px solid #d4e8e0' }

function BranchGateCodeBlock({ branchId }) {
  const [row, setRow] = useState(null)
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState(false)
  const [code, setCode] = useState('')
  const [note, setNote] = useState('')
  const [info, setInfo] = useState(null)

  const load = useCallback(async () => {
    const { data, error: e } = await supabase.from(TABLE).select('*').eq('branch_id', branchId).maybeSingle()
    if (e) setError(`Kód brány nelze načíst: ${e.message} (tabulka ${TABLE} nemusí být ještě nasazená)`)
    else { setRow(data || null); setError(null) }
    setLoaded(true)
  }, [branchId])
  useEffect(() => { setEditing(false); load() }, [load])

  // Audit bez kódu (jen co se stalo) — best effort, chyba auditu nesmí zablokovat uložení
  async function audit(action, newData) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, entity_type: TABLE, entity_id: branchId, new_data: newData })
    } catch { /* best effort */ }
  }

  // Vrací true jen po úspěšném uložení — nabídka dopo­slání kódů (offerNotify) nesmí běžet po chybě
  // (dřív by po neúspěšném UPDATE nabídla rozeslat STARÝ kód všem rezervacím).
  async function run(fn) {
    setBusy(true)
    try { await fn(); setEditing(false); await load(); return true } catch (e) { setError(e.message || String(e)); return false } finally { setBusy(false) }
  }

  // UPDATE bez oprávnění (RLS) chybu nevrací, jen 0 řádků → ověřit přes .select()
  async function update(patch) {
    const { data, error: e } = await supabase.from(TABLE).update(patch).eq('branch_id', branchId).select('branch_id')
    if (e) throw e
    if (!data?.length) throw new Error('Změna se neuložila (chybí oprávnění admina?)')
  }

  // Po nastavení / změně / zapnutí kódu: nabídnout dopo­slání kódu stávajícím rezervacím (RPC
  // admin_notify_branch_gate_code, 20261004f) — zákazníci, kteří kódy dostali dřív, by kód schránky neměli.
  async function offerNotify() {
    try {
      const { data: dry, error: e1 } = await supabase.rpc('admin_notify_branch_gate_code', { p_branch_id: branchId, p_dry_run: true })
      if (e1 || !dry?.success) { setInfo(e1 ? `Dopo­slání kódů nelze ověřit: ${e1.message}` : null); return }
      const n = dry.count || 0
      if (!n) { setInfo('Žádná stávající rezervace s vydanými kódy — nikomu se nic neposílá.'); return }
      if (!window.confirm(`Poslat aktuální kódy včetně kódu brány ${n} zákazníkům se stávajícími rezervacemi na této pobočce? (zpráva v aplikaci, SMS/WhatsApp a e-mail — pořadí brána → šatna → motorka)`)) {
        setInfo(`Kód uložen. Stávajícím rezervacím (${n}) se kód brány NEPOSLAL — zákazníci ho uvidí jen v aplikaci.`)
        return
      }
      const { data, error: e2 } = await supabase.rpc('admin_notify_branch_gate_code', { p_branch_id: branchId })
      if (e2) throw e2
      setInfo(`Kódy odeslány ${data?.notified ?? 0} zákazníkům.`)
      audit('branch_gate_code_notified', { notified: data?.notified ?? 0 })
    } catch (e) { setError(e.message || String(e)) }
  }

  function startEdit() { setCode(row?.lockbox_code || ''); setNote(row?.note || ''); setError(null); setEditing(true) }

  const codeOk = GATE_CODE_RE.test(code)
  const codeChanged = !!row && code !== row.lockbox_code

  function save() {
    const patch = { lockbox_code: code, note: note.trim() || null }
    return run(async () => {
      if (row) await update(patch)
      else {
        const { error: e } = await supabase.from(TABLE).insert({ branch_id: branchId, is_active: true, ...patch })
        if (e) throw e
      }
      audit(row ? 'branch_gate_code_updated' : 'branch_gate_code_created', { code_changed: !row || codeChanged })
    }).then((ok) => { if (ok && (!row || codeChanged)) return offerNotify() })
  }

  function toggle() {
    const next = !row.is_active
    if (!next && !window.confirm('Vypnout kód brány? Zákazníci pak kód brány ani postup s bránou nedostanou (v aplikaci, e-mailu, SMS ani ve zprávách).')) return
    return run(async () => { await update({ is_active: next }); audit('branch_gate_code_toggled', { is_active: next }) })
      .then((ok) => { if (ok && next) return offerNotify() })
  }

  let body
  if (!loaded) body = <div className="text-[12px]" style={{ color: '#6b8c7a' }}>Načítám…</div>
  else if (editing) body = (
    <div>
      <div className="flex items-end gap-2 flex-wrap">
        <Input label="Kód schránky (3–8 číslic)" value={code} onChange={v => setCode(v.replace(/\D/g, '').slice(0, 8))} width={170}
          placeholder="jen číslice" invalid={code !== '' && !codeOk}
          title="Kód číselníku HORNÍ schránky s klíčem od visacího zámku brány — přesně jak je nastavený na schránce." />
        <Input label="Poznámka (jen pro obsluhu)" value={note} onChange={setNote} width={340}
          placeholder="např. horní schránka na pravém sloupku vrat" title="Interní poznámka, zákazníkům se neposílá. Kód sem nepište." />
        <Btn tone="dark" onClick={save} disabled={busy || !codeOk}>{busy ? 'Ukládám…' : row ? 'Uložit' : 'Nastavit kód brány'}</Btn>
        <Btn onClick={() => setEditing(false)} disabled={busy}>Zrušit</Btn>
      </div>
      {codeChanged && codeOk && (
        <div className="text-[12px] mt-1" style={{ color: '#b45309' }}>
          Kdo už kódy dostal (SMS, e-mail, zprávy), má v nich starý kód — v aplikaci uvidí nový. Kód na schránce přenastavte ve stejnou chvíli.
        </div>
      )}
    </div>
  )
  else if (row) body = (
    <div className="flex items-center gap-2 p-2 rounded-lg flex-wrap" style={boxStyle}>
      <span className="font-mono font-extrabold text-sm" style={{ color: '#0f1a14', letterSpacing: 2 }}>{row.lockbox_code}</span>
      <Chip tone={row.is_active ? 'green' : 'gray'}>{row.is_active ? 'Aktivní — posílá se zákazníkům' : 'Vypnuto — neposílá se'}</Chip>
      {row.note && <span className="text-sm" style={{ color: '#1a2e22' }}>{row.note}</span>}
      <span className="ml-auto flex gap-1">
        <Btn small tone="blue" onClick={startEdit} disabled={busy}>Upravit</Btn>
        <Btn small tone={row.is_active ? 'red' : 'green'} onClick={toggle} disabled={busy}>{row.is_active ? 'Vypnout' : 'Zapnout'}</Btn>
      </span>
    </div>
  )
  else body = (
    <div className="flex items-center gap-2 p-2 rounded-lg flex-wrap" style={boxStyle}>
      <span className="text-sm" style={{ color: '#6b8c7a' }}>Pobočka nemá vjezdovou bránu se schránkou — zákazníci kód brány ani postup s bránou nedostávají.</span>
      <Btn small tone="dark" onClick={startEdit} style={{ marginLeft: 'auto' }}>Nastavit kód brány</Btn>
    </div>
  )

  return (
    <RpiSection title="Vjezdová brána — kód schránky s klíčem" hint={HINT}>
      {error && <div className="p-2 rounded-card text-sm mb-2" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}
      {info && <div className="p-2 rounded-card text-sm mb-2" style={{ background: '#ecfdf5', color: '#065f46' }}>{info}</div>}
      {body}
    </RpiSection>
  )
}

export { BranchGateCodeBlock }
