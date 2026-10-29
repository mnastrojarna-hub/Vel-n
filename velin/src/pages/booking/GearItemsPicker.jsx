// Výběr kusů výbavy a velikostí pro výpůjčku JEN výbavy ve Velínu (Nová rezervace → „Jen výbava“,
// Upravit rezervaci výbavy). Ceník = aktivní kusy gear_rental_prices, na samoobslužné pobočce jen velikosti
// v limitech (lib/bookingKind selfServiceSizeOk). Volné kusy = get_gear_rental_availability (jen když je
// zapnutá kontrola skladu; ve Velínu jen informace — admin RPC vrací varování, ne chybu).
// Cena = server (quote_gear_booking / admin_update_gear_booking dry-run), klient nic nepočítá.
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { GEAR_KEYS, GEAR_LABELS, gearSizeCatalog, gearItemsPayload } from '../../lib/bookingKind'

const czk = n => `${(Number(n) || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`

/** Aktivní kusy ceníku výbavy (kind = item) v pořadí ceníku. */
export function useGearPrices() {
  const [prices, setPrices] = useState(null)
  useEffect(() => {
    let alive = true
    supabase.from('gear_rental_prices').select('*').eq('kind', 'item').eq('is_active', true).order('sort_order')
      .then(({ data }) => { if (alive) setPrices(data || []) }, () => { if (alive) setPrices([]) })
    return () => { alive = false }
  }, [])
  return prices
}

/** Volné kusy na pobočce v termínu: {helmet:{M:2,…},…} nebo null (kontrola skladu vypnutá / chyba). */
export function useGearAvailability(branchId, start, end) {
  const [sizes, setSizes] = useState(null)
  useEffect(() => {
    if (!branchId || !start || !end) { setSizes(null); return }
    let alive = true
    supabase.rpc('get_gear_rental_availability', { p_branch_id: branchId, p_start: start, p_end: end })
      .then(({ data, error }) => { if (alive) setSizes(!error && data?.enabled && data.sizes ? data.sizes : null) }, () => { if (alive) setSizes(null) })
    return () => { alive = false }
  }, [branchId, start, end])
  return sizes
}

/** Nezávazné nacenění (quote_gear_booking) — {loading, data, error}; dotaz se zpožděním po změně výběru. */
export function useGearQuote(branchId, start, end, selection) {
  const [state, setState] = useState({ loading: false, data: null })
  const key = JSON.stringify(gearItemsPayload(selection))
  useEffect(() => {
    const items = gearItemsPayload(selection)
    if (!branchId || !start || !end || !items.length) { setState({ loading: false, data: null }); return }
    let alive = true
    setState(s => ({ ...s, loading: true }))
    const t = setTimeout(() => {
      supabase.rpc('quote_gear_booking', { p_branch_id: branchId, p_start: start, p_end: end, p_items: items })
        .then(({ data, error }) => { if (alive) setState({ loading: false, data: error ? { error: error.message } : data }) },
          e => { if (alive) setState({ loading: false, data: { error: e?.message || 'quote failed' } }) })
    }, 350)
    return () => { alive = false; clearTimeout(t) }
  }, [branchId, start, end, key]) // eslint-disable-line react-hooks/exhaustive-deps
  return state
}

const box = { padding: '6px 10px', borderRadius: 8, border: '1px solid #b6dccb', fontSize: 14, fontWeight: 700, background: '#fff' }

/** selection = {helmet:'M',…}; onChange(nová selection). `free` = výsledek useGearAvailability. */
export default function GearItemsPicker({ prices, selection, onChange, selfService = false, free = null, disabled = false }) {
  if (prices == null) return <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
  const catalog = gearSizeCatalog(prices, selfService)
  const items = prices.filter(p => GEAR_KEYS.includes(p.key))
  if (!items.length) return <p className="text-sm" style={{ color: '#b45309' }}>Ceník výbavy nemá žádný aktivní kus (Flotila → Půjčení oblečení).</p>
  const set = (k, v) => { const n = { ...selection }; if (v) n[k] = v; else delete n[k]; onChange(n) }
  return (
    <div className="space-y-2">
      {items.map(p => {
        const sizes = catalog[p.key] || []
        const on = !!selection[p.key]
        const freeOf = s => (free && free[p.key] && Object.prototype.hasOwnProperty.call(free[p.key], s) ? Number(free[p.key][s]) : null)
        const cur = selection[p.key]
        const curFree = on ? freeOf(cur) : null
        const outOfCatalog = on && sizes.length > 0 && !sizes.includes(cur)
        return (
          <div key={p.key} className="flex items-center gap-3 p-2 rounded-lg max-sm:flex-wrap" style={{ background: on ? '#ecfeff' : '#f8faf9', border: `1px solid ${on ? '#67e8f9' : '#e5e7eb'}` }}>
            <label className="flex items-center gap-2 cursor-pointer flex-1 min-w-0">
              <input type="checkbox" checked={on} disabled={disabled || !sizes.length}
                onChange={e => set(p.key, e.target.checked ? (cur || sizes[0] || '') : null)}
                style={{ width: 20, height: 20, accentColor: '#0e7490' }} />
              <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{p.label || GEAR_LABELS[p.key]}</span>
              <span className="text-sm" style={{ color: '#4a5a52' }}>{czk(p.price_per_day)}/den</span>
            </label>
            {on && (
              <select value={cur} disabled={disabled} onChange={e => set(p.key, e.target.value)} style={box}>
                {outOfCatalog && <option value={cur}>{cur} (mimo ceník / limit)</option>}
                {sizes.map(s => { const f = freeOf(s); return <option key={s} value={s}>{s}{f != null ? ` · volno ${f}` : ''}</option> })}
              </select>
            )}
            {on && curFree != null && curFree <= 0 && <span className="text-xs font-bold" style={{ color: '#dc2626' }}>není volná</span>}
            {on && outOfCatalog && <span className="text-xs font-bold" style={{ color: '#b45309' }}>velikost mimo nabídku</span>}
          </div>
        )
      })}
      {selfService && <p className="text-xs" style={{ color: '#4a5a52' }}>Samoobslužná pobočka: jen velikosti v rozsahu výdeje (helma S–3XL, bunda/kalhoty/rukavice do 4XL).</p>}
    </div>
  )
}
