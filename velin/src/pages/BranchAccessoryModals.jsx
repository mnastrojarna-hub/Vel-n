import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { FALLBACK_ACCESSORY_TYPES, accSku, fetchInventoryMap, deductFromWarehouse, Spinner } from './BranchHelpers'

// ─── Fill All Modal ──────────────────────────────────────────────
function FillAllModal({ branchId, branchName, accessories, accTypes, onClose, onDone }) {
  const [invMap, setInvMap] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    fetchInventoryMap().then(map => { setInvMap(map); setLoading(false) })
  }, [])

  if (loading || !invMap) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.3)' }}>
        <div className="rounded-card" style={{ background: '#fff', padding: 24, minWidth: 360 }}>
          <Spinner />
        </div>
      </div>
    )
  }

  const existingMap = {}
  accessories.forEach(a => { existingMap[`${a.type}-${a.size}`] = a.quantity || 0 })

  const lines = []
  let canFill = 0, missing = 0
  accTypes.forEach(at => {
    at.sizes.forEach(size => {
      const sku = accSku(at.key, size)
      const inv = invMap[sku]
      const stock = inv?.stock || 0
      const current = existingMap[`${at.key}-${size}`] || 0
      const toAdd = current === 0 ? Math.min(1, stock) : 0
      lines.push({ type: at.key, size, label: at.label, stock, current, toAdd, sku, is_consumable: at.is_consumable })
      if (toAdd > 0) canFill++
      if (stock === 0 && current === 0) missing++
    })
  })

  async function handleConfirm() {
    setSaving(true)
    try {
      const rows = []
      for (const l of lines) {
        if (l.toAdd > 0) {
          const ok = await deductFromWarehouse(l.sku, l.toAdd, branchName)
          if (!ok) continue
        }
        rows.push({ branch_id: branchId, type: l.type, size: l.size, quantity: l.current + l.toAdd })
      }
      if (rows.length > 0) {
        const { error } = await supabase
          .from('branch_accessories')
          .upsert(rows, { onConflict: 'branch_id,type,size' })
        if (error) throw error
      }
      onDone()
    } catch (e) { alert('Chyba: ' + e.message) } finally { setSaving(false) }
  }

  const fillLines = lines.filter(l => l.toAdd > 0)
  const missingLines = lines.filter(l => l.stock === 0 && l.current === 0)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.3)' }}>
      <div className="rounded-card" style={{ background: '#fff', padding: 24, minWidth: 380, maxWidth: 500, maxHeight: '80vh', overflow: 'auto' }}>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          Naplnit pobočku ze skladu
        </h3>

        {fillLines.length > 0 && (
          <div className="mb-3">
            <div className="text-sm font-bold mb-1" style={{ color: '#1a8a18' }}>
              Doplní se ({fillLines.length}):
            </div>
            {fillLines.map(l => (
              <div key={`${l.type}-${l.size}`} className="flex items-center justify-between text-sm py-1"
                style={{ borderBottom: '1px solid #d4e8e0' }}>
                <span>{l.label} {l.size}{l.is_consumable ? ' (spotřební)' : ''}</span>
                <span style={{ color: '#1a8a18' }}>+{l.toAdd} ks (sklad: {l.stock})</span>
              </div>
            ))}
          </div>
        )}

        {missingLines.length > 0 && (
          <div className="mb-3">
            <div className="text-sm font-bold mb-1" style={{ color: '#dc2626' }}>
              Chybí na skladě ({missingLines.length}):
            </div>
            {missingLines.map(l => (
              <div key={`${l.type}-${l.size}`} className="text-sm py-1"
                style={{ color: '#dc2626', borderBottom: '1px solid #fee2e2' }}>
                {l.label} {l.size} — 0 ks na skladě
              </div>
            ))}
          </div>
        )}

        {fillLines.length === 0 && missingLines.length === 0 && (
          <div className="text-sm py-2" style={{ color: '#1a2e22' }}>
            Všechny položky jsou již na pobočce.
          </div>
        )}

        {fillLines.length === 0 && missingLines.length > 0 && (
          <div className="text-sm py-2 font-bold" style={{ color: '#dc2626' }}>
            Sklad je prázdný — nelze naplnit. Doplňte sklad přes příjem zboží.
          </div>
        )}

        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onClose}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '6px 14px', background: '#f1faf7', color: '#1a2e22' }}>
            Zavřít
          </button>
          {fillLines.length > 0 && (
            <button onClick={handleConfirm} disabled={saving}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '6px 14px', background: '#1a2e22', color: '#74FB71', opacity: saving ? 0.5 : 1 }}>
              {saving ? 'Přenáším...' : `Potvrdit (${canFill} položek)`}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// ─── Manage Accessory Types Modal ────────────────────────────────
