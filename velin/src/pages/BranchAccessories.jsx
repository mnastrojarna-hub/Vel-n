import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { FALLBACK_ACCESSORY_TYPES, loadAccessoryTypes, accSku, deductFromWarehouse, returnToWarehouse, Spinner } from './BranchHelpers'
import { FillAllModal, ManageTypesModal } from './BranchAccessoryModals'

function TabAccessories({ accessories, loading, branchId, branchName, onRefresh }) {
  const [showAdd, setShowAdd] = useState(false)
  const [editItem, setEditItem] = useState(null)
  const [saving, setSaving] = useState(false)
  const [showFillAll, setShowFillAll] = useState(false)
  const [showManageTypes, setShowManageTypes] = useState(false)
  const [accTypes, setAccTypes] = useState(FALLBACK_ACCESSORY_TYPES)

  useEffect(() => { loadAccessoryTypes().then(setAccTypes) }, [])

  if (loading) return <Spinner />

  const grouped = {}
  accTypes.forEach(at => { grouped[at.key] = [] })
  accessories.forEach(a => { if (grouped[a.type]) grouped[a.type].push(a) })

  const rentalTypes = accTypes.filter(t => !t.is_consumable)
  const consumableTypes = accTypes.filter(t => t.is_consumable)

  async function handleSaveAccessory(item) {
    setSaving(true)
    try {
      const sku = accSku(item.type, item.size)
      const oldQty = item.id ? (accessories.find(a => a.id === item.id)?.quantity || 0) : 0
      const delta = item.quantity - oldQty
      if (delta > 0) {
        const ok = await deductFromWarehouse(sku, delta, branchName)
        if (!ok) { alert(`Nedostatek na skladě pro ${item.type} ${item.size}.`); return }
      } else if (delta < 0) {
        const typeInfo = accTypes.find(t => t.key === item.type)
        if (!typeInfo?.is_consumable) await returnToWarehouse(sku, Math.abs(delta), branchName)
      }
      if (item.id) {
        const { error } = await supabase
          .from('branch_accessories').update({ quantity: item.quantity }).eq('id', item.id)
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('branch_accessories').upsert({
            branch_id: branchId, type: item.type, size: item.size, quantity: item.quantity,
          }, { onConflict: 'branch_id,type,size' })
        if (error) throw error
      }
      setEditItem(null); setShowAdd(false); onRefresh()
    } catch (e) { alert('Chyba: ' + e.message) } finally { setSaving(false) }
  }

  async function handleDeleteAccessory(id) {
    const acc = accessories.find(a => a.id === id)
    if (!acc) return
    const typeInfo = accTypes.find(t => t.key === acc.type)
    const msg = typeInfo?.is_consumable
      ? 'Smazat tuto spotřební položku?'
      : 'Smazat tuto položku? Množství se vrátí na sklad.'
    if (!window.confirm(msg)) return
    try {
      if (acc.quantity > 0 && !typeInfo?.is_consumable) {
        await returnToWarehouse(accSku(acc.type, acc.size), acc.quantity, branchName)
      }
      await supabase.from('branch_accessories').delete().eq('id', id)
      onRefresh()
    } catch (e) { alert('Chyba: ' + e.message) }
  }

  const totalItems = accessories.reduce((s, a) => s + (a.quantity || 0), 0)

  function renderTypeGroup(at) {
    const items = grouped[at.key] || []
    if (items.length === 0 && accessories.length > 0) return null
    return (
      <div key={at.key} className="mb-3">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
            {at.label}
          </span>
          {at.is_consumable && (
            <span className="text-xs font-bold rounded-btn" style={{ padding: '1px 6px', background: '#fef3c7', color: '#92400e' }}>
              spotřební
            </span>
          )}
        </div>
        {items.length === 0 ? (
          <div className="text-sm py-1" style={{ color: '#1a2e22', opacity: 0.5 }}>Žádné položky</div>
        ) : (
          <div className="flex flex-wrap gap-2">
            {items.sort((a, b) => a.size.localeCompare(b.size, 'cs', { numeric: true })).map(item => (
              <div key={item.id}
                className="flex items-center gap-2 rounded-lg cursor-pointer"
                style={{ padding: '4px 10px', background: item.quantity > 0 ? '#f1faf7' : '#fff5f5', border: '1px solid #d4e8e0' }}
                onClick={() => setEditItem(item)}>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{item.size}</span>
                <span className="text-sm font-extrabold" style={{ color: item.quantity > 0 ? '#1a8a18' : '#dc2626' }}>
                  {item.quantity} ks
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div className="text-sm" style={{ color: '#1a2e22' }}>
          <strong>{accessories.length}</strong> typů, <strong>{totalItems}</strong> kusů celkem
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowManageTypes(true)}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '5px 12px', background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }}>
            Správa typů
          </button>
          <button onClick={() => setShowFillAll(true)} disabled={saving}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '5px 12px', background: '#dbeafe', color: '#2563eb' }}>
            Naplnit vše
          </button>
          <button onClick={() => setShowAdd(true)}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '5px 12px', background: '#1a2e22', color: '#74FB71' }}>
            + Přidat
          </button>
        </div>
      </div>

      {rentalTypes.length > 0 && (
        <div className="mb-2">
          <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22', opacity: 0.5 }}>
            Půjčované
          </div>
          {rentalTypes.map(renderTypeGroup)}
        </div>
      )}
      {consumableTypes.length > 0 && (
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#92400e', opacity: 0.7 }}>
            Spotřební zboží
          </div>
          {consumableTypes.map(renderTypeGroup)}
        </div>
      )}

      {(showAdd || editItem) && (
        <AccessoryEditModal
          existing={editItem}
          branchId={branchId}
          branchName={branchName}
          accTypes={accTypes}
          onSave={handleSaveAccessory}
          onDelete={editItem?.id ? () => handleDeleteAccessory(editItem.id) : null}
          onClose={() => { setShowAdd(false); setEditItem(null) }}
          saving={saving}
        />
      )}
      {showFillAll && (
        <FillAllModal
          branchId={branchId}
          branchName={branchName}
          accessories={accessories}
          accTypes={accTypes}
          onClose={() => setShowFillAll(false)}
          onDone={() => { setShowFillAll(false); onRefresh() }}
        />
      )}
      {showManageTypes && (
        <ManageTypesModal
          onClose={() => setShowManageTypes(false)}
          onSaved={() => { loadAccessoryTypes().then(setAccTypes); setShowManageTypes(false) }}
        />
      )}
    </div>
  )

