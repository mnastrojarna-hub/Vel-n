import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { purgeWebCache } from '../../lib/webCache'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import GearTranslations, { cleanTranslations } from './GearTranslations'
import { KEY_RE, INPUT, parseSizes, itemsSum, czk, audit } from './gearShared'

// Přidání / úprava řádku ceníku `gear_rental_prices`. Klíč a typ jsou po založení
// pevné (na klíč odkazují položky už vytvořených výpůjček).

function Label({ children, hint }) {
  return (
    <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
      {children}{hint && <span className="normal-case font-semibold tracking-normal" style={{ color: '#6b7a72' }}> — {hint}</span>}
    </label>
  )
}

function initForm(row, kind, prices) {
  if (row) {
    return {
      key: row.key, kind: row.kind, label: row.label || '', description: row.description || '',
      price: String(row.price_per_day ?? ''), sizesText: (row.sizes || []).join(', '),
      includes: [...(row.includes || [])], is_active: !!row.is_active,
      sort_order: String(row.sort_order ?? 0), translations: row.translations || {},
    }
  }
  const maxSort = prices.reduce((m, p) => Math.max(m, Number(p.sort_order) || 0), 0)
  return {
    key: '', kind, label: '', description: '', price: '',
    sizesText: '', includes: [], is_active: true, sort_order: String(maxSort + 10), translations: {},
  }
}

