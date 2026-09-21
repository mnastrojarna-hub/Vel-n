import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'
import { mapyLinkUrl } from '../lib/mapyCz'
import { DETAIL_TABS, maxMotosForBranch, isSelfService, SELF_SERVICE_LAYOUT_NOTE, Spinner, EmptyState, DRow } from './BranchHelpers'
import { TabAccessories } from './BranchAccessories'
import { TabDoorCodes } from './BranchDoorCodes'
import { TabSelfService } from './BranchSelfService'
import { TabClosures } from './BranchClosures'

function BranchDetailModal({ branch, stats: branchStats, bookings, onClose, onEdit, onRefresh }) {
  const [tab, setTab] = useState(0)
  const [motos, setMotos] = useState([])
  const [loadingMotos, setLoadingMotos] = useState(true)
  const [accessories, setAccessories] = useState([])
  const [loadingAccessories, setLoadingAccessories] = useState(true)
  const [doorCodes, setDoorCodes] = useState([])
  const [loadingCodes, setLoadingCodes] = useState(true)
  const [activeBookings, setActiveBookings] = useState([])

  useEffect(() => {
    loadMotos()
    loadAccessories()
    loadDoorCodes()
    loadActiveBookings()
  }, [branch.id])

  async function loadMotos() {
    setLoadingMotos(true)
    try {
      const { data } = await supabase
        .from('motorcycles')
        .select('id, model, spz, status, mileage, image_url, box_number')
        .eq('branch_id', branch.id)
        .order('box_number', { ascending: true, nullsFirst: false })
      setMotos(data || [])
    } catch {}
    setLoadingMotos(false)
  }

  async function loadAccessories() {
    setLoadingAccessories(true)
    try {
      const { data, error } = await supabase
        .from('branch_accessories')
        .select('*')
        .eq('branch_id', branch.id)
        .order('type')
      if (error) {
        console.warn('[Branches] branch_accessories query failed:', error.message)
        setAccessories([])
      } else {
        setAccessories(data || [])
      }
    } catch (e) {
      console.warn('[Branches] accessories load failed:', e.message)
      setAccessories([])
    }
    setLoadingAccessories(false)
  }

  async function loadDoorCodes() {
    setLoadingCodes(true)
    try {
      const { data, error } = await supabase
        .from('branch_door_codes')
        .select('*, bookings(id, status, start_date, end_date, user_id, profiles:user_id(full_name, email)), motorcycles:moto_id(model, spz)')
        .eq('branch_id', branch.id)
        .order('created_at', { ascending: false })
      if (error) {
        console.warn('[Branches] branch_door_codes query failed:', error.message)
        setDoorCodes([])
      } else {
        setDoorCodes(data || [])
      }
    } catch (e) {
      console.warn('[Branches] door codes load failed:', e.message)
      setDoorCodes([])
    }
    setLoadingCodes(false)
  }

  async function loadActiveBookings() {
    try {
      const { data: branchMotos } = await supabase
        .from('motorcycles')
        .select('id')
        .eq('branch_id', branch.id)
      if (!branchMotos || branchMotos.length === 0) { setActiveBookings([]); return }
      const motoIds = branchMotos.map(m => m.id)
      const { data } = await supabase
        .from('bookings')
        .select('id, moto_id, status, start_date, end_date, user_id, profiles:user_id(full_name)')
        .in('moto_id', motoIds)
        .in('status', ['active', 'reserved'])
        .order('start_date')
      setActiveBookings(data || [])
    } catch {
      setActiveBookings([])
    }
  }

  const MOTO_STATUS = {
    active: { label: 'Dostupná', bg: '#dcfce7', color: '#1a8a18' },
    rented: { label: 'Pronajatá', bg: '#dbeafe', color: '#2563eb' },
    maintenance: { label: 'V servisu', bg: '#fef3c7', color: '#b45309' },
    unavailable: { label: 'Nedostupná', bg: '#fee2e2', color: '#dc2626' },
    retired: { label: 'Vyřazena', bg: '#f3f4f6', color: '#1a2e22' },
  }

  return (
    <Modal open title={`Pobočka: ${branch.name}`} onClose={onClose} wide>
      {/* Status bar */}
      <div className="flex items-center gap-3 mb-4">
        <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
          style={{
            padding: '3px 10px',
            background: branch.is_open ? '#dcfce7' : '#fee2e2',
            color: branch.is_open ? '#1a8a18' : '#dc2626',
          }}>
          {branch.is_open ? 'Otevřená — Nonstop' : 'Zavřená'}
        </span>
        {branch.branch_code && (
          <span className="font-mono text-sm font-bold" style={{ color: '#1a2e22' }}>
            Kód: {branch.branch_code}
          </span>
        )}
        <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
          style={{
            padding: '3px 10px',
            background: branch.active === false ? '#fee2e2' : '#f1faf7',
            color: branch.active === false ? '#dc2626' : '#1a2e22',
          }}>
          {branch.active === false ? 'Neaktivní' : 'Aktivní'}
        </span>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-4 border-b" style={{ borderColor: '#d4e8e0' }}>
        {DETAIL_TABS.map((t, i) => (
          <button key={t} onClick={() => setTab(i)}
            className="text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
            style={{
              padding: '8px 16px',
              background: tab === i ? '#1a2e22' : 'transparent',
              color: tab === i ? '#74FB71' : '#1a2e22',
              borderRadius: '8px 8px 0 0',
            }}>
            {t}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {tab === 0 && (
        <TabInfo branch={branch} branchStats={branchStats} bookings={bookings} />
      )}
      {tab === 1 && (
        <TabMotorcycles motos={motos} loading={loadingMotos} statusLabels={MOTO_STATUS} branch={branch} onRefresh={loadMotos} />
      )}
      {tab === 2 && (
        <TabAccessories accessories={accessories} loading={loadingAccessories} branchId={branch.id} branchName={branch.name} onRefresh={loadAccessories} />
      )}
      {tab === 3 && (
        <TabDoorCodes
          doorCodes={doorCodes}
          loading={loadingCodes}
          branchId={branch.id}
          motos={motos}
          activeBookings={activeBookings}
          onRefresh={() => { loadDoorCodes(); loadActiveBookings() }}
        />
      )}
      {tab === 4 && (
        <TabSelfService branchId={branch.id} branchName={branch.name} motos={motos} />
      )}
      {tab === 5 && (
        <TabClosures branch={branch} />
      )}

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onEdit}>Upravit</Button>
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}

// ─── Tab: Info ────────────────────────────────────────────────────
function TabInfo({ branch, branchStats, bookings }) {
  return (
    <>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <DRow label="Kód pobočky" value={branch.branch_code} mono />
        <DRow label="Provoz" value={branch.is_open ? 'Otevřená — Nonstop' : 'Zavřená'} />
        <DRow label="Město" value={branch.city} />
        <DRow label="Adresa" value={branch.address} />
        <DRow label="Telefon" value={branch.phone} mono />
        <DRow label="Stav" value={branch.active === false ? 'Neaktivní' : 'Aktivní'} />
        {branch.gps_lat && branch.gps_lng && (
          <div className="col-span-2">
            <DRow label="GPS" value={`${branch.gps_lat}, ${branch.gps_lng}`} mono />
            <a href={mapyLinkUrl(branch.gps_lat, branch.gps_lng)}
              target="_blank" rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-sm font-bold px-2 py-0.5 rounded-btn mt-1"
              style={{ background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>
              Otevřít v Mapy.cz
            </a>
          </div>
        )}
        {branch.notes && (
          <div className="col-span-2">
            <DRow label="Poznámky" value={branch.notes} />
          </div>
        )}
      </div>

      <div className="grid grid-cols-3 gap-3 mb-4">
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorky</div>
          <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>
            {branchStats?.active || 0} / {branchStats?.total || 0}
          </div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rezervace</div>
          <div className="text-lg font-extrabold" style={{ color: '#8b5cf6' }}>{bookings}</div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>V servisu</div>
          <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{branchStats?.maintenance || 0}</div>
        </div>
      </div>
    </>
  )
}

function TabMotorcycles({ motos, loading, statusLabels, branch, onRefresh }) {
  const [saving, setSaving] = useState(false)
  const selfService = isSelfService(branch)
  const maxMotos = maxMotosForBranch(branch)

  if (loading) return <Spinner />
  if (motos.length === 0) return <EmptyState text="Žádné motorky na této pobočce" />

  // Sort by box_number (nulls last)
  const sorted = [...motos].sort((a, b) => {
    if (a.box_number == null && b.box_number == null) return 0
    if (a.box_number == null) return 1
    if (b.box_number == null) return -1
    return a.box_number - b.box_number
  })

  // Číslo kóje jde u motorky kdykoliv přepsat (i změnit, nejen doplnit).
  // Prázdná hodnota = motorka bez přiřazené kóje.
  async function setBoxNumber(motoId, num) {
    if (num != null && (num < 1 || num > maxMotos)) {
      alert(`Číslo kóje musí být 1–${maxMotos}.`)
      return
    }
    setSaving(true)
    try {
      const { error } = await supabase.from('motorcycles').update({ box_number: num }).eq('id', motoId)
      if (error) throw error
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  function commitBoxInput(motoId, raw) {
    const txt = String(raw ?? '').trim()
    if (txt === '') { setBoxNumber(motoId, null); return }
    const val = parseInt(txt, 10)
    if (Number.isNaN(val)) return
    setBoxNumber(motoId, val)
  }

  async function swapBoxNumbers(indexA, indexB) {
    if (indexA < 0 || indexB < 0 || indexA >= sorted.length || indexB >= sorted.length) return
    setSaving(true)
    try {
      const mA = sorted[indexA]
      const mB = sorted[indexB]
      const numA = mA.box_number
      const numB = mB.box_number
      // Swap: set A to temp -1, set B to A's number, set A to B's number
      await supabase.from('motorcycles').update({ box_number: -1 }).eq('id', mA.id)
      await supabase.from('motorcycles').update({ box_number: numA }).eq('id', mB.id)
      await supabase.from('motorcycles').update({ box_number: numB }).eq('id', mA.id)
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  async function autoAssignBoxNumbers() {
    if (motos.length > maxMotos) {
      alert(`Na pobočce je ${motos.length} motorek, ale jen ${maxMotos} kójí — auto-přiřazení by nemělo kam ty navíc dát. Přesuňte přebytečné motorky na jinou pobočku.`)
      return
    }
    if (!window.confirm(`Automaticky přiřadit čísla kojí 1–${motos.length} všem motorkám na pobočce?`)) return
    setSaving(true)
    try {
      for (let i = 0; i < sorted.length; i++) {
        const { error } = await supabase.from('motorcycles').update({ box_number: i + 1 }).eq('id', sorted[i].id)
        if (error) throw error
      }
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  const hasUnassigned = sorted.some(m => m.box_number == null)
  const overLimit = motos.length > maxMotos
  // Dvě motorky ve stejné kóji = špatné kódy i špatné dveře na samoobsluze
  const dupBoxes = new Set(
    sorted.map(m => m.box_number).filter(n => n != null)
      .filter((n, i, arr) => arr.indexOf(n) !== i)
  )
  const outOfRange = new Set(
    sorted.filter(m => m.box_number != null && (m.box_number < 1 || m.box_number > maxMotos)).map(m => m.box_number)
  )

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div className="text-sm" style={{ color: '#1a2e22' }}>
          <strong>{motos.length}</strong> {selfService ? `z ${maxMotos} kójí motorek` : `motorek na pobočce (max ${maxMotos})`}
          {selfService && (
            <span className="ml-1" style={{ color: '#6b7280' }}>({SELF_SERVICE_LAYOUT_NOTE} — kóje 1–{maxMotos})</span>
          )}
          <div className="text-xs" style={{ color: '#6b7280' }}>Změna kóje vygeneruje zákazníkům s rezervací nové kódy a znovu je odešle.</div>
        </div>
        <div className="flex gap-2">
          {hasUnassigned && (
            <button onClick={autoAssignBoxNumbers} disabled={saving}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', opacity: saving ? 0.5 : 1 }}>
              Auto-přiřadit čísla kojí
            </button>
          )}
        </div>
      </div>

      {overLimit && (
        <div className="rounded-lg mb-2 text-sm" style={{ padding: '8px 10px', background: '#fee2e2', color: '#dc2626' }}>
          Na pobočce je {motos.length} motorek, ale jen {maxMotos} kójí{selfService ? ` (${SELF_SERVICE_LAYOUT_NOTE})` : ''}. Přebytečné kusy přesuňte na jinou pobočku.
        </div>
      )}
      {dupBoxes.size > 0 && (
        <div className="rounded-lg mb-2 text-sm" style={{ padding: '8px 10px', background: '#fef3c7', color: '#b45309' }}>
          Kóje {[...dupBoxes].map(n => `#${n}`).join(', ')} má přiřazeno víc motorek — zákazník by dostal kód k cizím dveřím. Opravte čísla kójí.
        </div>
      )}
      {outOfRange.size > 0 && (
        <div className="rounded-lg mb-2 text-sm" style={{ padding: '8px 10px', background: '#fef3c7', color: '#b45309' }}>
          Kóje {[...outOfRange].map(n => `#${n}`).join(', ')} je mimo rozsah 1–{maxMotos} této pobočky.
        </div>
      )}

      <div className="space-y-1 max-h-96 overflow-y-auto">
        {sorted.map((m, i) => {
          const st = statusLabels[m.status] || statusLabels.active
          return (
            <div key={m.id} className="flex items-center text-sm gap-1" style={{ padding: '6px 8px', background: i % 2 === 0 ? '#f8fcfa' : '#fff', borderRadius: 8 }}>
              {/* Box number */}
              <div className="flex items-center gap-0.5 mr-1" style={{ minWidth: 70 }}>
                <span className="font-mono font-extrabold text-sm" style={{
                  color: m.box_number != null ? '#1a2e22' : '#dc2626',
                  background: m.box_number != null ? '#dcfce7' : '#fee2e2',
                  padding: '2px 6px',
                  borderRadius: 6,
                  minWidth: 32,
                  textAlign: 'center',
                  display: 'inline-block',
                }}>
                  {m.box_number != null ? `#${m.box_number}` : '—'}
                </span>
                {/* Move arrows */}
                <div className="flex flex-col" style={{ lineHeight: 0 }}>
                  <button onClick={() => swapBoxNumbers(i, i - 1)} disabled={i === 0 || saving}
                    className="cursor-pointer border-none bg-transparent"
                    style={{ padding: 0, fontSize: 10, color: i === 0 ? '#ccc' : '#1a2e22', lineHeight: '12px' }}
                    title="Posunout nahoru">
                    ▲
                  </button>
                  <button onClick={() => swapBoxNumbers(i, i + 1)} disabled={i === sorted.length - 1 || saving}
                    className="cursor-pointer border-none bg-transparent"
                    style={{ padding: 0, fontSize: 10, color: i === sorted.length - 1 ? '#ccc' : '#1a2e22', lineHeight: '12px' }}
                    title="Posunout dolů">
                    ▼
                  </button>
                </div>
              </div>
              {/* Moto info */}
              <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
              <span className="ml-1 font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz || '—'}</span>
              <span className="ml-auto mr-2 text-sm" style={{ color: '#1a2e22' }}>
                {m.mileage ? `${m.mileage.toLocaleString('cs-CZ')} km` : ''}
              </span>
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                style={{ padding: '2px 6px', background: st.bg, color: st.color }}>
                {st.label}
              </span>
              {/* Číslo kóje — vždy přepsatelné (prázdné = bez kóje) */}
              <input
                key={`box-${m.id}-${m.box_number ?? 'x'}`}
                type="number" min="1" max={maxMotos} placeholder="Kóje"
                defaultValue={m.box_number ?? ''}
                disabled={saving}
                title={`Kóje motorky na pobočce (1–${maxMotos}). Prázdné = bez přiřazené kóje.`}
                className="rounded-btn text-sm outline-none font-mono ml-1"
                style={{
                  width: 54, padding: '2px 4px', textAlign: 'center',
                  background: m.box_number == null ? '#fffbeb' : '#f1faf7',
                  border: `1px solid ${m.box_number == null ? '#fbbf24' : '#d4e8e0'}`,
                }}
                onKeyDown={e => { if (e.key === 'Enter') e.target.blur() }}
                onBlur={e => {
                  const txt = String(e.target.value ?? '').trim()
                  const cur = m.box_number == null ? '' : String(m.box_number)
                  if (txt === cur) return
                  commitBoxInput(m.id, txt)
                }}
              />
            </div>
          )
        })}
      </div>
    </div>
  )
}

export default BranchDetailModal
