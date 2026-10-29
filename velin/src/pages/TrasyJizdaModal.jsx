import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import TrasyJizdaMapa from './TrasyJizdaMapa'
import TrasyJizdaDiag from './TrasyJizdaDiag'
import TrasyJizdaBody from './TrasyJizdaBody'
import TrasyJizdaEtapy from './TrasyJizdaEtapy'
import TrasyJizdaCesta from './TrasyJizdaCesta'
import TrasyJizdaStav, { RideStatTiles } from './TrasyJizdaStav'
import { trackQuality, fmtGap } from '../lib/rideTrack'
import { rideCoreStats, rideRecState, rideDays, fmtSince, cz } from '../lib/rideStats'

// Detail projeté jízdy zákazníka — mapa se stopou, statistiky (pauzy, etapy
// po dnech, příslušnost k cestě — stejně jako appka) a EDITACE:
// název, popis, sdílení (soukromá/veřejná), moderace (zobrazit/skrýt),
// zastávky (název, popisek, mazání fotek i celé zastávky — TrasyJizdaBody).
// Zápis jde přímo do tabulek (Velín má admin RLS politiku).

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
// < 1024 px: na nízkém displeji (telefon na šířku) nižší mapa — jinak vyplní celou
// plochu mezi lepivou hlavičkou a patičkou a tah prstem jen posouvá mapu, ne detail.
const MAP_H = 'max-lg:!h-[min(320px,45dvh)]'
// Telefon na šířku (nízký displej): tenčí lepivá hlavička a patička → víc místa pro obsah.
const LOW_PAD = 'max-lg:[@media(max-height:500px)]:!py-2'