export default function GearPriceModal({ row, kind, prices, onClose, onSaved }) {
  const isNew = !row
  const [form, setForm] = useState(() => initForm(row, kind, prices))
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = patch => setForm(f => ({ ...f, ...patch }))
  const isSet = form.kind === 'set'
  const items = prices.filter(p => p.kind === 'item')
  // kusy kompletu v pořadí ceníku; klíče smazaných kusů se při uložení vypustí
  const includes = items.filter(i => form.includes.includes(i.key)).map(i => i.key)
  const missing = form.includes.filter(k => !items.some(i => i.key === k))
  const sum = itemsSum(prices, includes)
  const priceNum = Number(String(form.price).replace(',', '.'))

  function validate() {
    if (isNew) {
      if (!KEY_RE.test(form.key)) return 'Klíč: 2–40 znaků, malá písmena bez diakritiky, číslice a _ (začíná písmenem).'
      if (prices.some(p => p.key === form.key)) return `Klíč „${form.key}“ už v ceníku existuje.`
    }
    if (!form.label.trim()) return 'Vyplňte název.'
    if (String(form.price).trim() === '' || !Number.isFinite(priceNum) || priceNum < 0 || priceNum > 100000) return 'Cena za den musí být 0–100 000 Kč.'
    if (!/^-?\d+$/.test(String(form.sort_order).trim())) return 'Pořadí musí být celé číslo.'
    if (isSet && includes.length < 2) return 'Komplet musí obsahovat aspoň 2 kusy.'
    return null
  }

  async function save() {
    const v = validate()
    if (v) { setErr(v); return }
    setErr(null); setSaving(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        label: form.label.trim(),
        description: form.description.trim() || null,
        price_per_day: Math.round(priceNum * 100) / 100,
        sizes: isSet ? [] : parseSizes(form.sizesText),
        includes: isSet ? includes : [],
        is_active: form.is_active,
        sort_order: parseInt(form.sort_order, 10),
        translations: cleanTranslations(form.translations),
        updated_by: user?.id || null,
      }
      const result = isNew
        ? await debugAction('gear_rental_prices.create', 'GearPriceModal', () =>
            supabase.from('gear_rental_prices').insert({ key: form.key, kind: form.kind, ...payload }).select().single(), { key: form.key, ...payload })
        : await debugAction('gear_rental_prices.update', 'GearPriceModal', () =>
            supabase.from('gear_rental_prices').update(payload).eq('key', row.key).select().single(), { key: row.key, ...payload })
      if (result?.error) throw new Error(result.error.message)
      const { updated_by: _u, translations: _t, ...logged } = payload
      await audit(isNew ? 'gear_rental_price_created' : 'gear_rental_price_updated', 'gear_rental_prices', null,
        isNew ? null : { key: row.key, label: row.label, price_per_day: row.price_per_day, sizes: row.sizes, includes: row.includes, is_active: row.is_active, sort_order: row.sort_order },
        { key: form.key, kind: form.kind, ...logged })
      purgeWebCache()
      onSaved()
    } catch (e) {
      setErr(`Uložení selhalo: ${e.message}`)
    } finally {
      setSaving(false)
    }
  }

  const toggleInclude = k => set({ includes: form.includes.includes(k) ? form.includes.filter(x => x !== k) : [...form.includes, k] })

  return (
    <Modal open onClose={onClose} stickyHeader
      title={isNew ? (isSet ? 'Nový komplet' : 'Nový kus výbavy') : `Upravit: ${row.label}`}>
      <div className="space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <Label hint={isNew ? 'nelze později změnit' : 'pevný'}>Klíč</Label>
            <input value={form.key} disabled={!isNew} onChange={e => set({ key: e.target.value.toLowerCase().replace(/\s+/g, '_') })}
              placeholder={isSet ? 'např. set_summer' : 'např. vest'} className="w-full font-mono max-lg:min-h-[40px]"
              style={{ ...INPUT, opacity: isNew ? 1 : 0.6 }} />
          </div>
          <div>
            <Label>Typ</Label>
            <div className="text-sm font-bold" style={{ ...INPUT, background: '#fff' }}>{isSet ? 'Komplet (sada kusů)' : 'Kus výbavy'}</div>
          </div>
        </div>
        <div>
          <Label>Název (česky)</Label>
          <input value={form.label} onChange={e => set({ label: e.target.value })} className="w-full max-lg:min-h-[40px]" style={INPUT}
            placeholder={isSet ? 'např. Komplet bez bot' : 'např. Helma'} />
        </div>
        <div>
          <Label hint="nepovinné">Popis</Label>
          <input value={form.description} onChange={e => set({ description: e.target.value })} className="w-full max-lg:min-h-[40px]" style={INPUT}
            placeholder={isSet ? 'např. Helma, bunda, kalhoty a rukavice' : ''} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Cena Kč / den</Label>
            <input type="number" min="0" max="100000" step="1" value={form.price} onChange={e => set({ price: e.target.value })}
              className="w-full max-lg:min-h-[40px]" style={INPUT} />
          </div>
          <div>
            <Label hint="nižší = výš">Pořadí</Label>
            <input type="number" step="1" value={form.sort_order} onChange={e => set({ sort_order: e.target.value })}
              className="w-full max-lg:min-h-[40px]" style={INPUT} />
          </div>
        </div>

        {isSet ? (
          <div>
            <Label hint="min. 2">Obsahuje kusy</Label>
            <div className="flex flex-wrap gap-2">
              {items.map(it => {
                const on = form.includes.includes(it.key)
                return (
                  <label key={it.key} className="flex items-center gap-2 cursor-pointer rounded-btn text-sm font-bold max-lg:min-h-[40px]"
                    style={{ padding: '6px 10px', background: on ? '#74FB71' : '#f1faf7', border: `1px solid ${on ? '#74FB71' : '#d4e8e0'}`, color: '#1a2e22', opacity: it.is_active ? 1 : 0.6 }}>
                    <input type="checkbox" checked={on} onChange={() => toggleInclude(it.key)} className="accent-[#1a8a18]" />
                    {it.label} <span style={{ color: '#6b7a72', fontWeight: 600 }}>{czk(it.price_per_day)}</span>
                    {!it.is_active && <span style={{ color: '#b45309' }}>(neaktivní)</span>}
                  </label>
                )
              })}
            </div>
            {missing.length > 0 && (
              <p className="text-sm mt-2" style={{ color: '#b45309' }}>Neexistující kusy {missing.join(', ')} se při uložení z kompletu odeberou.</p>
            )}
            {includes.length >= 2 && (
              <p className="text-sm mt-2" style={{ color: Number.isFinite(priceNum) && priceNum < sum ? '#1a8a18' : '#b45309' }}>
                Kusy zvlášť: {czk(sum)} / den.{' '}
                {Number.isFinite(priceNum) && String(form.price).trim() !== '' && (priceNum < sum
                  ? `Komplet ušetří ${czk(sum - priceNum)} / den.`
                  : 'Komplet NENÍ levnější než kusy — web ho neuplatní a účtuje po kusech.')}
              </p>
            )}
          </div>
        ) : (
          <div>
            <Label hint="oddělené čárkou; prázdné = bez velikosti">Velikosti</Label>
            <input value={form.sizesText} onChange={e => set({ sizesText: e.target.value })} className="w-full max-lg:min-h-[40px]" style={INPUT}
              placeholder="S, M, L, XL, 2XL" />
          </div>
        )}

        <label className="flex items-center gap-2 cursor-pointer text-sm font-bold max-lg:min-h-[40px]" style={{ color: '#1a2e22' }}>
          <input type="checkbox" checked={form.is_active} onChange={e => set({ is_active: e.target.checked })} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
          Aktivní (nabízí se na webu)
        </label>

        <GearTranslations value={form.translations} onChange={translations => set({ translations })}
          showDesc={!!form.description.trim() || Object.values(form.translations || {}).some(t => t?.description)} />

        {err && <p className="text-sm" style={{ color: '#dc2626' }}>{err}</p>}
        <div className="flex gap-3 justify-end max-sm:flex-col-reverse">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        </div>
      </div>
    </Modal>
  )
}
