import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { purgeWebCache } from '../../lib/webCache'
import { useIsMobile } from '../../hooks/useIsMobile'
import { Table, TRow, TH, TD } from '../ui/Table'
import Button from '../ui/Button'
import ConfirmDialog from '../ui/ConfirmDialog'
import GearPriceModal from './GearPriceModal'
import GearExample from './GearExample'
import GearSettingsCard from './GearSettingsCard'
import { czk, itemsSum, audit, Pill } from './gearShared'

// Záložka „Ceník“: kusy + komplety (gear_rental_prices), příklad výpočtu, nastavení webu.

function contentOf(p, prices) {
  if (p.kind !== 'set') return (p.sizes || []).length ? p.sizes.join(', ') : 'bez velikosti'
  return (p.includes || []).map(k => prices.find(x => x.key === k)?.label || `${k} (chybí)`).join(' + ')
}

function SetNote({ p, prices }) {
  if (p.kind !== 'set') return null
  const sum = itemsSum(prices, p.includes)
  const price = Number(p.price_per_day)
  return price < sum
    ? <div className="text-xs mt-0.5" style={{ color: '#1a8a18' }}>kusy zvlášť {czk(sum)} · ušetří {czk(sum - price)} / den</div>
    : <div className="text-xs mt-0.5 font-bold" style={{ color: '#b45309' }}>není levnější než kusy ({czk(sum)}) — neuplatní se</div>
}

function ActiveToggle({ p, busy, onToggle }) {
  return (
    <button type="button" disabled={busy} onClick={() => onToggle(p)}
      className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer border-none whitespace-nowrap max-lg:min-h-[36px]"
      style={{ padding: '4px 10px', background: p.is_active ? '#dcfce7' : '#f3f4f6', color: p.is_active ? '#1a8a18' : '#6b7a72', opacity: busy ? 0.5 : 1 }}>
      {p.is_active ? '● Aktivní' : '○ Skryto'}
    </button>
  )
}

const BTN_EDIT = { padding: '4px 10px', background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }
const BTN_DEL = { padding: '4px 10px', background: '#fee2e2', color: '#dc2626', border: 'none' }

