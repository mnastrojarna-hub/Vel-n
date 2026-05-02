import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'

export default function CustomersBulkActionsModal({ open, onClose, selectedCustomers, onUpdated }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [mode, setMode] = useState(null)
  const [reason, setReason] = useState('')
  const [licenseGroup, setLicenseGroup] = useState('')
  const [country, setCountry] = useState('')
  const [marketingValue, setMarketingValue] = useState('true')
  const [emailSubject, setEmailSubject] = useState('')
  const [emailBody, setEmailBody] = useState('')

  useEffect(() => {
    if (open) {
      setMode(null); setError(null); setSuccess(null)
      setReason(''); setLicenseGroup(''); setCountry(''); setMarketingValue('true')
      setEmailSubject(''); setEmailBody('')
    }
  }, [open])

  if (!open) return null

  const ids = selectedCustomers.map(c => c.id)
  const count = ids.length

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function run(label, fn) {
    setBusy(true); setError(null); setSuccess(null)
    try {
      await fn()
      setSuccess(`${label} (${count} zákazníků)`)
      onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleBlock(blocked) {
    await run(blocked ? 'Zákazníci zablokováni' : 'Zákazníci odblokováni', async () => {
      const upd = { is_blocked: blocked }
      if (blocked) {
        upd.blocked_at = new Date().toISOString()
        upd.blocked_reason = reason || 'Hromadné blokování'
      } else {
        upd.blocked_at = null
        upd.blocked_reason = null
      }
      const { error: err } = await supabase.from('profiles').update(upd).in('id', ids)
      if (err) throw err
      await logAudit('customer_bulk_block', { count, blocked, reason: upd.blocked_reason || null, ids })
    })
  }

  async function handleAddLicenseGroup() {
    if (!licenseGroup) { setError('Vyber skupinu'); return }
    await run(`Přidána skupina ${licenseGroup}`, async () => {
      // Read each customer's current license_group, append, write back
      for (const c of selectedCustomers) {
        const current = Array.isArray(c.license_group) ? c.license_group : []
        if (current.includes(licenseGroup)) continue
        await supabase.from('profiles').update({ license_group: [...current, licenseGroup] }).eq('id', c.id)
      }
      await logAudit('customer_bulk_add_license_group', { count, group: licenseGroup, ids })
    })
  }

  async function handleSetCountry() {
    if (!country) { setError('Vyber zemi'); return }
    await run(`Země nastavena na ${country}`, async () => {
      const { error: err } = await supabase.from('profiles').update({ country }).in('id', ids)
      if (err) throw err
      await logAudit('customer_bulk_set_country', { count, country, ids })
    })
  }

  async function handleMarketingConsent() {
    const val = marketingValue === 'true'
    await run(`Marketing souhlas: ${val ? 'ANO' : 'NE'}`, async () => {
      const { error: err } = await supabase.from('profiles')
        .update({ marketing_consent: val, consent_email: val }).in('id', ids)
      if (err) throw err
      await logAudit('customer_bulk_marketing_consent', { count, value: val, ids })
    })
  }

  async function handleDelete() {
    if (!window.confirm(`TRVALE smazat ${count} zákaznických profilů?\n\nPoznámka: rezervace, faktury a vouchery zůstanou v DB, ale nebudou mít vazbu na zákazníka.`)) return
    await run('Profily smazány', async () => {
      const { error: err } = await supabase.from('profiles').delete().in('id', ids)
      if (err) throw err
      await logAudit('customer_bulk_deleted', { count, ids })
    })
  }

  function handleExport() {
    const headers = ['ID', 'Jméno', 'Email', 'Telefon', 'Město', 'Země', 'Skupiny ŘP', 'Registrace', 'Zdroj', 'Marketing', 'Blokován']
    const rows = selectedCustomers.map(c => [
      c.id || '',
      c.full_name || '',
      c.email || '',
      c.phone || '',
      c.city || '',
      c.country || '',
      Array.isArray(c.license_group) ? c.license_group.join('|') : '',
      c.created_at?.slice(0, 10) || '',
      c.registration_source || '',
      c.marketing_consent ? 'ANO' : 'NE',
      c.is_blocked ? 'ANO' : 'NE',
    ])
    const csv = [headers, ...rows].map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `zakaznici-${new Date().toISOString().slice(0, 10)}.csv`
    a.click(); URL.revokeObjectURL(url)
    setSuccess(`Exportováno ${count} zákazníků do CSV`)
    logAudit('customer_bulk_exported', { count })
  }

  function handleCopyEmails() {
    const emails = selectedCustomers.map(c => c.email).filter(Boolean).join(', ')
    if (!emails) { setError('Žádné e-maily ve výběru'); return }
    navigator.clipboard.writeText(emails)
    setSuccess(`Zkopírováno ${emails.split(',').length} e-mailů do schránky`)
  }

  function handleCopyPhones() {
    const phones = selectedCustomers.map(c => c.phone).filter(Boolean).join(', ')
    if (!phones) { setError('Žádné telefony ve výběru'); return }
    navigator.clipboard.writeText(phones)
    setSuccess(`Zkopírováno ${phones.split(',').length} telefonů do schránky`)
  }

  async function handleSendEmail() {
    if (!emailSubject || !emailBody) { setError('Vyplň předmět a obsah'); return }
    const recipients = selectedCustomers.map(c => c.email).filter(Boolean)
    if (recipients.length === 0) { setError('Žádný e-mail ve výběru'); return }
    if (!window.confirm(`Odeslat e-mail ${recipients.length} zákazníkům?`)) return
    await run('E-maily odeslány', async () => {
      // Use Supabase edge function send-email if available; fallback: log only
      const { error: err } = await supabase.functions.invoke('send-bulk-email', {
        body: { recipients, subject: emailSubject, html: emailBody.replace(/\n/g, '<br>') },
      }).catch(e => ({ error: e }))
      if (err) {
        // Fallback: just log without sending
        await logAudit('customer_bulk_email_failed', { count: recipients.length, subject: emailSubject, error: String(err) })
        throw new Error(`Edge funkce send-bulk-email selhala: ${err.message || err}`)
      }
      await logAudit('customer_bulk_email_sent', { count: recipients.length, subject: emailSubject })
    })
  }

  return (
    <Modal open={open} onClose={onClose} title={`Hromadná správa zákazníků (${count})`} wide>
      {success && <Banner color="#16a34a" bg="#dcfce7">{success}</Banner>}
      {error && <Banner color="#dc2626" bg="#fee2e2">{error}</Banner>}

      <div className="mb-4">
        <div className="text-sm font-bold mb-2" style={{ color: '#1a2e22' }}>Vybraní zákazníci:</div>
        <div className="flex flex-wrap gap-1.5 max-h-24 overflow-auto p-2 rounded-btn" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {selectedCustomers.map(c => (
            <span key={c.id} className="text-xs font-bold px-2 py-1 rounded-btn" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              {c.full_name || '—'} <span style={{ color: '#6b7280' }}>{c.email}</span>
            </span>
          ))}
        </div>
      </div>

      {!mode && (
        <div className="grid grid-cols-2 gap-3">
          <ModeBtn label="Zablokovat / odblokovat" desc="is_blocked + důvod" onClick={() => setMode('block')} />
          <ModeBtn label="Marketing souhlas" desc="Zapnout / vypnout newsletter" onClick={() => setMode('marketing')} />
          <ModeBtn label="Přidat skupinu ŘP" desc="A / A1 / A2 / AM / B" onClick={() => setMode('license')} />
          <ModeBtn label="Nastavit zemi" desc="CZ / SK / DE / AT / PL" onClick={() => setMode('country')} />
          <ModeBtn label="Kopírovat kontakty" desc="E-maily nebo telefony do schránky" onClick={() => setMode('copy')} />
          <ModeBtn label="Hromadný e-mail" desc="Odeslat zprávu vybraným" onClick={() => setMode('email')} />
          <ModeBtn label="Export do CSV" desc="Stáhnout vybrané zákazníky" onClick={() => setMode('export')} />
          <ModeBtn label="Smazat profily" desc="Trvale odstranit (nevratné)" onClick={() => setMode('delete')} danger />
        </div>
      )}

      {mode === 'block' && (
        <Section title="Zablokovat / odblokovat" onBack={() => setMode(null)}>
          <Label>Důvod blokace</Label>
          <input value={reason} onChange={e => setReason(e.target.value)}
            placeholder="Např. dluh, nehoda bez krytí, podvod…"
            className="w-full rounded-btn text-sm outline-none mb-3"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div className="grid grid-cols-2 gap-2">
            <StatusBtn label="🚫 Zablokovat" color="#dc2626" onClick={() => handleBlock(true)} disabled={busy} />
            <StatusBtn label="✓ Odblokovat" color="#16a34a" onClick={() => handleBlock(false)} disabled={busy} />
          </div>
        </Section>
      )}

      {mode === 'marketing' && (
        <Section title="Marketing souhlas" onBack={() => setMode(null)}>
          <Label>Hodnota</Label>
          <Select value={marketingValue} onChange={setMarketingValue}
            options={[{ value: 'true', label: 'ANO — odebírá newsletter' }, { value: 'false', label: 'NE — odhlásit' }]} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleMarketingConsent} disabled={busy}>{busy ? 'Pracuji…' : `Nastavit (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'license' && (
        <Section title="Přidat skupinu řidičského průkazu" onBack={() => setMode(null)}>
          <Select value={licenseGroup} onChange={setLicenseGroup}
            options={[{ value: '', label: '— vyber skupinu —' },
              { value: 'AM', label: 'AM' }, { value: 'A1', label: 'A1' },
              { value: 'A2', label: 'A2' }, { value: 'A', label: 'A' }, { value: 'B', label: 'B' }]} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleAddLicenseGroup} disabled={busy || !licenseGroup}>{busy ? 'Pracuji…' : `Přidat (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'country' && (
        <Section title="Nastavit zemi" onBack={() => setMode(null)}>
          <Select value={country} onChange={setCountry}
            options={[{ value: '', label: '— vyber zemi —' },
              { value: 'CZ', label: 'Česko (CZ)' }, { value: 'SK', label: 'Slovensko (SK)' },
              { value: 'DE', label: 'Německo (DE)' }, { value: 'AT', label: 'Rakousko (AT)' },
              { value: 'PL', label: 'Polsko (PL)' }]} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleSetCountry} disabled={busy || !country}>{busy ? 'Pracuji…' : `Nastavit (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'copy' && (
        <Section title="Kopírovat kontakty" onBack={() => setMode(null)}>
          <div className="grid grid-cols-2 gap-2">
            <StatusBtn label="📧 Kopírovat e-maily" color="#2563eb" onClick={handleCopyEmails} disabled={busy} />
            <StatusBtn label="📱 Kopírovat telefony" color="#16a34a" onClick={handleCopyPhones} disabled={busy} />
          </div>
        </Section>
      )}

      {mode === 'email' && (
        <Section title="Odeslat hromadný e-mail" onBack={() => setMode(null)}>
          <Label>Předmět</Label>
          <input value={emailSubject} onChange={e => setEmailSubject(e.target.value)}
            className="w-full rounded-btn text-sm outline-none mb-3"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <Label>Obsah</Label>
          <textarea value={emailBody} onChange={e => setEmailBody(e.target.value)} rows={6}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div className="text-xs mt-2" style={{ color: '#6b7280' }}>
            Vyžaduje edge funkci <code>send-bulk-email</code>. Pokud není nasazená, akce selže.
          </div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleSendEmail} disabled={busy || !emailSubject || !emailBody}>
              {busy ? 'Odesílám…' : `Odeslat (${selectedCustomers.filter(c => c.email).length})`}
            </Button>
          </div>
        </Section>
      )}

      {mode === 'export' && (
        <Section title="Export do CSV" onBack={() => setMode(null)}>
          <div className="text-sm" style={{ color: '#1a2e22' }}>Stáhne CSV s {count} zákazníky (jméno, kontakty, město, ŘP, zdroj, souhlasy).</div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleExport} disabled={busy}>Stáhnout CSV</Button>
          </div>
        </Section>
      )}

      {mode === 'delete' && (
        <Section title="Trvale smazat profily" onBack={() => setMode(null)}>
          <div className="p-3 rounded-card mb-3" style={{ background: '#fee2e2', color: '#dc2626' }}>
            <strong>Pozor!</strong> Tato akce je <strong>nevratná</strong>. Profily, které mají rezervace nebo faktury, mohou způsobit problémy s integritou dat.
          </div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button onClick={handleDelete} disabled={busy} style={{ background: '#dc2626', color: '#fff' }}>
              {busy ? 'Pracuji…' : `Trvale smazat (${count})`}
            </Button>
          </div>
        </Section>
      )}

      {!mode && (
        <div className="flex justify-end mt-5">
          <Button onClick={onClose}>Zavřít</Button>
        </div>
      )}
    </Modal>
  )
}

function Banner({ children, color, bg }) {
  return <div className="mb-3 p-3 rounded-card text-sm font-bold" style={{ background: bg, color }}>{children}</div>
}

function Section({ title, children }) {
  return (
    <div className="p-4 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>{title}</div>
      {children}
    </div>
  )
}

function ModeBtn({ label, desc, onClick, danger = false }) {
  return (
    <button onClick={onClick} className="text-left rounded-card cursor-pointer transition-all hover:shadow"
      style={{ padding: 16, background: '#fff', border: `1px solid ${danger ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="font-extrabold uppercase tracking-wide text-sm" style={{ color: danger ? '#dc2626' : '#1a2e22' }}>{label}</div>
      <div className="text-xs mt-1" style={{ color: '#6b7280' }}>{desc}</div>
    </button>
  )
}

function StatusBtn({ label, color, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer text-sm disabled:opacity-50"
      style={{ padding: '10px 14px', background: '#fff', border: `2px solid ${color}`, color }}>
      {label}
    </button>
  )
}

function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function Select({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="w-full rounded-btn text-sm outline-none cursor-pointer"
      style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