export default function TrasyJizdaModal({ ride, authorName, onClose, onChanged, trip, onOpenRide }) {
  const [name, setName] = useState(ride.name || '')
  const [description, setDescription] = useState(ride.description || '')
  const [visibility, setVisibility] = useState(ride.visibility || 'private')
  const [status, setStatus] = useState(ride.status || 'approved')
  const [points, setPoints] = useState(ride.points || [])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  // Stopa se dotahuje až tady — seznam jízd ji záměrně nenačítá (jsonb
  // s tisíci body × stovky jízd = zbytečné megabajty na každé otevření).
  const [track, setTrack] = useState(Array.isArray(ride.track) ? ride.track : null)
  // Etapy (dny) se načítají spolu se stopou — DB bez sloupce `stages` (SQL
  // „pauzy jízd" ještě nenasazené) prostě etapy nemá.
  const [stages, setStages] = useState(Array.isArray(ride.stages) ? ride.stages : [])
  const [closing, setClosing] = useState(false)

  useEffect(() => {
    if (track !== null) return
    let alive = true
    const one = (cols) => supabase.from('user_rides').select(cols).eq('id', ride.id).maybeSingle()
    ;(async () => {
      let { data, error } = await one('track, stages')
      if (error && (error.code === '42703' || /column .* does not exist/.test(error.message || ''))) {
        ;({ data, error } = await one('track'))
      }
      if (!alive) return
      if (error) { setErr(error.message); setTrack([]); return }
      setTrack(Array.isArray(data?.track) ? data.track : [])
      if (Array.isArray(data?.stages)) setStages(data.stages)
    })()
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ride.id])

  const q = trackQuality(ride, track || [])
  // live (bod < 15 min) / standing (stojí — nová appka při stání nic
  // neposílá) / stuck („visí": bez bodu déle, než dává smysl).
  const recState = rideRecState(ride)
  const stuck = recState === 'stuck'
  const days = rideDays(ride, stages)

  async function saveRide() {
    setSaving(true); setErr(null)
    const patch = {
      name: (name || '').trim().slice(0, 120),
      description: (description || '').trim() || null,
      status,
      updated_at: new Date().toISOString(),
    }
    // Sdílení nastavuje ZÁKAZNÍK. Posíláme ho jen když s ním operátor
    // opravdu hnul — jinak by uložení názvu přepsalo hodnotu, kterou si
    // zákazník mezitím v appce změnil, tou z okamžiku otevření modalu.
    if (visibility !== (ride.visibility || 'private')) patch.visibility = visibility

    const { error } = await supabase.from('user_rides').update(patch).eq('id', ride.id)
    setSaving(false)
    if (error) { setErr(error.message); return }
    onChanged?.()
    onClose?.()
  }

  /** Uzavře zaseknutou nahrávku stejnou cestou jako appka i cron. */
  async function closeStuck() {
    setClosing(true); setErr(null)
    try {
      const { data, error } = await supabase
        .rpc('admin_finish_user_ride', { p_ride_id: ride.id })
      if (error) throw error
      if (data?.success === false) throw new Error(data.error)
      // Uzavření jízdy pod 1 km ji SMAŽE (stejné pravidlo jako v appce).
      // Operátor to musí vidět — jinak klikne, dostane zelenou a jízda
      // beze slova zmizí ze seznamu.
      if (data?.discarded) {
        window.alert('Záznam ukončen. Jízda měla méně než 1 km ověřené trasy, '
          + 'takže byla podle pravidel smazána (parkování se do deníku neukládá).')
      }
      onChanged?.()
      onClose?.()
    } catch (e) {
      setErr(e.message || String(e))
    } finally {
      setClosing(false)
    }
  }

  const label = (txt) => (
    <label className="block text-xs font-extrabold mb-1" style={{ color: '#4a6357' }}>{txt}</label>
  )
  const inputStyle = {
    width: '100%', padding: '8px 12px', borderRadius: 10,
    border: '1px solid #d4e8e0', background: '#f1faf7', fontSize: 14, color: '#0f1a14',
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4"
      style={{ background: 'rgba(15,26,20,.55)' }} onClick={onClose}>
      <div className="mg-modal rounded-card w-full" onClick={e => e.stopPropagation()}
        style={{ background: '#fff', maxWidth: 860, maxHeight: '92vh', overflowY: 'auto' }}>
        {/* hlavička */}
        <div className={`flex items-center justify-between gap-3 p-4 ${LOW_PAD}`}
          style={{ borderBottom: '1px solid #d4e8e0', position: 'sticky', top: 0, background: '#fff', zIndex: 2 }}>
          <div className="min-w-0">
            <h3 className="font-extrabold text-lg truncate" style={{ color: '#0f1a14' }}>
              🏍️ {ride.name || 'Projetá jízda'}
            </h3>
            <p className="text-xs" style={{ color: '#6b8f7b' }}>
              {authorName || 'Motorkář'} · {fmtDate(ride.started_at)}
              {ride.moto_name ? ` · ${ride.moto_name}` : ''}
              {ride.source === 'manual' ? ' · ručně vytvořená' : ' · automatický záznam'}
            </p>
          </div>
          <button onClick={onClose} className="cursor-pointer text-xl font-bold shrink-0 max-lg:min-w-[40px] max-lg:min-h-[40px]"
            style={{ background: 'none', border: 'none', color: '#6b8f7b' }}>✕</button>
        </div>

        <div className="p-4 flex flex-col gap-4">
          {err && <p className="text-sm" style={{ color: '#dc2626' }}>{err}</p>}

          {track === null ? (
            <div className={`rounded-card flex justify-center items-center ${MAP_H}`}
              style={{ border: '1px solid #d4e8e0', height: 320, background: '#f1faf7' }}>
              <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
            </div>
          ) : (
            <TrasyJizdaMapa
              heightClass={MAP_H}
              track={track}
              points={points}
              fitKey={ride.id}
              live={ride.is_recording && ride.end_lat != null ? {
                lat: ride.end_lat, lng: ride.end_lng,
                isLive: recState === 'live',
                paused: recState === 'standing',
                label: stuck
                  ? `Naposledy viděn ${fmtDate(ride.last_fix_at)}`
                  : recState === 'standing'
                    ? `Stojí od ${fmtSince(ride.last_fix_at || ride.updated_at)}`
                    : 'Poslední známá poloha',
              } : null}
            />
          )}

          {/* Ručně poskládaná jízda má pár bodů z principu — varování o
              „staré appce" by u ní operátora jen mátlo. */}
          {q.points > 0 && q.sparse && ride.source !== 'manual' && (
            <p className="text-xs rounded-card" style={{
              background: '#fffbeb', border: '1px solid #fde68a', color: '#92400e', padding: '8px 10px',
            }}>
              ⚠️ <b>Řídká stopa</b> — {q.points} bodů na {Number(ride.distance_km || 0).toFixed(1)} km
              {q.gaps > 0 && `, ${q.gaps}× výpadek signálu`}
              {ride.gap_sec > 0 && ` (celkem ${fmtGap(ride.gap_sec)} bez signálu)`}.
              Šedé přerušované úseky na mapě jsou místa, kde appka polohu
              neposílala — tudy zákazník jet nemusel a nepočítají se ani do
              kilometrů. Nejčastěji appka zavřená nebo uspaná systémem na
              pozadí — proč přesně, ukáže Diagnostika záznamu níže.
            </p>
          )}

          {q.segments.some(sg => sg.gapBefore?.kind === 'pause' && sg.gapBefore.moved) && (
            <p className="text-xs" style={{ color: '#4a5d75' }}>
              〰️ Modrošedá čárkovaná čára = přesun během pauzy (trajekt, přívěs…) — do kilometrů se nepočítá.
            </p>
          )}

          <TrasyJizdaStav ride={ride} state={recState} closing={closing} onEnd={closeStuck} />

          {/* statistiky jízdy — kompletní přehled (stejné hodnoty jako appka) */}
          <RideStatTiles cells={[
            ...rideCoreStats(ride, { pauseCount: q.pauses }),
            ['⛰️', 'Nastoupáno', ride.elevation_gain_m ? `${ride.elevation_gain_m} m` : '—'],
            ['📅', 'Dny', cz(days, 'den', 'dny', 'dní'), 'Dny, kdy se opravdu jelo (z etap; jinak kalendářní dny jízdy)'],
            ['📍', 'Zastávek', String(points.filter(p => p.kind === 'stop').length), 'Místa, která si zákazník uložil (fotky, popisky)'],
            ['📷', 'Fotek', String(points.reduce((n, p) => n + (Array.isArray(p.photos) ? p.photos.length : 0), 0))],
            ['🛰️', 'Bodů stopy', track === null ? '…' : String(q.points)],
            ['🚦', 'Start', fmtDate(ride.started_at)],
            ['🏁', 'Konec', ride.ended_at ? fmtDate(ride.ended_at)
              : (stuck ? 'záznam visí' : (recState === 'standing' ? 'stojí (pauza)' : 'nahrává se'))],
          ]} />
          <TrasyJizdaEtapy stages={stages} />
          <TrasyJizdaCesta trip={trip} currentId={ride.id} onOpen={onOpenRide} />
          {/* Proč ve stopě chybí úsek: verze appky, popředí/pozadí, GPS. */}
          {ride.source !== 'manual' && ride.user_id && <TrasyJizdaDiag ride={ride} track={track} />}
          {ride.booking_id && (
            <a href={`/rezervace/${ride.booking_id}`} className="text-sm font-extrabold max-lg:flex max-lg:items-center max-lg:min-h-[36px]"
              style={{ color: '#1a8a18' }}>🔗 Otevřít rezervaci této výpůjčky</a>
          )}

          {/* editace jízdy */}
          <div className="grid gap-3 grid-cols-1 sm:grid-cols-[1fr_1fr]">
            <div style={{ gridColumn: '1 / -1' }}>
              {label('Název jízdy')}
              <input style={inputStyle} value={name} onChange={e => setName(e.target.value)} />
            </div>
            <div style={{ gridColumn: '1 / -1' }}>
              {label('Popis zážitku')}
              <textarea style={{ ...inputStyle, minHeight: 80, resize: 'vertical' }}
                value={description} onChange={e => setDescription(e.target.value)} />
            </div>
            <div>
              {label('Sdílení (nastavuje zákazník)')}
              <select style={inputStyle} value={visibility} onChange={e => setVisibility(e.target.value)}>
                <option value="private">🔒 Soukromá — vidí jen zákazník</option>
                <option value="public">🌍 Veřejná — vidí ostatní motorkáři</option>
              </select>
            </div>
            <div>
              {label('Moderace')}
              <select style={inputStyle} value={status} onChange={e => setStatus(e.target.value)}>
                <option value="approved">✅ Zobrazená</option>
                <option value="hidden">🙈 Skrytá (nevhodný obsah)</option>
              </select>
            </div>
          </div>

          {/* body jízdy */}
          <TrasyJizdaBody points={points} setPoints={setPoints} setErr={setErr}
            onChanged={onChanged} inputStyle={inputStyle} />
        </div>

        {/* patička */}
        <div className={`flex gap-2 justify-end p-4 ${LOW_PAD}`}
          style={{ borderTop: '1px solid #d4e8e0', position: 'sticky', bottom: 0, background: '#fff' }}>
          <button onClick={onClose} className="rounded-btn text-sm font-extrabold cursor-pointer"
            style={{ padding: '8px 16px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}>
            Zavřít
          </button>
          <button onClick={saveRide} disabled={saving}
            className="rounded-btn text-sm font-extrabold cursor-pointer"
            style={{ padding: '8px 18px', background: '#74FB71', color: '#0f1a14', border: 'none', opacity: saving ? 0.6 : 1 }}>
            {saving ? 'Ukládám…' : 'Uložit jízdu'}
          </button>
        </div>
      </div>
    </div>
  )
}
