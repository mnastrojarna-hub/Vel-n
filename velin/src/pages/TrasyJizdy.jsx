import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../lib/supabase'
import SearchInput from '../components/ui/SearchInput'
import { SmallBtn } from './BranchHelpers'
import TrasyJizdaModal from './TrasyJizdaModal'

// Projeté jízdy zákazníků („Moje jízdy" v appce): stopa GPS z výpůjčky
// (vzniká automaticky, když má zákazník povolenou polohu) + zastávky s
// fotkami a popisky. Velín je čte, edituje, moderuje (skrýt) i maže.
// Jízda je SOUKROMÁ, dokud ji zákazník sám nezveřejní — Velín to respektuje
// a stav sdílení jen zobrazuje (změnit ho lze v detailu).

const FILTERS = [
  { id: 'all', label: 'Vše' },
  { id: 'public', label: '🌍 Veřejné' },
  { id: 'private', label: '🔒 Soukromé' },
  { id: 'hidden', label: '🙈 Skryté' },
  { id: 'recording', label: '⏺ Nahrávané' },
  { id: 'photos', label: '📷 S fotkami' },
]

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
const fmtDur = (min) => min == null ? '—' : (min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`)

export default function TrasyJizdy({ onChanged }) {
  const [rides, setRides] = useState([])
  const [pointsByRide, setPointsByRide] = useState({})
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState(null)
  const [confirm, setConfirm] = useState(null)

  useEffect(() => { load() /* eslint-disable-next-line */ }, [])

  async function load() {
    setLoading(true); setErr(null)
    try {
      // Jízdy — stránkovaně (PostgREST vrací max 1000 řádků na dotaz).
      const all = []
      for (let from = 0; ; from += 1000) {
        const { data, error } = await supabase.from('user_rides')
          .select('*').order('started_at', { ascending: false }).range(from, from + 999)
        if (error) {
          throw new Error(
            `Načtení jízd selhalo: ${error.message || 'neznámá chyba'}` +
            (error.code === '42P01' || (error.message || '').includes('does not exist')
              ? '\n\nTabulka "user_rides" zatím v databázi neexistuje — spusťte prosím SQL migraci jízd.'
              : ''))
        }
        all.push(...(data || []))
        if (!data || data.length < 1000) break
      }
      setRides(all)

      // Body jízd (zastávky + start/cíl) — pro počty i detail.
      const byRide = {}
      for (let from = 0; ; from += 1000) {
        const { data, error } = await supabase.from('user_ride_points')
          .select('*').order('sort_order').range(from, from + 999)
        if (error) throw error
        ;(data || []).forEach(p => {
          (byRide[p.ride_id] = byRide[p.ride_id] || []).push(p)
        })
        if (!data || data.length < 1000) break
      }
      setPointsByRide(byRide)

      // Jména jezdců (přezdívka z věrnostního programu, jinak celé jméno).
      const ids = [...new Set(all.map(r => r.user_id).filter(Boolean))]
      const map = {}
      for (let i = 0; i < ids.length; i += 200) {
        const { data: profs } = await supabase.from('profiles')
          .select('id, full_name, loyalty_nickname').in('id', ids.slice(i, i + 200))
        ;(profs || []).forEach(p => {
          map[p.id] = p.loyalty_nickname?.trim() || p.full_name?.trim() || 'Motorkář'
        })
      }
      setNames(map)
    } catch (e) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function toggleHidden(ride) {
    const next = ride.status === 'hidden' ? 'approved' : 'hidden'
    const { error } = await supabase.from('user_rides')
      .update({ status: next, updated_at: new Date().toISOString() }).eq('id', ride.id)
    if (error) { setErr(error.message); return }
    setRides(rs => rs.map(r => r.id === ride.id ? { ...r, status: next } : r))
    onChanged?.()
  }

  async function remove(ride) {
    const { error } = await supabase.from('user_rides').delete().eq('id', ride.id)
    setConfirm(null)
    if (error) { setErr(error.message); return }
    setRides(rs => rs.filter(r => r.id !== ride.id))
    onChanged?.()
  }

  const photoCount = (id) => (pointsByRide[id] || [])
    .reduce((s, p) => s + (Array.isArray(p.photos) ? p.photos.length : 0), 0)

  const filtered = useMemo(() => rides.filter(r => {
    if (filter === 'public' && !(r.visibility === 'public')) return false
    if (filter === 'private' && r.visibility !== 'private') return false
    if (filter === 'hidden' && r.status !== 'hidden') return false
    if (filter === 'recording' && !r.is_recording) return false
    if (filter === 'photos' && photoCount(r.id) === 0) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (r.name || '').toLowerCase().includes(s) ||
      (r.moto_name || '').toLowerCase().includes(s) ||
      (names[r.user_id] || '').toLowerCase().includes(s)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [rides, filter, search, names, pointsByRide])


  const publicCount = rides.filter(r => r.visibility === 'public' && r.status === 'approved').length
  const hiddenCount = rides.filter(r => r.status === 'hidden').length
  const totalKm = Math.round(rides.reduce((s, r) => s + Number(r.distance_km || 0), 0))

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat jízdu, jezdce, motorku…" />
        <div className="flex gap-1 flex-wrap">
          {FILTERS.map(f => (
            <button key={f.id} onClick={() => setFilter(f.id)}
              className="rounded-btn text-xs font-extrabold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none',
                background: filter === f.id ? '#74FB71' : '#f1faf7', color: '#1a2e22',
              }}>
              {f.label}
            </button>
          ))}
        </div>
        <span className="ml-auto text-xs font-bold" style={{ color: '#6b8f7b' }}>
          {rides.length} jízd · {publicCount} veřejných · {hiddenCount} skrytých · {totalKm} km celkem
        </span>
      </div>

      {err && <p className="text-sm mb-3" style={{ color: '#dc2626', whiteSpace: 'pre-wrap' }}>{err}</p>}

      {loading ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
        </div>
      ) : filtered.length === 0 ? (
        <p className="text-sm py-8 text-center" style={{ color: '#6b8f7b' }}>
          {rides.length === 0
            ? 'Zatím žádné projeté jízdy. Vznikají automaticky v appce, když má zákazník při výpůjčce povolenou polohu.'
            : 'Žádná jízda neodpovídá filtru.'}
        </p>
      ) : (
        <div className="flex flex-col gap-3">
          {filtered.map(ride => {
            const pts = pointsByRide[ride.id] || []
            const stops = pts.filter(p => p.kind === 'stop').length
            const isHidden = ride.status === 'hidden'
            return (
              <div key={ride.id} className="rounded-card"
                style={{
                  background: isHidden ? '#fef2f2' : '#fff',
                  border: `1px solid ${isHidden ? '#fecaca' : '#d4e8e0'}`,
                  padding: '12px 14px',
                }}>
                <div className="flex items-center justify-between gap-3 mb-1 flex-wrap">
                  <div className="flex items-center gap-2 min-w-0 flex-wrap">
                    <button onClick={() => setDetail({ ...ride, points: pts })}
                      className="text-sm font-extrabold cursor-pointer truncate" title="Otevřít detail jízdy"
                      style={{ background: 'none', border: 'none', color: '#1a8a18', padding: 0, maxWidth: 360 }}>
                      🏍️ {ride.name || 'Projetá jízda'}
                    </button>
                    <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                      {names[ride.user_id] || 'Motorkář'}
                    </span>
                    {ride.visibility === 'public' && (
                      <span className="text-[9px] font-extrabold uppercase rounded-btn"
                        style={{ padding: '2px 6px', background: '#e8ffe8', color: '#1a8a18' }}>Veřejná</span>
                    )}
                    {ride.is_recording && (
                      <span className="text-[9px] font-extrabold uppercase rounded-btn"
                        style={{ padding: '2px 6px', background: '#fef3c7', color: '#b45309' }}>Nahrává se</span>
                    )}
                    {isHidden && (
                      <span className="text-[9px] font-extrabold uppercase rounded-btn"
                        style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>Skryto</span>
                    )}
                  </div>
                  <span className="text-xs" style={{ color: '#6b8f7b' }}>{fmtDate(ride.started_at)}</span>
                </div>

                <div className="flex gap-3 flex-wrap text-xs font-bold mb-2" style={{ color: '#4a6357' }}>
                  <span>📏 {Number(ride.distance_km || 0).toFixed(1)} km</span>
                  <span>⏱️ {fmtDur(ride.duration_min)}</span>
                  <span>📍 {stops} zastávek</span>
                  <span>📷 {photoCount(ride.id)} fotek</span>
                  {ride.moto_name && <span>🏍️ {ride.moto_name}</span>}
                  {ride.booking_id && (
                    <a href={`/rezervace/${ride.booking_id}`} style={{ color: '#1a8a18' }}>🔗 rezervace</a>
                  )}
                </div>

                {ride.description?.trim() && (
                  <p className="text-sm mb-2" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>
                    {ride.description}
                  </p>
                )}

                <div className="flex gap-2 items-center flex-wrap">
                  <SmallBtn color="#1a8a18" onClick={() => setDetail({ ...ride, points: pts })}>
                    Detail a úpravy
                  </SmallBtn>
                  <SmallBtn color={isHidden ? '#1a8a18' : '#b45309'} onClick={() => toggleHidden(ride)}>
                    {isHidden ? 'Zobrazit' : 'Skrýt'}
                  </SmallBtn>
                  {confirm === ride.id ? (
                    <>
                      <span className="text-xs font-bold" style={{ color: '#dc2626' }}>Opravdu smazat?</span>
                      <SmallBtn color="#dc2626" onClick={() => remove(ride)}>Ano, smazat</SmallBtn>
                      <SmallBtn color="#6b7280" onClick={() => setConfirm(null)}>Zrušit</SmallBtn>
                    </>
                  ) : (
                    <SmallBtn color="#dc2626" onClick={() => setConfirm(ride.id)}>Smazat</SmallBtn>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {detail && (
        <TrasyJizdaModal
          ride={detail}
          authorName={names[detail.user_id]}
          onClose={() => setDetail(null)}
          onChanged={() => { load(); onChanged?.() }}
        />
      )}
    </div>
  )
}
