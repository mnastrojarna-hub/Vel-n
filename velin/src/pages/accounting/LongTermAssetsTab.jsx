import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'
import { AddAssetModal, AssetDetailModal } from './LongTermAssetsModals'

const PER_PAGE = 25

const CATEGORIES = [
  { value: 'vehicles', label: 'Dopravni prostredky' },
  { value: 'machinery', label: 'Stroje a pristroje' },
  { value: 'buildings', label: 'Stavby' },
  { value: 'land', label: 'Pozemky' },
  { value: 'equipment', label: 'Vybaveni' },
  { value: 'intangible', label: 'Nehmotny majetek' },
]

// CZ depreciation groups per § 30 ZDP
const DEPRECIATION_GROUPS = [
  { value: 1, label: 'Skupina 1 (3 roky)', years: 3, firstYearRate: 20, nextYearRate: 40, accFirstRate: 14.2, accNextRate: 28.6 },
  { value: 2, label: 'Skupina 2 (5 let)', years: 5, firstYearRate: 11, nextYearRate: 22.25, accFirstRate: 8.5, accNextRate: 18.5 },
  { value: 3, label: 'Skupina 3 (10 let)', years: 10, firstYearRate: 5.5, nextYearRate: 10.5, accFirstRate: 4.3, accNextRate: 8.7 },
  { value: 4, label: 'Skupina 4 (20 let)', years: 20, firstYearRate: 2.15, nextYearRate: 5.15, accFirstRate: 1.4, accNextRate: 3.4 },
  { value: 5, label: 'Skupina 5 (30 let)', years: 30, firstYearRate: 1.4, nextYearRate: 3.4, accFirstRate: 1.0, accNextRate: 2.0 },
  { value: 6, label: 'Skupina 6 (50 let)', years: 50, firstYearRate: 1.02, nextYearRate: 2.02, accFirstRate: 0.5, accNextRate: 1.0 },
]

const DEPRECIATION_METHODS = [
  { value: 'linear', label: 'Rovnomerne (linearni)' },
  { value: 'accelerated', label: 'Zrychlene' },
]

