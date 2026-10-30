import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../lib/supabase'
import SearchInput from '../components/ui/SearchInput'
import { SmallBtn } from './BranchHelpers'
import TrasyJizdaModal from './TrasyJizdaModal'
import { RideBadges, RideStatsLine } from './TrasyJizdaInfo'
import { useMediaQuery } from '../hooks/useIsMobile'
import { rideRecState, rentalHoldsRide } from '../lib/rideStats'
import { groupRideTrips, tripOfRide } from '../lib/rideTrip'

// Projeté jízdy zákazníků („Moje jízdy" v appce): stopa GPS z výpůjčky
// (vzniká automaticky, když má zákazník povolenou polohu) + zastávky s
// fotkami a popisky. Velín je čte, edituje, moderuje (skrýt) i maže.
// Jízda je SOUKROMÁ, dokud ji zákazník sám nezveřejní — Velín to respektuje
// a stav sdílení jen zobrazuje (změnit ho lze v detailu).
// Nová appka nahrává jen při jízdě (pauzy, noci) — běžící záznam bez bodu
// je proto „Stojí", ne hned „Záznam visí"; jízda pod 1 km, kterou server drží
// kvůli datům z telefonu bez internetu, „Čeká na data" (stav výpůjček běžících
// nahrávek se dotahuje — stejná pravidla jako server). Víc jízd téže výpůjčky nebo
// sloučených zákazníkem appka ukazuje jako jednu CESTU (štítek 🧳).

const FILTERS = [
  { id: 'all', label: 'Vše' },
  { id: 'public', label: '🌍 Veřejné' },
  { id: 'private', label: '🔒 Soukromé' },
  { id: 'hidden', label: '🙈 Skryté' },
  { id: 'recording', label: '⏺ Nahrávané' },
  { id: 'standing', label: '⏸ Stojí' },
  { id: 'photos', label: '📷 S fotkami' },
]

// Seznam NEČTE sloupec `track` — u stovek jízd po tisících bodů to byly
// megabajty jsonb na každé otevření stránky. Stopu si načte až detail jízdy.
const RIDE_LIST_COLS = [
  'id', 'user_id', 'booking_id', 'moto_id', 'moto_name', 'name', 'description',
  'source', 'start_lat', 'start_lng', 'end_lat', 'end_lng', 'started_at',
  'ended_at', 'distance_km', 'duration_min', 'moving_sec', 'idle_sec',
  'gap_sec', 'last_fix_at', 'avg_speed_kmh', 'max_speed_kmh',
  'elevation_gain_m', 'is_recording', 'visibility', 'status', 'cover_image',
  'created_at', 'updated_at',
].join(',')

/** Sloupce z SQL „pauzy jízd" (pauzy, etapy, cesty). `stats_state` jen jako
 *  značka, jestli čísla spočítal nový výpočet (null = stará uzavřená jízda). */
const RIDE_PAUSE_COLS = ['pause_sec', 'pause_aware', 'trip_id', 'trip_name', 'stages', 'stats_state']

/** Záložní dotazy, když DB nové sloupce ještě (nebo už) nemá: nejdřív bez
 *  sloupců pauz, pak i bez těch z migrace 20260921g (bez „bez signálu"). */
