import { useState, useEffect, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { purgeWebCache } from '../../lib/webCache'
import { OPERATOR, setCompanyInfoCache, validateCompanyInfo } from '../../lib/company'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'

// Firemní údaje = `app_settings.company_info` — JEDINÉ místo, odkud provozovatele a účet čtou
// faktury, smlouvy, QR platba, e-maily, web i appka. (Dřív tahle záložka zapisovala
// `cms_variables.company_*`, které nic nečetlo.) Ukládá se merge s hodnotou v DB — ostatní
// klíče (sociální sítě…) zůstávají. Už vystavené doklady nesou vlastního vystavitele
// (`invoices.issuer_snapshot`) a touto změnou se NEpřepisují.
const GROUPS = [
  { title: 'Firemní údaje', fields: [
    { key: 'name', label: 'Název firmy' },
    { key: 'ico', label: 'IČO' },
    { key: 'dic', label: 'DIČ' },
    { key: 'vat_payer', label: 'Plátce DPH', type: 'checkbox' },
    { key: 'address', label: 'Sídlo' },
    { key: 'register', label: 'Zápis v obchodním rejstříku', type: 'textarea' },
    { key: 'register_short', label: 'Zápis v rejstříku — krátký tvar (patičky dokumentů)' },
    { key: 'data_box', label: 'Datová schránka' },
  ] },
  { title: 'Bankovní spojení', fields: [
    { key: 'bank_account', label: 'Číslo účtu' },
    { key: 'bank_iban', label: 'IBAN' },
    { key: 'bank_name', label: 'Banka' },
    { key: 'bank_bic', label: 'BIC (SWIFT)' },
  ] },
  { title: 'Kontakt', fields: [
    { key: 'phone', label: 'Telefon' },
    { key: 'email', label: 'E-mail' },
    { key: 'web', label: 'Web' },
  ] },
]
const FIELDS = GROUPS.flatMap(g => g.fields)
// Údaje tištěné na dokladech a smlouvách — jejich změna = nový provozovatel / účet.
const IDENTITY_KEYS = ['name', 'ico', 'dic', 'vat_payer', 'address', 'register', 'register_short', 'bank_account', 'bank_iban', 'bank_name', 'bank_bic']
const WARNING = 'Změna platí pro všechny nově vystavené doklady, smlouvy a e-maily. Už vystavené doklady se nemění.'

async function readCompanyInfo() {
  const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
  if (error) throw error
  return data?.value && typeof data.value === 'object' ? data.value : null
}

function toForm(src) {
  const out = {}
  FIELDS.forEach(f => { out[f.key] = f.type === 'checkbox' ? src?.[f.key] === true : (src?.[f.key] ?? '') })
  return out
}

// Formulář → hodnoty k uložení (oříznuté; IBAN / BIC / DIČ / účet bez mezer, velkými písmeny).
function toValue(form) {
  const t = (k) => String(form[k] ?? '').trim()
  const compact = (k) => t(k).replace(/\s+/g, '')
  return {
    name: t('name'), ico: compact('ico'), dic: compact('dic').toUpperCase() || null, vat_payer: form.vat_payer === true,
    address: t('address'), register: t('register').replace(/\s+/g, ' '), register_short: t('register_short'), data_box: t('data_box'),
    bank_account: compact('bank_account'), bank_iban: compact('bank_iban').toUpperCase(), bank_name: t('bank_name'),
    bank_bic: compact('bank_bic').toUpperCase(),
    phone: t('phone'), email: t('email'), web: t('web'),
  }
}

// Smí se změnit provozovatel? Jen když KAŽDÝ už vystavený doklad nese vlastního vystavitele —
// doklad bez `issuer_snapshot` se renderuje z aktuálního nastavení a změna by ho přepsala.
async function issuedDocsAreFrozen() {
  const { data, error } = await supabase.from('invoices').select('id').is('issuer_snapshot', null).neq('type', 'received').limit(1)
  if (error) return false // sloupec ještě neexistuje (nasazení nedoběhlo) / nelze ověřit
  return !(data && data.length)
}

export default function CompanyTab() {
  const [values, setValues] = useState({})
  const [loaded, setLoaded] = useState(false)
  const [loadFailed, setLoadFailed] = useState(false)
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState(null)
  const base = useRef(null) // hodnota z DB, ze které formulář vznikl (kontrola souběžné změny při uložení)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      // řádek v DB ještě není → předvyplní se záložní údaje provozovatele
      base.current = await readCompanyInfo()
      setValues(toForm(base.current || OPERATOR))
      setLoadFailed(false)
    } catch (e) {
      setLoadFailed(true)
      setMsg({ type: 'error', text: `Firemní údaje se nepodařilo načíst: ${e.message}` })
    }
    setLoaded(true)
  }

  async function save() {
    setMsg(null)
    setSaving(true)
    try {
      const current = await readCompanyInfo()
      // Údaje se od načtení formuláře změnily (jiný uživatel / nasazení) → nepřepisuj je starým formulářem.
      if (FIELDS.some(f => String(base.current?.[f.key] ?? '') !== String(current?.[f.key] ?? ''))) {
        base.current = current
        setValues(toForm(current || OPERATOR))
        setMsg({ type: 'error', text: 'Firemní údaje se mezitím změnily (jiný uživatel nebo nasazení). Načetly se aktuální hodnoty — zkontrolujte je a uložte znovu.' })
        return
      }
      const next = toValue(values)
      const errs = validateCompanyInfo(next)
      if (errs.length) { setMsg({ type: 'error', text: errs.join(' ') }); return }
      const same = (k) => String(current?.[k] ?? '') === String(next[k] ?? '') || (k === 'vat_payer' && (current?.[k] === true) === next[k])
      const identityChanged = !current || IDENTITY_KEYS.some(k => !same(k))
      if (identityChanged && !(await issuedDocsAreFrozen())) {
        setMsg({ type: 'error', text: 'Změnu provozovatele nebo účtu teď nelze uložit: některé už vystavené doklady nemají uloženého vystavitele (invoices.issuer_snapshot) a změna by je přepsala. Počkejte na dokončení nasazení databáze, případně kontaktujte správce.' })
        return
      }
      const value = { ...(current || {}), ...next }
      // Nový provozovatel / účet platí od teď: smlouvy a VOP vystavené dřív se dál otevírají z uložených souborů.
      if (identityChanged) value.valid_from = new Date().toISOString()
      const res = await debugAction('company.save', 'CompanyTab', () =>
        supabase.from('app_settings').upsert({ key: 'company_info', value }, { onConflict: 'key' }), value)
      if (res?.error) throw new Error(res.error.message)
      setCompanyInfoCache(value)
      base.current = value
      setValues(toForm(value))
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'company_info_updated', entity_type: 'app_settings', old_data: current, new_data: value })
      } catch { /* audit je best-effort */ }
      purgeWebCache() // web čte company_info (JSON-LD) přes file-cache
      setMsg({ type: 'ok', text: 'Firemní údaje uloženy.' })
    } catch (e) {
      setMsg({ type: 'error', text: `Uložení selhalo: ${e.message}` })
    } finally {
      setSaving(false)
    }
  }

  if (!loaded) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div className="max-w-lg">
      <Card>
        <div className="p-3 rounded-lg mb-4" style={{ background: '#fef3c7', border: '1px solid #fbbf24' }}>
          <p className="text-sm font-bold" style={{ color: '#78350f' }}>{WARNING}</p>
        </div>
        {GROUPS.map((g, gi) => (
          <div key={g.title} className={gi > 0 ? 'mt-5' : ''}>
            <div className="text-sm font-bold mb-4" style={{ color: '#0f1a14' }}>{g.title}</div>
            <div className="space-y-3">
              {g.fields.map(f => f.type === 'checkbox' ? (
                <label key={f.key} className="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" checked={values[f.key] === true} onChange={e => setValues(v => ({ ...v, [f.key]: e.target.checked }))} />
                  <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{f.label}</span>
                </label>
              ) : (
                <div key={f.key}>
                  <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{f.label}</label>
                  {f.type === 'textarea' ? (
                    <textarea rows={2} value={values[f.key] || ''} onChange={e => setValues(v => ({ ...v, [f.key]: e.target.value }))}
                      className="w-full rounded-btn text-sm outline-none"
                      style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }} />
                  ) : (
                    <input value={values[f.key] || ''} onChange={e => setValues(v => ({ ...v, [f.key]: e.target.value }))}
                      className="w-full rounded-btn text-sm outline-none"
                      style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
                  )}
                </div>
              ))}
            </div>
          </div>
        ))}
        {msg && (
          <div className="mt-4 p-3 rounded-card" style={{ background: msg.type === 'ok' ? '#dcfce7' : '#fee2e2', color: msg.type === 'ok' ? '#166534' : '#dc2626', fontSize: 13 }}>{msg.text}</div>
        )}
        <div className="mt-5">
          <Button green onClick={save} disabled={saving || loadFailed}>{saving ? 'Ukládám…' : 'Uložit údaje'}</Button>
        </div>
      </Card>
    </div>
  )
}