export default function GearPriceList({ prices, loading, error, reload }) {
  const isMobile = useIsMobile()
  const [edit, setEdit] = useState(null) // { row } | { kind }
  const [del, setDel] = useState(null)
  const [busy, setBusy] = useState(null)
  const [err, setErr] = useState(null)

  async function toggleActive(p) {
    setBusy(p.key); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const next = !p.is_active
      const result = await debugAction('gear_rental_prices.toggle', 'GearPriceList', () =>
        supabase.from('gear_rental_prices').update({ is_active: next, updated_by: user?.id || null }).eq('key', p.key), { key: p.key, is_active: next })
      if (result?.error) throw new Error(result.error.message)
      await audit('gear_rental_price_updated', 'gear_rental_prices', null, { key: p.key, is_active: p.is_active }, { key: p.key, is_active: next })
      purgeWebCache()
      await reload()
    } catch (e) {
      setErr(`Změna selhala: ${e.message}`)
    }
    setBusy(null)
  }

  async function handleDelete(p) {
    setDel(null); setErr(null)
    try {
      const result = await debugAction('gear_rental_prices.delete', 'GearPriceList', () =>
        supabase.from('gear_rental_prices').delete().eq('key', p.key).select('key'), { key: p.key })
      if (result?.error) throw new Error(result.error.message)
      if (!result?.data?.length) throw new Error('nic se nesmazalo (chybí oprávnění?)')
      await audit('gear_rental_price_deleted', 'gear_rental_prices', null,
        { key: p.key, kind: p.kind, label: p.label, price_per_day: p.price_per_day, sizes: p.sizes, includes: p.includes }, { key: p.key })
      purgeWebCache()
      await reload()
    } catch (e) {
      setErr(`Smazání selhalo: ${e.message}`)
    }
  }

  function askDelete(p) {
    const inSets = prices.filter(s => s.kind === 'set' && (s.includes || []).includes(p.key))
    if (inSets.length) {
      setErr(`„${p.label}“ je součástí kompletu ${inSets.map(s => `„${s.label}“`).join(', ')} — nejdřív ho z kompletu odeber (nebo kus jen skryj).`)
      return
    }
    setDel(p)
  }

  const actions = p => (
    <div className="flex gap-2 justify-end">
      <button type="button" onClick={() => setEdit({ row: p })} className="rounded-btn text-sm font-bold cursor-pointer max-lg:min-h-[36px]" style={BTN_EDIT}>Upravit</button>
      <button type="button" onClick={() => askDelete(p)} className="rounded-btn text-sm font-bold cursor-pointer max-lg:min-h-[36px]" style={BTN_DEL}>Smazat</button>
    </div>
  )

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <Button green onClick={() => setEdit({ kind: 'item' })} className="max-lg:min-h-[40px]">+ Nový kus</Button>
        <Button onClick={() => setEdit({ kind: 'set' })} className="max-lg:min-h-[40px]">+ Nový komplet</Button>
      </div>

      {(err || error) && <p className="text-sm" style={{ color: '#dc2626' }}>{err || error}</p>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : prices.length === 0 ? (
        <div className="bg-white rounded-card shadow-card text-sm text-center" style={{ padding: 24, color: '#1a2e22' }}>Ceník je prázdný — přidej kus výbavy.</div>
      ) : isMobile ? (
        <div className="space-y-2">
          {prices.map(p => (
            <div key={p.key} className="bg-white rounded-card shadow-card" style={{ padding: 12, opacity: p.is_active ? 1 : 0.65 }}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-extrabold" style={{ color: '#0f1a14' }}>{p.label}</div>
                  <div className="text-xs font-mono" style={{ color: '#6b7a72' }}>{p.key} · pořadí {p.sort_order}</div>
                </div>
                <div className="text-right shrink-0">
                  <div className="font-extrabold" style={{ color: '#0f1a14' }}>{czk(p.price_per_day)}<span className="text-xs font-semibold"> / den</span></div>
                  <Pill {...(p.kind === 'set' ? { label: 'Komplet', color: '#7c3aed', bg: '#ede9fe' } : { label: 'Kus', color: '#1a2e22', bg: '#f1faf7' })} />
                </div>
              </div>
              {p.description && <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>{p.description}</div>}
              <div className="text-sm mt-1" style={{ color: '#1a2e22', overflowWrap: 'anywhere' }}>{contentOf(p, prices)}</div>
              <SetNote p={p} prices={prices} />
              <div className="flex items-center justify-between gap-2 mt-2">
                <ActiveToggle p={p} busy={busy === p.key} onToggle={toggleActive} />
                {actions(p)}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <Table>
          <thead>
            <TRow header><TH>Pořadí</TH><TH>Název</TH><TH>Typ</TH><TH>Velikosti / obsahuje</TH><TH>Kč / den</TH><TH>Stav</TH><TH></TH></TRow>
          </thead>
          <tbody>
            {prices.map(p => (
              <TRow key={p.key}>
                <TD mono>{p.sort_order}</TD>
                <TD style={{ opacity: p.is_active ? 1 : 0.6 }}>
                  <div className="font-bold">{p.label}</div>
                  <div className="text-xs font-mono" style={{ color: '#6b7a72' }}>{p.key}</div>
                  {p.description && <div className="text-xs" style={{ color: '#1a2e22' }}>{p.description}</div>}
                </TD>
                <TD><Pill {...(p.kind === 'set' ? { label: 'Komplet', color: '#7c3aed', bg: '#ede9fe' } : { label: 'Kus', color: '#1a2e22', bg: '#f1faf7' })} /></TD>
                <TD style={{ maxWidth: 320 }}>{contentOf(p, prices)}<SetNote p={p} prices={prices} /></TD>
                <TD bold>{czk(p.price_per_day)}</TD>
                <TD><ActiveToggle p={p} busy={busy === p.key} onToggle={toggleActive} /></TD>
                <TD>{actions(p)}</TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}

      {!loading && prices.length > 0 && <GearExample prices={prices} />}
      <GearSettingsCard />

      {edit && (
        <GearPriceModal row={edit.row} kind={edit.kind} prices={prices}
          onClose={() => setEdit(null)} onSaved={() => { setEdit(null); reload() }} />
      )}
      {del && (
        <ConfirmDialog open danger title="Smazat z ceníku?"
          message={`„${del.label}“ (${del.key}) zmizí z ceníku i z nabídky na webu. Už vytvořené výpůjčky zůstanou beze změny. Pokud ho chceš nabízet později, raději ho jen skryj.`}
          onConfirm={() => handleDelete(del)} onCancel={() => setDel(null)} />
      )}
    </div>
  )
}