const RIDE_COL_SETS = [
  [RIDE_LIST_COLS, ...RIDE_PAUSE_COLS].join(','),
  RIDE_LIST_COLS,
  RIDE_LIST_COLS.split(',').filter(c => c !== 'gap_sec' && c !== 'last_fix_at').join(','),
]

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
/** Souhrn v sedle za všechny jízdy — v hodinách (dny by u součtu mátly). */
const fmtHours = (sec) => {
  const min = Math.round((Number(sec) || 0) / 60)
  return !sec ? '—' : (min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`)
}

export default function TrasyJizdy({ onChanged }) {
  const [rides, setRides] = useState([])
  const [pointsByRide, setPointsByRide] = useState({})
  const [names, setNames] = useState({})
  const [bookings, setBookings] = useState({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState(null)
  const [confirm, setConfirm] = useState(null)
  const isPhone = useMediaQuery('(max-width: 639px)')   // telefon: hledání přes celou šířku

  useEffect(() => { load() /* eslint-disable-next-line */ }, [])

  async function load() {
    setLoading(true); setErr(null)
    try {
      // Jízdy — stránkovaně (PostgREST vrací max 1000 řádků na dotaz).
      const all = []
      let level = 0 // index do RIDE_COL_SETS — platí pro všechny stránky
      for (let from = 0; ; from += 1000) {
        // `id` jako druhé řazení: bez jednoznačného klíče může stránkování
        // přes hranici 1000 řádků některé jízdy zdvojit a jiné vynechat.
        const page = (cols) => supabase.from('user_rides').select(cols)
          .order('started_at', { ascending: false }).order('id').range(from, from + 999)
        let { data, error } = await page(RIDE_COL_SETS[level])
        // Velín se nasazuje přes Vercel a SQL přes GitHub Actions nezávisle:
        // v okně mezi nimi (nebo po rollbacku) nové sloupce ještě nemusí
        // existovat. Seznam se pak načte bez nich místo prázdné stránky s chybou.
        while (error && level < RIDE_COL_SETS.length - 1 &&
          (error.code === '42703' || /column .* does not exist/.test(error.message || ''))) {
          level++
          ;({ data, error } = await page(RIDE_COL_SETS[level]))
        }
        if (error) {
          throw new Error(
            `Načtení jízd selhalo: ${error.message || 'neznámá chyba'}` +
            (error.code === '42P01' || /relation .* does not exist/.test(error.message || '')
              ? '\n\nTabulka "user_rides" zatím v databázi neexistuje — spusťte prosím SQL migraci jízd.'
              : error.code === '42703'
                ? '\n\nV databázi chybí sloupec jízd — SQL migrace 20260921g ještě neproběhla, nebo byla vrácena.'
                : ''))
        }
        all.push(...(data || []))
        if (!data || data.length < 1000) break
      }
      setRides(all)

      // Stav výpůjček běžících nahrávek (vrácení, konec) — „visí" / „čeká na
      // data" se řídí pravidly serveru. Chyba = stav neznáme (pravidla postaru).
      const bids = [...new Set(all.filter(r => r.is_recording && r.booking_id).map(r => r.booking_id))]
      const bmap = {}
      for (let i = 0; i < bids.length; i += 200) {
        const { data: bks } = await supabase.from('bookings')
          .select('id, status, returned_at, end_date, booking_kind').in('id', bids.slice(i, i + 200))
        ;(bks || []).forEach(b => { bmap[b.id] = b })
      }
      setBookings(bmap)

      // Body jízd (zastávky + start/cíl) — pro počty i detail.
      const byRide = {}
      for (let from = 0; ; from += 1000) {
        const { data, error } = await supabase.from('user_ride_points')
          .select('*').order('sort_order').order('id').range(from, from + 999)
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

  /** Stav nahrávky s rezervací, pokud ji známe (rideRecState). */
  const recStateOf = (r) => {
    const bk = r.booking_id ? bookings[r.booking_id] || null : null
    return rideRecState(r, Date.now(), rentalHoldsRide(bk), bk)
  }

  const photoCount = (id) => (pointsByRide[id] || [])
    .reduce((s, p) => s + (Array.isArray(p.photos) ? p.photos.length : 0), 0)

  // Cesty (≥ 2 jízdy, které appka ukazuje jako jednu) — stejné seskupení jako appka.
  const trips = useMemo(() => groupRideTrips(rides), [rides])

  const filtered = useMemo(() => rides.filter(r => {
    if (filter === 'public' && !(r.visibility === 'public')) return false
    if (filter === 'private' && r.visibility !== 'private') return false
    if (filter === 'hidden' && r.status !== 'hidden') return false
    if (filter === 'recording' && !r.is_recording) return false
    if (filter === 'standing' && recStateOf(r) !== 'standing') return false
    if (filter === 'photos' && photoCount(r.id) === 0) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (r.name || '').toLowerCase().includes(s) ||
      (r.moto_name || '').toLowerCase().includes(s) ||
      (r.trip_name || '').toLowerCase().includes(s) ||
      (names[r.user_id] || '').toLowerCase().includes(s)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [rides, filter, search, names, pointsByRide, bookings])


  const publicCount = rides.filter(r => r.visibility === 'public' && r.status === 'approved').length
  const hiddenCount = rides.filter(r => r.status === 'hidden').length
  const totalKm = Math.round(rides.reduce((s, r) => s + Number(r.distance_km || 0), 0))
  const totalMovingSec = rides.reduce((s, r) => s + Number(r.moving_sec || 0), 0)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat jízdu, jezdce, motorku…" fullWidth={isPhone} />
        <div className="flex gap-1 flex-wrap">
          {FILTERS.map(f => (
            <button key={f.id} onClick={() => setFilter(f.id)}
              className="rounded-btn text-xs font-extrabold cursor-pointer max-lg:min-h-[36px]"
              style={{
                padding: '6px 12px', border: 'none',
                background: filter === f.id ? '#74FB71' : '#f1faf7', color: '#1a2e22',
              }}>
              {f.label}
            </button>
          ))}
        </div>
        <span className="ml-auto text-xs font-bold" style={{ color: '#6b8f7b' }}>
          {rides.length} jízd · {publicCount} veřejných · {hiddenCount} skrytých · {totalKm} km · {fmtHours(totalMovingSec)} v sedle
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
            const recState = recStateOf(ride)
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
                      className="text-sm font-extrabold cursor-pointer truncate max-lg:min-h-[32px]" title="Otevřít detail jízdy"
                      style={{ background: 'none', border: 'none', color: '#1a8a18', padding: 0, maxWidth: 360 }}>
                      🏍️ {ride.name || 'Projetá jízda'}
                    </button>
                    <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                      {names[ride.user_id] || 'Motorkář'}
                    </span>
                    <RideBadges ride={ride} state={recState} trip={tripOfRide(trips, ride)} />
                  </div>
                  <span className="text-xs" style={{ color: '#6b8f7b' }}>{fmtDate(ride.started_at)}</span>
                </div>

                <div className="flex gap-3 flex-wrap text-xs font-bold mb-2 max-lg:items-center" style={{ color: '#4a6357' }}>
                  <RideStatsLine ride={ride} stops={stops} photos={photoCount(ride.id)} />
                </div>

                {ride.description?.trim() && (
                  <p className="text-sm mb-2" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>
                    {ride.description}
                  </p>
                )}

                <div className="flex gap-2 items-center flex-wrap max-lg:[&>button]:min-h-[36px]">
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
          key={detail.id}
          ride={detail}
          authorName={names[detail.user_id]}
          trip={tripOfRide(trips, detail)}
          booking={detail.booking_id ? bookings[detail.booking_id] || null : null}
          onOpenRide={(r) => setDetail({ ...r, points: pointsByRide[r.id] || [] })}
          onClose={() => setDetail(null)}
          onChanged={() => { load(); onChanged?.() }}
        />
      )}
    </div>
  )
}
