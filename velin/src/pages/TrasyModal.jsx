import { useState, useEffect } from 'react'
import { supabase, supabaseUrl, supabaseAnonKey } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'
import ImageUploader from '../components/ui/ImageUploader'
import { FormField } from './BranchHelpers'
import { autoTranslateRow } from '../lib/autoTranslate'
import TrasyMapPicker from './TrasyMapPicker'
import { decodeRouteCoords, extractMapyUrl, getRcFromUrl, extractRouteGeometry } from '../lib/mapyRoute'

const r6 = (v) => Math.round(Number(v) * 1e6) / 1e6

// Mapy.com API klíč (stejný jako v mobilní appce) — pro výpočet geometrie trasy.
const MAPY_KEY = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0'

/**
 * Best-effort výpočet geometrie trasy přes Mapy.com routing API.
 * Vrací { coordinates:[[lng,lat],…], length_m, duration_s } nebo null.
 * Pokud volání selže (CORS/limit), vrátí null — appka si geometrii dopočítá
 * sama z waypointů při zobrazení.
 */
async function computeGeometry(branch, waypoints, routeType) {
  const pts = []
  const hasBranch = branch && branch.gps_lat != null && branch.gps_lng != null
  if (hasBranch) pts.push([Number(branch.gps_lng), Number(branch.gps_lat)])
  for (const w of waypoints) {
    if (w.lat != null && w.lng != null && w.lat !== '' && w.lng !== '') {
      pts.push([Number(w.lng), Number(w.lat)])
    }
  }
  if (routeType === 'loop' && hasBranch) pts.push([Number(branch.gps_lng), Number(branch.gps_lat)])
  if (pts.length < 2) return null

  const start = pts[0]
  const end = pts[pts.length - 1]
  const middle = pts.slice(1, -1)
  const params = new URLSearchParams({
    apikey: MAPY_KEY,
    lang: 'cs',
    start: `${start[0]},${start[1]}`,
    end: `${end[0]},${end[1]}`,
    routeType: 'car_fast',
    format: 'geojson',
  })
  if (middle.length) params.set('waypoints', middle.map(p => `${p[0]},${p[1]}`).join(';'))

  try {
    const res = await fetch(`https://api.mapy.cz/v1/routing/route?${params.toString()}`, {
      headers: { 'X-Mapy-Api-Key': MAPY_KEY, Accept: 'application/json' },
    })
    if (!res.ok) return null
    const data = await res.json()
    // Geometrie může být GeoJSON i zakódovaný polyline string — robustní extrakce.
    const coords = extractRouteGeometry(data, start)
    const length_m = data?.length ?? data?.summary?.length ?? data?.properties?.length ?? null
    const duration_s = data?.duration ?? data?.summary?.duration ?? data?.properties?.duration ?? null
    const hasCoords = Array.isArray(coords) && coords.length >= 2
    if (!hasCoords && length_m == null) return null
    return { coordinates: hasCoords ? coords : null, length_m, duration_s }
  } catch {
    return null
  }
}

const emptyWaypoint = () => ({ lat: '', lng: '', label: '' })
const emptyPoi = () => ({ name: '', description: '', lat: '', lng: '', image_url: '', images: [] })