export default function LongTermAssetsTab() {
  const debugMode = useDebugMode()
  const [assets, setAssets] = useState([])
  const [depreciations, setDepreciations] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)
  const [subTab, setSubTab] = useState('assets')
  const [generating, setGenerating] = useState(false)
  const [unlinkedMotos, setUnlinkedMotos] = useState([])
  const [addingMotoId, setAddingMotoId] = useState(null)

  useEffect(() => { load() }, [page, subTab])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      if (subTab === 'assets') {
        const { data, count, error: err } = await debugAction('long_term_assets.list', 'LongTermAssetsTab', () =>
          supabase.from('acc_long_term_assets').select('*', { count: 'exact' })
            .order('acquired_date', { ascending: false })
            .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        )
        if (err) throw err
        setAssets(data || [])
        setTotal(count || 0)

        // Check for fleet motorcycles not in long-term assets
        await checkUnlinkedMotorcycles()
      } else {
        const { data, count, error: err } = await debugAction('depreciations.list', 'LongTermAssetsTab', () =>
          supabase.from('acc_depreciation_entries').select('*, acc_long_term_assets(name)', { count: 'exact' })
            .order('year', { ascending: false })
            .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        )
        if (err) throw err
        setDepreciations(data || [])
        setTotal(count || 0)
      }
    } catch (e) {
      debugError('LongTermAssetsTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function checkUnlinkedMotorcycles() {
    try {
      const [motosRes, assetsRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, spz, vin, acquired_at, status'),
        supabase.from('acc_long_term_assets').select('motorcycle_id').not('motorcycle_id', 'is', null),
      ])
      const linkedIds = new Set((assetsRes.data || []).map(a => a.motorcycle_id))
      const unlinked = (motosRes.data || []).filter(m => !linkedIds.has(m.id) && m.status !== 'retired')
      setUnlinkedMotos(unlinked)
    } catch (e) {
      console.error('checkUnlinkedMotorcycles:', e)
    }
  }

  async function addMotoToAssets(moto) {
    setAddingMotoId(moto.id)
    try {
      const { error: err } = await supabase.from('acc_long_term_assets').insert({
        name: `${moto.model} (${moto.spz || moto.vin || ''})`,
        category: 'vehicles',
        purchase_price: 0,
        current_value: 0,
        total_depreciated: 0,
        acquired_date: moto.acquired_at || new Date().toISOString().slice(0, 10),
        depreciation_group: 2, // Sk. 2 = 5 let (dopravní prostředky)
        depreciation_method: 'accelerated',
        status: 'active',
        motorcycle_id: moto.id,
        missing_purchase_doc: true,
      })
      if (err) throw err
      await load()
    } catch (e) {
      setError('Chyba přidání motorky do majetku: ' + e.message)
    } finally {
      setAddingMotoId(null)
    }
  }

  async function generateDepreciation(year) {
    setGenerating(true)
    setError(null)
    try {
      const { data: allAssets } = await supabase.from('acc_long_term_assets').select('*')
        .eq('status', 'active')

      for (const asset of (allAssets || [])) {
        // Check if already generated
        const existing = await supabase.from('acc_depreciation_entries').select('id')
          .eq('asset_id', asset.id).eq('year', year).maybeSingle()
        if (existing.data) continue

        const group = DEPRECIATION_GROUPS.find(g => g.value === asset.depreciation_group)
        if (!group) continue

        // Count existing depreciation years
        const { count: depYears } = await supabase.from('acc_depreciation_entries').select('id', { count: 'exact', head: true })
          .eq('asset_id', asset.id)

        const isFirstYear = depYears === 0
        const yearNumber = (depYears || 0) + 1

        if (yearNumber > group.years) continue // Fully depreciated

        let annualAmount = 0
        const price = asset.purchase_price

        if (asset.depreciation_method === 'linear') {
          if (isFirstYear) {
            annualAmount = Math.round(price * group.firstYearRate / 100)
          } else {
            annualAmount = Math.round(price * group.nextYearRate / 100)
          }
        } else {
          // Accelerated depreciation
          const remainingValue = asset.current_value || price
          if (isFirstYear) {
            annualAmount = Math.round(price / group.years)
          } else {
            const remainingYears = group.years - yearNumber + 1
            annualAmount = Math.round((2 * remainingValue) / (remainingYears + 1))
          }
        }

        // Don't depreciate more than remaining value
        annualAmount = Math.min(annualAmount, asset.current_value || 0)
        const newValue = (asset.current_value || 0) - annualAmount
        const totalDepreciated = (asset.total_depreciated || 0) + annualAmount

        await supabase.from('acc_depreciation_entries').insert({
          asset_id: asset.id,
          year,
          year_number: yearNumber,
          annual_amount: annualAmount,
          cumulative_amount: totalDepreciated,
          remaining_value: newValue,
          method: asset.depreciation_method,
          depreciation_group: asset.depreciation_group,
        })

        await supabase.from('acc_long_term_assets').update({
          current_value: newValue,
          total_depreciated: totalDepreciated,
        }).eq('id', asset.id)

        // Auto accounting entry
        await supabase.from('accounting_entries').insert({
          type: 'expense',
          amount: annualAmount,
          description: `Odpis: ${asset.name} (rok ${yearNumber}/${group.years})`,
          category: 'odpisy',
          date: `${year}-12-31`,
        })
      }

      await load()
    } catch (e) {
      setError('Chyba generovani odpisu: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const totalPages = Math.ceil(total / PER_PAGE)
  const now = new Date()

  // Summary
  const totalPurchase = assets.reduce((s, a) => s + (a.purchase_price || 0), 0)
  const totalCurrent = assets.reduce((s, a) => s + (a.current_value || 0), 0)
  const totalDepreciated = assets.reduce((s, a) => s + (a.total_depreciated || 0), 0)

  return (
    <div>
      <div className="flex gap-2 mb-4">
        {['assets', 'depreciations'].map(t => (
          <button key={t} onClick={() => { setSubTab(t); setPage(1) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 14px', background: subTab === t ? '#1a2e22' : '#f1faf7', color: subTab === t ? '#74FB71' : '#1a2e22', border: 'none' }}>
            {t === 'assets' ? 'Majetek' : 'Odpisy'}
          </button>
        ))}
      </div>

      <div className="flex items-center gap-3 mb-4">
        {subTab === 'assets' && <Button green onClick={() => setShowAdd(true)}>+ Novy dlouhodoby majetek</Button>}
        {subTab === 'depreciations' && (
          <Button green onClick={() => generateDepreciation(now.getFullYear())} disabled={generating}>
            {generating ? 'Generuji...' : `Generovat odpisy ${now.getFullYear()}`}
          </Button>
        )}
      </div>

      {/* Warning: unlinked fleet motorcycles */}
      {subTab === 'assets' && unlinkedMotos.length > 0 && (
        <div className="mb-4 p-4 rounded-card" style={{ background: '#fef3c7', border: '1px solid #fcd34d' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>
            Motorky ve flotile bez zaneseni do majetku ({unlinkedMotos.length})
          </div>
          <div className="flex flex-wrap gap-2">
            {unlinkedMotos.map(m => (
              <div key={m.id} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #fcd34d' }}>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{m.model}</span>
                {m.spz && <span className="text-xs font-mono" style={{ color: '#6b7280' }}>{m.spz}</span>}
                <button onClick={() => addMotoToAssets(m)}
                  disabled={addingMotoId === m.id}
                  className="text-xs font-bold cursor-pointer rounded"
                  style={{ padding: '2px 8px', background: '#1a8a18', color: '#fff', border: 'none', opacity: addingMotoId === m.id ? 0.5 : 1 }}>
                  {addingMotoId === m.id ? '...' : '+ Pridat'}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {subTab === 'assets' && assets.length > 0 && (
        <div className="grid grid-cols-3 gap-3 mb-4">
          <MiniStat label="Porizovaci cena celkem" value={fmt(totalPurchase)} color="#1a2e22" />
          <MiniStat label="Zustat. hodnota celkem" value={fmt(totalCurrent)} color="#1a8a18" />
          <MiniStat label="Odepsano celkem" value={fmt(totalDepreciated)} color="#dc2626" />
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : subTab === 'assets' ? (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Nazev</TH><TH>Kategorie</TH><TH>Sk.</TH><TH>Metoda</TH>
                <TH>Poriz. cena</TH><TH>Zust. hodnota</TH><TH>Odepsano</TH><TH>Stav</TH><TH>Doklad</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {assets.map(a => {
                const group = DEPRECIATION_GROUPS.find(g => g.value === a.depreciation_group)
                const pct = a.purchase_price > 0 ? Math.round(((a.total_depreciated || 0) / a.purchase_price) * 100) : 0
                return (
                  <TRow key={a.id}>
                    <TD bold>{a.name}</TD>
                    <TD>{CATEGORIES.find(c => c.value === a.category)?.label || a.category}</TD>
                    <TD>{a.depreciation_group || '—'}</TD>
                    <TD>{a.depreciation_method === 'linear' ? 'Rovnom.' : 'Zrychl.'}</TD>
                    <TD>{fmt(a.purchase_price)}</TD>
                    <TD bold color="#1a8a18">{fmt(a.current_value)}</TD>
                    <TD color="#dc2626">{fmt(a.total_depreciated)} ({pct}%)</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                        style={{ padding: '4px 10px', background: a.status === 'active' ? '#dcfce7' : a.status === 'fully_depreciated' ? '#e0e7ff' : '#fee2e2', color: a.status === 'active' ? '#1a8a18' : a.status === 'fully_depreciated' ? '#4338ca' : '#dc2626' }}>
                        {a.status === 'active' ? 'Aktivni' : a.status === 'fully_depreciated' ? 'Odepsano' : 'Vyrazeno'}
                      </span>
                    </TD>
                    <TD>
                      {a.missing_purchase_doc ? (
                        <span className="text-xs font-bold" style={{ color: '#dc2626' }}>Chybi doklad</span>
                      ) : a.invoice_number ? (
                        <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>OK</span>
                      ) : (
                        <span className="text-xs" style={{ color: '#6b7280' }}>—</span>
                      )}
                    </TD>
                    <TD>
                      <button onClick={() => setDetail(a)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>Detail</button>
                    </TD>
                  </TRow>
                )
              })}
              {assets.length === 0 && <TRow><TD>Zadny dlouhodoby majetek</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Majetek</TH><TH>Rok</TH><TH>Rok odpisu</TH><TH>Rocni odpis</TH>
                <TH>Kumulativne</TH><TH>Zbyva</TH><TH>Metoda</TH>
              </TRow>
            </thead>
            <tbody>
              {depreciations.map(d => (
                <TRow key={d.id}>
                  <TD bold>{d.acc_long_term_assets?.name || '—'}</TD>
                  <TD>{d.year}</TD>
                  <TD>{d.year_number}.</TD>
                  <TD bold color="#dc2626">{fmt(d.annual_amount)}</TD>
                  <TD>{fmt(d.cumulative_amount)}</TD>
                  <TD color="#1a8a18">{fmt(d.remaining_value)}</TD>
                  <TD>{d.method === 'linear' ? 'Rovnomerne' : 'Zrychlene'}</TD>
                </TRow>
              ))}
              {depreciations.length === 0 && <TRow><TD>Zadne odpisy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddAssetModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && <AssetDetailModal asset={detail} onClose={() => setDetail(null)} />}
    </div>
  )
}

function MiniStat({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