function AccessoryEditModal({ existing, branchId, branchName, accTypes, onSave, onDelete, onClose, saving }) {
  const [form, setForm] = useState({
    type: existing?.type || (accTypes[0]?.key || 'boots'),
    size: existing?.size || '',
    quantity: existing?.quantity ?? 0,
  })
  const [warehouseStock, setWarehouseStock] = useState(null)

  const typeConfig = accTypes.find(t => t.key === form.type)
  const isConsumable = !!typeConfig?.is_consumable

  useEffect(() => {
    if (!form.size) { setWarehouseStock(null); return }
    supabase.from('inventory').select('stock')
      .eq('sku', accSku(form.type, form.size)).single()
      .then(({ data }) => setWarehouseStock(data?.stock ?? 0))
  }, [form.type, form.size])

  const oldQty = existing?.quantity || 0
  const delta = form.quantity - oldQty
  const canSave = form.size && (delta <= 0 || (warehouseStock !== null && warehouseStock >= delta))

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.3)' }}>
      <div className="rounded-card" style={{ background: '#fff', padding: 24, minWidth: 320, maxWidth: 400 }}>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          {existing ? 'Upravit příslušenství' : 'Přidat příslušenství'}
        </h3>
        {isConsumable && (
          <div className="text-xs font-bold rounded-btn mb-2" style={{ padding: '3px 8px', background: '#fef3c7', color: '#92400e', display: 'inline-block' }}>
            Spotřební — při snížení se nevrací na sklad
          </div>
        )}
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</label>
            <select value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value, size: '' }))}
              disabled={!!existing}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              {accTypes.map(t => (
                <option key={t.key} value={t.key}>{t.label}{t.is_consumable ? ' (spotřební)' : ''}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Velikost</label>
            <select value={form.size} onChange={e => setForm(f => ({ ...f, size: e.target.value }))}
              disabled={!!existing}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              <option value="">Vyberte...</option>
              {(typeConfig?.sizes || []).map(s => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>
          {form.size && warehouseStock !== null && (
            <div className="text-sm rounded-btn" style={{ padding: '6px 10px',
              background: warehouseStock > 0 ? '#dcfce7' : '#fee2e2',
              color: warehouseStock > 0 ? '#1a8a18' : '#dc2626' }}>
              Sklad: <strong>{warehouseStock} ks</strong>
              {warehouseStock === 0 && ' — není na skladě'}
            </div>
          )}
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Počet kusů</label>
            <input type="number" min="0" value={form.quantity}
              onChange={e => setForm(f => ({ ...f, quantity: Math.max(0, parseInt(e.target.value) || 0) }))}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
          </div>
          {delta > 0 && warehouseStock !== null && warehouseStock < delta && (
            <div className="text-sm" style={{ color: '#dc2626' }}>
              Potřeba {delta} ks, na skladě pouze {warehouseStock} ks
            </div>
          )}
        </div>
        <div className="flex justify-between mt-4">
          <div>
            {onDelete && (
              <button onClick={() => { onDelete(); onClose() }}
                className="rounded-btn text-sm font-bold cursor-pointer border-none"
                style={{ padding: '6px 14px', background: '#fee2e2', color: '#dc2626' }}>
                Smazat
              </button>
            )}
          </div>
          <div className="flex gap-2">
            <button onClick={onClose}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '6px 14px', background: '#f1faf7', color: '#1a2e22' }}>
              Zrušit
            </button>
            <button
              onClick={() => onSave({ id: existing?.id, type: form.type, size: form.size, quantity: form.quantity })}
              disabled={saving || !canSave}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '6px 14px', background: '#1a2e22', color: '#74FB71', opacity: saving || !canSave ? 0.5 : 1 }}>
              {saving ? 'Ukládám...' : 'Uložit'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )

export { TabAccessories }