export default function TrasyModal({ existing, branches, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState({
    branch_id: existing?.branch_id || (branches[0]?.id || ''),
    name: existing?.name || '',
    description: existing?.description || '',
    route_type: existing?.route_type || 'loop',
    distance_km: existing?.distance_km ?? '',
    duration_min: existing?.duration_min ?? '',
    difficulty: existing?.difficulty || '',
    mapy_url: existing?.mapy_url || '',
    is_active: existing?.is_active ?? true,
    sort_order: existing?.sort_order ?? 0,
  })
  const [waypoints, setWaypoints] = useState(
    Array.isArray(existing?.waypoints) && existing.waypoints.length
      ? existing.waypoints.map(w => ({ lat: w.lat ?? '', lng: w.lng ?? '', label: w.label ?? '' }))
      : [emptyWaypoint()]
  )
  const [cover, setCover] = useState(existing?.cover_image ? [existing.cover_image] : [])
  const [images, setImages] = useState(Array.isArray(existing?.images) ? existing.images : [])
  const [imageAlts, setImageAlts] = useState(Array.isArray(existing?.image_alts) ? existing.image_alts : [])
  const [pois, setPois] = useState([])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [savingNote, setSavingNote] = useState('')
  const [showMap, setShowMap] = useState(false)
  const [importing, setImporting] = useState(false)
  const [importMsg, setImportMsg] = useState('')
  const [importErr, setImportErr] = useState(null)
  const [geometry, setGeometry] = useState(existing?.geometry || null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const branch = branches.find(b => b.id === form.branch_id)

  // Načti existující POI při editaci
  useEffect(() => {
    if (!isEdit) return
    let cancelled = false
    supabase.from('route_pois').select('*').eq('route_id', existing.id).order('sort_order')
      .then(({ data }) => {
        if (cancelled) return
        setPois((data || []).map(p => ({
          name: p.name || '', description: p.description || '',
          lat: p.lat ?? '', lng: p.lng ?? '',
          image_url: p.image_url || '',
          images: Array.isArray(p.images) ? p.images : [],
        })))
      })
    return () => { cancelled = true }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Náhled SKUTEČNÉ trasy po silnici na mapě + dopočet délky/času přes Mapy.com
  // routing (debounced). Reaguje na změnu waypointů, pobočky i typu trasy.
  useEffect(() => {
    if (!showMap) return
    const wp = waypoints.filter(w => w.lat !== '' && w.lng !== '' && !isNaN(Number(w.lat)) && !isNaN(Number(w.lng)))
    if (wp.length < 2) { setGeometry(null); return }
    let cancelled = false
    const tid = setTimeout(async () => {
      const geo = await computeGeometry(branch, wp, form.route_type)
      if (cancelled || !geo) return
      if (geo.coordinates) setGeometry({ coordinates: geo.coordinates })
      setForm(f => ({
        ...f,
        distance_km: f.distance_km === '' && geo.length_m ? Math.round(geo.length_m / 100) / 10 : f.distance_km,
        duration_min: f.duration_min === '' && geo.duration_s ? Math.round(geo.duration_s / 60) : f.duration_min,
      }))
    }, 600)
    return () => { cancelled = true; clearTimeout(tid) }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [waypoints, showMap, form.route_type, form.branch_id])

  // ── Waypoints helpers ──
  const setWp = (i, k, v) => setWaypoints(ws => ws.map((w, idx) => idx === i ? { ...w, [k]: v } : w))
  const addWp = () => setWaypoints(ws => [...ws, emptyWaypoint()])
  const rmWp = (i) => setWaypoints(ws => ws.filter((_, idx) => idx !== i))
  const moveWp = (i, dir) => setWaypoints(ws => {
    const j = i + dir
    if (j < 0 || j >= ws.length) return ws
    const next = [...ws]; [next[i], next[j]] = [next[j], next[i]]; return next
  })
  // Klik do mapy → přidá waypoint (zahodí prázdné řádky), tažení → posun
  const addWpAt = (lat, lng) => setWaypoints(ws => [
    ...ws.filter(w => w.lat !== '' || w.lng !== '' || w.label !== ''),
    { lat: r6(lat), lng: r6(lng), label: '' },
  ])
  const moveWpTo = (i, lat, lng) => setWaypoints(ws => ws.map((w, idx) => idx === i ? { ...w, lat: r6(lat), lng: r6(lng) } : w))

  // ── POI helpers ──
  const setPoi = (i, k, v) => setPois(ps => ps.map((p, idx) => idx === i ? { ...p, [k]: v } : p))
  const addPoi = () => setPois(ps => [...ps, emptyPoi()])
  const rmPoi = (i) => setPois(ps => ps.filter((_, idx) => idx !== i))
  // Klik do mapy v režimu POI → přidá bod zájmu se souřadnicemi
  const addPoiAt = (lat, lng) => setPois(ps => [...ps, { ...emptyPoi(), lat: r6(lat), lng: r6(lng) }])
  const movePoiTo = (i, lat, lng) => setPois(ps => ps.map((p, idx) => idx === i ? { ...p, lat: r6(lat), lng: r6(lng) } : p))

  // ── Import trasy z Mapy.com odkazu ──
  // Plná URL s `rc` se dekóduje rovnou v prohlížeči; zkrácený /s/ odkaz nebo
  // iframe rozbalí edge fn resolve-mapy-route (prohlížeč kvůli CORS nezvládne).
  function applyImported(pts, finalUrl) {
    setWaypoints(pts.map(p => ({ lat: r6(p.lat), lng: r6(p.lng), label: '' })))
    if (finalUrl) set('mapy_url', finalUrl)
    setGeometry(null) // přepočítá se přes routing (debounced effect) → trasa po silnici
    setShowMap(true)
    setImportMsg(`Načteno ${pts.length} bodů trasy ✓ — trasa po silnici, délka a čas se dopočítají z mapy; body zájmu přidej ručně níže`)
  }

  async function importFromMapy() {
    setImportErr(null); setImportMsg('')
    const url = extractMapyUrl(form.mapy_url) || (form.mapy_url || '').trim()
    if (!url) { setImportErr('Vlož odkaz na Mapy.com (nebo celý <iframe> kód).'); return }
    setImporting(true)
    try {
      const rc = getRcFromUrl(url)
      if (rc) {
        const pts = decodeRouteCoords(rc)
        if (!pts.length) throw new Error('V odkazu se nenašly žádné body trasy.')
        applyImported(pts, url)
        return
      }
      // Zkrácený odkaz → rozbalit přes edge fn
      setImportMsg('Rozbaluji odkaz…')
      const { data: { session } } = await supabase.auth.getSession()
      const res = await fetch(`${supabaseUrl}/functions/v1/resolve-mapy-route`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session?.access_token || supabaseAnonKey}`,
          apikey: supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ url }),
      })
      const d = await res.json().catch(() => ({}))
      if (!res.ok || !d?.success) {
        throw new Error(d?.error || `Rozbalení odkazu selhalo (HTTP ${res.status}).`)
      }
      const pts = Array.isArray(d.waypoints) && d.waypoints.length
        ? d.waypoints
        : decodeRouteCoords(d.rc)
      if (!pts.length) throw new Error('V odkazu se nenašly žádné body trasy.')
      applyImported(pts, d.url || url)
    } catch (e) {
      setImportErr(e.message)
    } finally {
      setImporting(false)
    }
  }

  async function handleSave() {
    if (!form.name?.trim()) { setErr('Název trasy je povinný.'); return }
    if (!form.branch_id) { setErr('Vyberte pobočku, od které trasa vede.'); return }
    setSaving(true); setErr(null)
    try {
      const cleanWp = waypoints
        .filter(w => w.lat !== '' && w.lng !== '' && !isNaN(Number(w.lat)) && !isNaN(Number(w.lng)))
        .map((w, i) => ({ lat: Number(w.lat), lng: Number(w.lng), label: w.label?.trim() || null, order: i }))

      // Geometrie přes Mapy.com (best-effort, cache do DB)
      setSavingNote('Počítám trasu v mapách…')
      const geo = await computeGeometry(branch, cleanWp, form.route_type)
      setSavingNote('Ukládám…')

      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        branch_id: form.branch_id,
        name: form.name.trim(),
        description: form.description?.trim() || null,
        route_type: form.route_type,
        distance_km: form.distance_km !== '' ? Number(form.distance_km)
          : (geo?.length_m ? Math.round(geo.length_m / 100) / 10 : null),
        duration_min: form.duration_min !== '' ? Number(form.duration_min)
          : (geo?.duration_s ? Math.round(geo.duration_s / 60) : null),
        difficulty: form.difficulty || null,
        mapy_url: form.mapy_url?.trim() || null,
        waypoints: cleanWp,
        geometry: (geo && geo.coordinates) ? { coordinates: geo.coordinates } : (geometry || existing?.geometry || null),
        cover_image: cover[0] || null,
        images,
        image_alts: imageAlts,
        is_active: form.is_active,
        sort_order: Number(form.sort_order) || 0,
        // Uložení adminem = schválení (potvrdí i uživatelský návrh trasy)
        status: 'approved',
        updated_at: new Date().toISOString(),
      }

      const result = await debugAction(isEdit ? 'routes.update' : 'routes.create', 'TrasyModal', () =>
        isEdit
          ? supabase.from('routes').update(payload).eq('id', existing.id).select().single()
          : supabase.from('routes').insert(payload).select().single()
      , { name: payload.name, branch_id: payload.branch_id })
      if (result?.error) {
        const m = result.error.message || 'Neznámá chyba'
        throw new Error(m + (result.error.code === '42501' ? ' — Zkontrolujte RLS politiky v Supabase.' : ''))
      }
      const routeId = result?.data?.id || existing?.id

      // POI: delete-and-reinsert (robustní, drží pořadí)
      setSavingNote('Ukládám body zájmu…')
      await supabase.from('route_pois').delete().eq('route_id', routeId)
      const cleanPois = pois.filter(p => p.name?.trim())
      if (cleanPois.length) {
        const poiRows = cleanPois.map((p, i) => ({
          route_id: routeId,
          name: p.name.trim(),
          description: p.description?.trim() || null,
          lat: p.lat !== '' ? Number(p.lat) : null,
          lng: p.lng !== '' ? Number(p.lng) : null,
          image_url: p.image_url || (Array.isArray(p.images) && p.images[0]) || null,
          images: Array.isArray(p.images) ? p.images : [],
          sort_order: i,
        }))
        const { data: insertedPois, error: poiErr } = await supabase
          .from('route_pois').insert(poiRows).select('id, name, description')
        if (poiErr) throw new Error(`Uložení bodů zájmu selhalo: ${poiErr.message}`)
        // Auto-překlad POI na pozadí
        ;(insertedPois || []).forEach(p => {
          if (p.description || p.name) {
            autoTranslateRow({ table: 'route_pois', id: p.id, row: { name: p.name, description: p.description } })
          }
        })
      }

      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: isEdit ? 'route_updated' : 'route_created',
        details: { name: payload.name },
      })
      // Auto-překlad trasy na pozadí
      if (routeId && (payload.name || payload.description)) {
        autoTranslateRow({ table: 'routes', id: routeId, row: { name: payload.name, description: payload.description } })
      }
      onSaved()
    } catch (e) {
      setErr(e.message)
    } finally {
      setSaving(false); setSavingNote('')
    }
  }

  const lbl = "block text-sm font-extrabold uppercase tracking-wide mb-1"
  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }

  return (
    <Modal open title={isEdit ? `Upravit trasu: ${existing.name}` : 'Nová trasa'} onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Pobočka *</label>
          <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— vyberte pobočku —</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}{b.city ? `, ${b.city}` : ''}</option>)}
          </select>
        </div>
        <FormField label="Název trasy *" value={form.name} onChange={v => set('name', v)} />
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Typ trasy</label>
          <select value={form.route_type} onChange={e => set('route_type', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="loop">Okruh (zpět na pobočku)</option>
            <option value="poi">Za body zájmu</option>
          </select>
        </div>
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Náročnost</label>
          <select value={form.difficulty} onChange={e => set('difficulty', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            <option value="easy">Lehká</option>
            <option value="medium">Střední</option>
            <option value="hard">Náročná</option>
          </select>
        </div>
        <FormField label="Délka (km)" value={form.distance_km} onChange={v => set('distance_km', v)} type="number"
          placeholder="prázdné = dopočítá se z mapy" />
        <FormField label="Doba (min)" value={form.duration_min} onChange={v => set('duration_min', v)} type="number"
          placeholder="prázdné = dopočítá se z mapy" />
        <div className="col-span-2">
          <label className={lbl} style={{ color: '#1a2e22' }}>Popis trasy</label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ ...inputStyle, minHeight: 70, resize: 'vertical' }}
            placeholder="Co zákazníka na trase čeká, doporučení, zajímavosti…" />
        </div>
        <div className="col-span-2">
          <label className={lbl} style={{ color: '#1a2e22' }}>Odkaz na Mapy.com — automatický import trasy</label>
          <div className="flex gap-2 items-start">
            <input type="text" value={form.mapy_url} onChange={e => { set('mapy_url', e.target.value); setImportErr(null); setImportMsg('') }}
              placeholder="Vlož mapy.com/s/… , plnou URL nebo celý <iframe> kód"
              className="flex-1 rounded-btn text-sm outline-none" style={inputStyle} />
            <Button green onClick={importFromMapy} disabled={importing || !form.mapy_url?.trim()}>
              {importing ? 'Načítám…' : '📥 Načíst trasu'}
            </Button>
          </div>
          <p className="text-xs mt-1" style={{ color: '#6b8f7b' }}>
            Naimportuje body trasy z odkazu (plná URL i zkrácený mapy.com/s/… i iframe). Body zájmu přidáš ručně níže.
          </p>
          {importMsg && <p className="text-xs mt-1 font-bold" style={{ color: '#1a8a18' }}>{importMsg}</p>}
          {importErr && <p className="text-xs mt-1" style={{ color: '#dc2626' }}>{importErr}</p>}
        </div>
      </div>

      {/* ── Interaktivní mapa (klik = přidat bod) ── */}
      <div className="mt-5">
        <div className="flex items-center justify-between mb-2">
          <label className={lbl} style={{ color: '#1a2e22', marginBottom: 0 }}>Mapa trasy</label>
          <Button small onClick={() => setShowMap(s => !s)}>{showMap ? 'Skrýt mapu' : '🗺️ Vybrat na mapě'}</Button>
        </div>
        {showMap && (
          <>
            {!branch?.gps_lat && (
              <p className="text-xs mb-2" style={{ color: '#b45309' }}>
                Tato pobočka nemá v Pobočkách vyplněné GPS — start trasy se na mapě nezobrazí, ale body jdou přidávat normálně.
              </p>
            )}
            <TrasyMapPicker
              start={branch?.gps_lat != null && branch?.gps_lng != null ? { lat: branch.gps_lat, lng: branch.gps_lng } : null}
              waypoints={waypoints}
              pois={pois}
              geometry={geometry}
              isLoop={form.route_type === 'loop'}
              onAddWaypoint={addWpAt}
              onAddPoi={addPoiAt}
              onMoveWaypoint={moveWpTo}
              onMovePoi={movePoiTo}
            />
          </>
        )}
      </div>

      {/* ── Waypointy (body trasy) ── */}
      <div className="mt-5">
        <div className="flex items-center justify-between mb-2">
          <label className={lbl} style={{ color: '#1a2e22', marginBottom: 0 }}>Body trasy (waypointy)</label>
          <Button small onClick={addWp}>+ Bod</Button>
        </div>
        <p className="text-xs mb-2" style={{ color: '#6b8f7b' }}>
          Souřadnice ve směru jízdy. Trasa začíná na pobočce{form.route_type === 'loop' ? ' a okruhem se na ni vrací' : ''}.
          Geometrie se po uložení spočítá přes Mapy.com.
        </p>
        {waypoints.map((w, i) => (
          <div key={i} className="flex items-center gap-2 mb-2">
            <span className="text-xs font-bold" style={{ color: '#8b5cf6', width: 18 }}>{i + 1}.</span>
            <input type="number" step="any" value={w.lat} onChange={e => setWp(i, 'lat', e.target.value)}
              placeholder="šířka (lat)" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 120 }} />
            <input type="number" step="any" value={w.lng} onChange={e => setWp(i, 'lng', e.target.value)}
              placeholder="délka (lng)" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 120 }} />
            <input type="text" value={w.label} onChange={e => setWp(i, 'label', e.target.value)}
              placeholder="popisek (volitelně)" className="flex-1 rounded-btn text-sm outline-none" style={inputStyle} />
            <button onClick={() => moveWp(i, -1)} title="Nahoru" className="cursor-pointer" style={{ background: 'none', border: 'none', color: '#6b8f7b' }}>▲</button>
            <button onClick={() => moveWp(i, 1)} title="Dolů" className="cursor-pointer" style={{ background: 'none', border: 'none', color: '#6b8f7b' }}>▼</button>
            <button onClick={() => rmWp(i)} title="Odebrat" className="cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626', fontSize: 16 }}>✕</button>
          </div>
        ))}
      </div>

      {/* ── Obrázky ── */}
      <div className="mt-5 grid grid-cols-1 gap-4">
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Hlavní (titulní) obrázek</label>
          <ImageUploader value={cover} onChange={setCover} folder={`routes/${existing?.id || 'new'}/cover`}
            single showMainBadge={false} helperText="Zobrazí se jako náhled v seznamu tras i v appce." />
        </div>
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Galerie trasy</label>
          <ImageUploader value={images} onChange={setImages} alts={imageAlts} onAltsChange={setImageAlts}
            folder={`routes/${existing?.id || 'new'}/gallery`}
            helperText="Fotky z trasy — zobrazí se v detailu v appce." />
        </div>
      </div>

      {/* ── Body zájmu (POI) ── */}
      <div className="mt-5">
        <div className="flex items-center justify-between mb-2">
          <label className={lbl} style={{ color: '#1a2e22', marginBottom: 0 }}>Body zájmu (POI)</label>
          <Button small onClick={addPoi}>+ Bod zájmu</Button>
        </div>
        {pois.length === 0 && (
          <p className="text-xs" style={{ color: '#6b8f7b' }}>Zatím žádné body zájmu. Přidejte zastávky s popisem a fotkou.</p>
        )}
        {pois.map((p, i) => (
          <div key={i} className="rounded-card mb-3" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', padding: 12 }}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-extrabold" style={{ color: '#8b5cf6' }}>BOD ZÁJMU {i + 1}</span>
              <button onClick={() => rmPoi(i)} className="cursor-pointer text-sm font-bold" style={{ background: 'none', border: 'none', color: '#dc2626' }}>Odebrat ✕</button>
            </div>
            {(p.lat === '' || p.lng === '' || p.lat == null || p.lng == null) && (
              <div className="text-xs font-bold mb-2 rounded-btn" style={{ color: '#b45309', background: '#fff7ed', border: '1px solid #fdba74', padding: '6px 10px' }}>
                ⚠ Chybí souřadnice — tento bod zájmu se NEZOBRAZÍ jako pin na mapě v aplikaci. Klikni do mapy výše v režimu „📍 Bod zájmu", nebo vyplň lat/lng ručně.
              </div>
            )}
            <div className="grid grid-cols-2 gap-2">
              <FormField label="Název" value={p.name} onChange={v => setPoi(i, 'name', v)} />
              <div className="grid grid-cols-2 gap-2">
                <FormField label="Šířka (lat)" value={p.lat} onChange={v => setPoi(i, 'lat', v)} type="number" />
                <FormField label="Délka (lng)" value={p.lng} onChange={v => setPoi(i, 'lng', v)} type="number" />
              </div>
              <div className="col-span-2">
                <label className={lbl} style={{ color: '#1a2e22' }}>Krátký popis</label>
                <textarea value={p.description} onChange={e => setPoi(i, 'description', e.target.value)}
                  className="w-full rounded-btn text-sm outline-none"
                  placeholder="Zobrazí se po kliknutí na tento bod zájmu v aplikaci"
                  style={{ ...inputStyle, minHeight: 48, resize: 'vertical' }} />
              </div>
              <div className="col-span-2">
                <label className={lbl} style={{ color: '#1a2e22' }}>Obrázky bodu zájmu</label>
                <ImageUploader value={p.images} onChange={(urls) => setPoi(i, 'images', urls)}
                  folder={`routes/${existing?.id || 'new'}/poi`} showMainBadge
                  helperText="První obrázek = hlavní fotka bodu zájmu." />
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* ── Stav + řazení ── */}
      <div className="mt-5 flex items-center gap-4 flex-wrap">
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Publikováno (viditelné v appce)</span>
        </label>
        <div className="flex items-center gap-2">
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Pořadí:</span>
          <input type="number" value={form.sort_order} onChange={e => set('sort_order', e.target.value)}
            className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} />
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626', whiteSpace: 'pre-wrap' }}>{err}</p>}
      <div className="flex justify-end items-center gap-3 mt-5">
        {saving && savingNote && <span className="text-sm" style={{ color: '#6b8f7b' }}>{savingNote}</span>}
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name?.trim() || !form.branch_id}>
          {saving ? 'Ukládám…' : isEdit ? 'Uložit změny' : 'Vytvořit trasu'}
        </Button>
      </div>
    </Modal>
  )
}