function ManageTypesModal({ onClose, onSaved }) {
  const [types, setTypes] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [editForm, setEditForm] = useState(null)
  const [err, setErr] = useState(null)

  useEffect(() => { loadTypes() }, [])

  async function loadTypes() {
    setLoading(true)
    const { data, error } = await supabase
      .from('accessory_types').select('*').order('sort_order')
    if (!error && data) setTypes(data)
    else setTypes(FALLBACK_ACCESSORY_TYPES)
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const f = editForm
      const sizesArr = f.sizesText.split(',').map(s => s.trim()).filter(Boolean)
      if (!f.key || !f.label || sizesArr.length === 0) { setErr('Vyplňte klíč, název a velikosti'); return }
      const priceVal = Math.max(0, parseInt(f.price_czk, 10) || 0)
      const unitVal = f.pricing_unit || 'per_booking'
      const row = {
        key: f.key, label: f.label, sizes: sizesArr,
        is_consumable: f.is_consumable, sort_order: f.sort_order || 0,
        price_czk: priceVal, pricing_unit: unitVal,
        audience: f.audience || 'adult',
      }
      if (f.id) {
        const { error } = await supabase.from('accessory_types').update(row).eq('id', f.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('accessory_types').insert(row)
        if (error) throw error
        // auto-create inventory items for new type
        const invRows = sizesArr.map(size => ({
          name: `${f.label} ${size}`, sku: accSku(f.key, size),
          category: 'prislusenstvi', stock: 0, min_stock: f.is_consumable ? 5 : 2, unit_price: 0,
        }))
        await supabase.from('inventory').upsert(invRows, { onConflict: 'sku', ignoreDuplicates: true })
      }
      setEditForm(null); loadTypes()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function handleToggleActive(t) {
    await supabase.from('accessory_types').update({ is_active: !t.is_active }).eq('id', t.id)
    loadTypes()
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.3)' }}>
      <div className="rounded-card" style={{ background: '#fff', padding: 24, minWidth: 420, maxWidth: 540, maxHeight: '80vh', overflow: 'auto' }}>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          Správa typů příslušenství
        </h3>

        {loading ? <Spinner /> : (
          <div className="space-y-2 mb-4">
            {types.map(t => (
              <div key={t.id || t.key} className="flex items-center justify-between rounded-lg"
                style={{ padding: '6px 10px', background: t.is_active !== false ? '#f1faf7' : '#f5f5f5', border: '1px solid #d4e8e0' }}>
                <div>
                  <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{t.label}</span>
                  {t.is_consumable && (
                    <span className="text-xs font-bold ml-2 rounded-btn" style={{ padding: '1px 6px', background: '#fef3c7', color: '#92400e' }}>
                      spotřební
                    </span>
                  )}
                  <div className="text-xs" style={{ color: '#1a2e22', opacity: 0.5 }}>
                    {t.key} — {(t.sizes || []).join(', ')}
                  </div>
                  <div className="text-xs mt-0.5" style={{ color: '#1a2e22' }}>
                    <strong>{(t.price_czk || 0)} Kč</strong>
                    <span style={{ opacity: 0.5 }}>
                      {' · '}
                      {t.pricing_unit === 'per_day' ? 'za den'
                        : t.pricing_unit === 'free' ? 'zdarma'
                        : 'za rezervaci'}
                      {' · '}
                      {t.audience === 'child' ? '👶 dětské'
                        : t.audience === 'both' ? '👤👶 obojí'
                        : '👤 dospělé'}
                    </span>
                  </div>
                </div>
                <div className="flex gap-1">
                  <button onClick={() => setEditForm({
                    id: t.id, key: t.key, label: t.label,
                    sizesText: (t.sizes || []).join(', '),
                    is_consumable: !!t.is_consumable, sort_order: t.sort_order || 0,
                    price_czk: typeof t.price_czk === 'number' ? t.price_czk : 0,
                    pricing_unit: t.pricing_unit || 'per_booking',
                    audience: t.audience || 'adult',
                  })}
                    className="rounded-btn text-xs font-bold cursor-pointer border-none"
                    style={{ padding: '3px 8px', background: '#dbeafe', color: '#2563eb' }}>
                    Upravit
                  </button>
                  {t.id && (
                    <button onClick={() => handleToggleActive(t)}
                      className="rounded-btn text-xs font-bold cursor-pointer border-none"
                      style={{ padding: '3px 8px', background: t.is_active !== false ? '#fee2e2' : '#dcfce7', color: t.is_active !== false ? '#dc2626' : '#1a8a18' }}>
                      {t.is_active !== false ? 'Deaktivovat' : 'Aktivovat'}
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {editForm ? (
          <div className="space-y-2 p-3 rounded-lg mb-3" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>
              {editForm.id ? 'Upravit typ' : 'Nový typ'}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Klíč (slug)</label>
                <input value={editForm.key} disabled={!!editForm.id}
                  onChange={e => setEditForm(f => ({ ...f, key: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '') }))}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} placeholder="ubrousky" />
              </div>
              <div>
                <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Název</label>
                <input value={editForm.label}
                  onChange={e => setEditForm(f => ({ ...f, label: e.target.value }))}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} placeholder="Ubrousky" />
              </div>
            </div>
            <div>
              <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Velikosti (čárkou)</label>
              <input value={editForm.sizesText}
                onChange={e => setEditForm(f => ({ ...f, sizesText: e.target.value }))}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} placeholder="UNI nebo XS, S, M, L, XL, XXL" />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Cena (Kč)</label>
                <input type="number" min={0} step={1} value={editForm.price_czk}
                  onChange={e => setEditForm(f => ({ ...f, price_czk: e.target.value }))}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} placeholder="0" />
              </div>
              <div>
                <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Jednotka</label>
                <select value={editForm.pricing_unit}
                  onChange={e => setEditForm(f => ({ ...f, pricing_unit: e.target.value }))}
                  className="w-full rounded-btn text-sm outline-none cursor-pointer"
                  style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }}>
                  <option value="per_booking">Za rezervaci</option>
                  <option value="per_day">Za den</option>
                  <option value="free">Zdarma (informativní)</option>
                </select>
              </div>
            </div>
            <div className="text-xs" style={{ color: '#92400e', background: '#fef3c7', padding: '6px 10px', borderRadius: 6 }}>
              Změna ceny ovlivní jen <strong>nové rezervace</strong>. Stávající rezervace mají cenu uloženou v <code>bookings.total_price</code> a faktury/refundy z ní vychází.
            </div>
            <div>
              <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>
                Pro koho (web filtruje podle license_required motorky — N = dětská)
              </label>
              <select value={editForm.audience}
                onChange={e => setEditForm(f => ({ ...f, audience: e.target.value }))}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }}>
                <option value="adult">👤 Dospělé velikosti</option>
                <option value="child">👶 Dětské velikosti</option>
                <option value="both">👤👶 Obojí (dospělý + dětský)</option>
              </select>
            </div>
            <div className="flex items-center gap-3">
              <label className="flex items-center gap-1 cursor-pointer">
                <input type="checkbox" checked={editForm.is_consumable}
                  onChange={e => setEditForm(f => ({ ...f, is_consumable: e.target.checked }))} />
                <span className="text-sm font-bold" style={{ color: '#92400e' }}>Spotřební zboží</span>
              </label>
              <div>
                <label className="text-xs font-bold mr-1" style={{ color: '#1a2e22' }}>Řazení:</label>
                <input type="number" value={editForm.sort_order} style={{ width: 50, padding: '4px 6px', border: '1px solid #d4e8e0', borderRadius: 6 }}
                  onChange={e => setEditForm(f => ({ ...f, sort_order: parseInt(e.target.value) || 0 }))} />
              </div>
            </div>
            {err && <div className="text-sm" style={{ color: '#dc2626' }}>{err}</div>}
            <div className="flex gap-2">
              <button onClick={() => setEditForm(null)}
                className="rounded-btn text-sm font-bold cursor-pointer border-none"
                style={{ padding: '5px 12px', background: '#f1faf7', color: '#1a2e22' }}>Zrušit</button>
              <button onClick={handleSave} disabled={saving}
                className="rounded-btn text-sm font-bold cursor-pointer border-none"
                style={{ padding: '5px 12px', background: '#1a2e22', color: '#74FB71' }}>
                {saving ? 'Ukládám...' : 'Uložit'}
              </button>
            </div>
          </div>
        ) : (
          <button onClick={() => setEditForm({ key: '', label: '', sizesText: 'UNI', is_consumable: true, sort_order: types.length + 1, price_czk: 0, pricing_unit: 'per_booking', audience: 'adult' })}
            className="rounded-btn text-sm font-bold cursor-pointer border-none mb-3"
            style={{ padding: '6px 14px', background: '#1a2e22', color: '#74FB71' }}>
            + Nový typ
          </button>
        )}

        <div className="flex justify-end mt-3">
          <button onClick={onSaved}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '6px 14px', background: '#f1faf7', color: '#1a2e22' }}>
            Zavřít
          </button>
        </div>
      </div>
    </div>
  )
}

export { FillAllModal, ManageTypesModal }
