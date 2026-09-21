import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import TrasyJizdaMapa from '../TrasyJizdaMapa'
import { trackQuality, fmtGap } from '../../lib/rideTrack'

// Detail rezervace → „Mapa a poloha": kde zákazník právě je a kudy dosud jel.
//
// Zdroj dat je RPC `admin_booking_live_ride` (SECURITY DEFINER, is_admin()):
// vrací poslední známou polohu z PRÁVĚ NAHRÁVANÉ jízdy k téhle rezervaci
// plus dosavadní stopu (prořídnutou na 1200 bodů, ať se netahá celý jsonb).
//
// Poloha chodí z appky po dávkách (nejpozději po ~90 s), takže „živá" =
// poslední fix mladší 15 minut. Když je starší, ukážeme kdy naposledy —
// nikdy netvrdíme, že zákazník je tam, kde byl před hodinou.
//
// user_rides NENÍ v supabase_realtime publikaci (a tahat celý `track`
// realtimem by ani nedávalo smysl), takže se dotazujeme pollingem.

const POLL_LIVE_MS = 20000 // nahrává se → obnovuj svižně
const POLL_IDLE_MS = 90000 // dojeté / nic neběží → jen občas

const fmtTime = (v) => v
  ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' })
  : '—'
const fmtDur = (min) => min == null ? '—'
  : (min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`)
const fmtSec = (sec) => !sec ? '—' : fmtDur(Math.round(sec / 60))
const fmtSpeed = (v) => v == null || Number(v) <= 0 ? '—' : `${Math.round(Number(v))} km/h`

const REASONS = {
  no_app: {
    title: 'Zákazník nemá appku',
    hint: 'Trasa i poloha vznikají jen v mobilní aplikaci MotoGo24. Tenhle zákazník ji zatím nepoužil.',
  },
  app_idle: {
    title: 'Appku dlouho neotevřel',
    hint: 'Aplikace se neozvala přes dva týdny — buď ji smazal, nebo ji na téhle výpůjčce nepoužívá.',
  },
  no_location: {
    title: 'Poloha není zapnutá',
    hint: 'Appku má, ale záznam trasy neběží — buď nemá povolenou polohu, nebo si záznam v „Mých zážitcích" vypnul. Je to jeho volba, Velín ji nepřepíná.',
  },
}

export default function BookingLiveMap({ bookingId, booking }) {
  const [data, setData] = useState(null)
  const [err, setErr] = useState(null)
  const [loading, setLoading] = useState(true)
  const [closing, setClosing] = useState(false)
  const timerRef = useRef(null)

  const load = useCallback(async (silent) => {
    if (!silent) setLoading(true)
    try {
      const { data: res, error } = await supabase
        .rpc('admin_booking_live_ride', { p_booking_id: bookingId })
      if (error) throw error
      if (res && res.ok === false) throw new Error(
        res.error === 'forbidden'
          ? 'Na živou polohu nemáte oprávnění.'
          : `Načtení polohy selhalo: ${res.error}`)
      setData(res)
      setErr(null)
    } catch (e) {
      setErr(e.message || String(e))
    } finally {
      setLoading(false)
    }
  }, [bookingId])

  useEffect(() => { load(false) }, [load])

  // Polling — rychleji jen dokud se opravdu nahrává.
  useEffect(() => {
    const ms = data?.is_recording ? POLL_LIVE_MS : POLL_IDLE_MS
    clearInterval(timerRef.current)
    timerRef.current = setInterval(() => {
      // Skrytá záložka prohlížeče nepotřebuje obnovovat nic.
      if (document.visibilityState === 'hidden') return
      load(true)
    }, ms)
    return () => clearInterval(timerRef.current)
  }, [data?.is_recording, load])

  async function closeStuck() {
    if (!data?.ride_id) return
    setClosing(true)
    try {
      const { data: res, error } = await supabase
        .rpc('admin_finish_user_ride', { p_ride_id: data.ride_id })
      if (error) throw error
      if (res?.success === false) throw new Error(res.error)
      await load(true)
    } catch (e) {
      setErr(e.message || String(e))
    } finally {
      setClosing(false)
    }
  }

  const card = {
    background: '#fff', border: '1px solid #d4e8e0', padding: '14px 16px',
  }

  if (loading && !data) {
    return (
      <div className="rounded-card flex justify-center py-12" style={card}>
        <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
      </div>
    )
  }

  if (err) {
    return (
      <div className="rounded-card" style={{ ...card, background: '#fef2f2', border: '1px solid #fecaca' }}>
        <p className="text-sm font-bold" style={{ color: '#dc2626' }}>{err}</p>
        <button onClick={() => load(false)} className="rounded-btn text-xs font-extrabold cursor-pointer mt-2"
          style={{ padding: '6px 12px', border: 'none', background: '#f1faf7', color: '#1a2e22' }}>
          Zkusit znovu
        </button>
      </div>
    )
  }

  // ── Zákazník polohu nesdílí ───────────────────────────────────────────
  if (!data?.has_ride) {
    const r = REASONS[data?.reason] || REASONS.no_location
    return (
      <div className="rounded-card" style={card}>
        <h3 className="font-extrabold text-base mb-1" style={{ color: '#0f1a14' }}>📍 {r.title}</h3>
        <p className="text-sm mb-3" style={{ color: '#4a6357' }}>{r.hint}</p>
        <p className="text-xs" style={{ color: '#6b8f7b' }}>
          Appka naposledy online: {fmtTime(data?.app_last_seen)}
          {' · '}stav rezervace: {data?.booking_status || booking?.status || '—'}
        </p>
        <button onClick={() => load(false)} className="rounded-btn text-xs font-extrabold cursor-pointer mt-3"
          style={{ padding: '6px 12px', border: 'none', background: '#f1faf7', color: '#1a2e22' }}>
          Obnovit
        </button>
      </div>
    )
  }

  const q = trackQuality(data, data.track)
  // Stáří fixu počítá server při každém dotazu — nepřepočítáváme ho v UI,
  // ať nehlásíme „před 2 s" pro bod, který je ve skutečnosti hodinu starý.
  const ageSec = Number(data.age_sec || 0)
  const isLive = !!data.is_live
  const recording = !!data.is_recording
  // „Visí" = pořád se tváří jako nahrávané, ale hodiny nic nepřišlo.
  const stuck = recording && ageSec > 3 * 3600

  const badge = (bg, color, text) => (
    <span className="text-[10px] font-extrabold uppercase rounded-btn"
      style={{ padding: '3px 8px', background: bg, color }}>{text}</span>
  )

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-card" style={card}>
        <div className="flex items-center gap-2 flex-wrap mb-2">
          <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>
            📍 Poloha zákazníka
          </h3>
          {isLive && badge('#dcfce7', '#15803d', '● Živě')}
          {recording && !isLive && badge('#fef3c7', '#b45309', `Poslední signál před ${fmtGap(ageSec)}`)}
          {!recording && badge('#f1f5f9', '#475569', 'Jízda dojetá')}
          {stuck && badge('#fee2e2', '#dc2626', 'Záznam visí')}
          <span className="ml-auto text-xs" style={{ color: '#6b8f7b' }}>
            aktualizace {recording ? 'každých 20 s' : 'každých 90 s'}
          </span>
        </div>

        <p className="text-sm mb-3" style={{ color: '#4a6357' }}>
          {isLive
            ? `Poslední GPS bod dorazil před ${fmtGap(ageSec)} (${fmtTime(data.last_fix_at)}). Appka posílá polohu po dávkách, takže menší zpoždění je normální.`
            : recording
              ? `Záznam pořád běží, ale poslední GPS bod je z ${fmtTime(data.last_fix_at)}. Zákazník má nejspíš vypnutý telefon nebo je bez signálu — značka na mapě ukazuje, kde byl naposledy.`
              : `Jízda je ukončená (${fmtTime(data.ended_at)}). Na mapě je celá projetá trasa.`}
        </p>

        <TrasyJizdaMapa
          track={data.track || []}
          points={[]}
          live={{
            lat: data.lat, lng: data.lng, isLive,
            label: isLive
              ? 'Aktuální poloha zákazníka'
              : `Naposledy viděn ${fmtTime(data.last_fix_at)}`,
          }}
          fitKey={data.ride_id}
          height={420}
        />
      </div>

      <div className="rounded-card" style={card}>
        <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
          {[
            ['📏', 'Ujeto', `${Number(data.distance_km || 0).toFixed(1)} km`],
            ['⏱️', 'Celkový čas', fmtDur(data.duration_min)],
            ['🏍️', 'Čas jízdy', fmtSec(data.moving_sec)],
            ['⏸️', 'Čas stání', fmtSec(data.idle_sec)],
            ['📵', 'Bez signálu', data.gap_sec ? fmtGap(data.gap_sec) : '—'],
            ['📊', 'Ø rychlost', fmtSpeed(data.avg_speed_kmh)],
            ['🚀', 'Max. rychlost', fmtSpeed(data.max_speed_kmh)],
            ['🛰️', 'Bodů stopy', String(q.points)],
            ['🚦', 'Start jízdy', fmtTime(data.started_at)],
            ['🛵', 'Motorka', data.moto_name || '—'],
          ].map(([emoji, label, value]) => (
            <div key={label} className="rounded-card"
              style={{ background: '#f1faf7', border: '1px solid #d4e8e0', padding: '8px 10px' }}>
              <div className="text-[10px] font-extrabold uppercase" style={{ color: '#6b8f7b' }}>
                {emoji} {label}
              </div>
              <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{value}</div>
            </div>
          ))}
        </div>

        {q.sparse && (
          <p className="text-xs mt-3 rounded-card" style={{
            background: '#fffbeb', border: '1px solid #fde68a', color: '#92400e', padding: '8px 10px',
          }}>
            ⚠️ Stopa je řídká ({q.points} bodů na {Number(data.distance_km || 0).toFixed(1)} km
            {q.gaps > 0 ? `, ${q.gaps}× výpadek signálu` : ''}). Úseky, kde appka
            polohu neposílala, jsou na mapě šedě přerušovaně — tudy zákazník
            nemusel jet. Nejčastější příčina: starší verze appky bez záznamu
            na pozadí, nebo vypnutá poloha během jízdy.
          </p>
        )}

        {stuck && (
          <div className="mt-3 rounded-card" style={{
            background: '#fef2f2', border: '1px solid #fecaca', padding: '8px 10px',
          }}>
            <p className="text-xs mb-2" style={{ color: '#991b1b' }}>
              Záznam se pořád tváří jako běžící, ale {fmtGap(ageSec)} nepřišel
              žádný GPS bod. Dokud visí, nemůže zákazníkovi vzniknout další
              jízda. (Server ho uklidí sám do tří hodin — tímhle to jde hned.)
            </p>
            <button onClick={closeStuck} disabled={closing}
              className="rounded-btn text-xs font-extrabold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none', background: '#dc2626',
                color: '#fff', opacity: closing ? .6 : 1,
              }}>
              {closing ? 'Ukončuji…' : 'Ukončit záznam'}
            </button>
          </div>
        )}

        <p className="text-xs mt-3" style={{ color: '#6b8f7b' }}>
          Trasa je zákazníkův soukromý zápisník — ve Velíně ji vidíte kvůli
          provozu výpůjčky. Detail a moderace: <a href="/trasy"
            style={{ color: '#1a8a18', fontWeight: 700 }}>Trasy → Jízdy zákazníků</a>.
        </p>
      </div>
    </div>
  )
}
