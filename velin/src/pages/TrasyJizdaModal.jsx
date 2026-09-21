import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { SmallBtn } from './BranchHelpers'
import TrasyJizdaMapa from './TrasyJizdaMapa'
import { trackQuality, fmtGap } from '../lib/rideTrack'

// Detail projeté jízdy zákazníka — mapa se stopou, statistiky a EDITACE:
// název, popis, sdílení (soukromá/veřejná), moderace (zobrazit/skrýt),
// zastávky (název, popisek, mazání fotek i celé zastávky).
// Zápis jde přímo do tabulek (Velín má admin RLS politiku).

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
const fmtDur = (min) => min == null ? '—' : (min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`)
const fmtSec = (sec) => !sec ? '—' : fmtDur(Math.round(sec / 60))
const fmtSpeed = (v) => v == null || Number(v) <= 0 ? '—' : `${Math.round(Number(v))} km/h`
const kindLabel = (k) => k === 'start' ? 'Start' : k === 'end' ? 'Cíl' : 'Zastávka'

export default function TrasyJizdaModal({ ride, authorName, onClose, onChanged }) {
  const [name, setName] = useState(ride.name || '')
  const [description, setDescription] = useState(ride.description || '')
  const [visibility, setVisibility] = useState(ride.visibility || 'private')
  const [status, setStatus] = useState(ride.status || 'approved')
  const [points, setPoints] = useState(ride.points || [])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [confirmDel, setConfirmDel] = useState(null)
  // Stopa se dotahuje až tady — seznam jízd ji záměrně nenačítá (jsonb
  // s tisíci body × stovky jízd = zbytečné megabajty na každé otevření).
  const [track, setTrack] = useState(Array.isArray(ride.track) ? ride.track : null)
  const [closing, setClosing] = useState(false)

  useEffect(() => {
    if (track !== null) return
    let alive = true
    supabase.from('user_rides').select('track').eq('id', ride.id).maybeSingle()
      .then(({ data, error }) => {
        if (!alive) return
        if (error) { setErr(error.message); setTrack([]); return }
        setTrack(Array.isArray(data?.track) ? data.track : [])
      })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ride.id])

  const q = trackQuality(ride, track || [])
  // „Visí" = pořád se tváří jako nahrávané, ale hodiny nepřišel žádný bod.
  const stuck = !!ride.is_recording && Date.now() -
    new Date(ride.last_fix_at || ride.started_at).getTime() > 3 * 3600 * 1000

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
      onChanged?.()
      onClose?.()
    } catch (e) {
      setErr(e.message || String(e))
    } finally {
      setClosing(false)
    }
  }

  async function savePoint(p, patch) {
    const { error } = await supabase.from('user_ride_points')
      .update({ ...patch, updated_at: new Date().toISOString() }).eq('id', p.id)
    if (error) { setErr(error.message); return }
    setPoints(ps => ps.map(x => x.id === p.id ? { ...x, ...patch } : x))
    onChanged?.()
  }

  async function deletePoint(p) {
    const { error } = await supabase.from('user_ride_points').delete().eq('id', p.id)
    setConfirmDel(null)
    if (error) { setErr(error.message); return }
    setPoints(ps => ps.filter(x => x.id !== p.id))
    onChanged?.()
  }

  function removePhoto(p, url) {
    savePoint(p, { photos: (p.photos || []).filter(u => u !== url) })
  }

  const label = (txt) => (
    <label className="block text-xs font-extrabold mb-1" style={{ color: '#4a6357' }}>{txt}</label>
  )
  const inputStyle = {
    width: '100%', padding: '8px 12px', borderRadius: 10,
    border: '1px solid #d4e8e0', background: '#f1faf7', fontSize: 14, color: '#0f1a14',
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(15,26,20,.55)' }} onClick={onClose}>
      <div className="rounded-card w-full" onClick={e => e.stopPropagation()}
        style={{ background: '#fff', maxWidth: 860, maxHeight: '92vh', overflowY: 'auto' }}>
        {/* hlavička */}
        <div className="flex items-center justify-between gap-3 p-4"
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
          <button onClick={onClose} className="cursor-pointer text-xl font-bold"
            style={{ background: 'none', border: 'none', color: '#6b8f7b' }}>✕</button>
        </div>

        <div className="p-4 flex flex-col gap-4">
          {err && <p className="text-sm" style={{ color: '#dc2626' }}>{err}</p>}

          {track === null ? (
            <div className="rounded-card flex justify-center items-center"
              style={{ border: '1px solid #d4e8e0', height: 320, background: '#f1faf7' }}>
              <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
            </div>
          ) : (
            <TrasyJizdaMapa
              track={track}
              points={points}
              fitKey={ride.id}
              live={ride.is_recording && ride.end_lat != null ? {
                lat: ride.end_lat, lng: ride.end_lng,
                isLive: !stuck,
                label: stuck
                  ? `Naposledy viděn ${fmtDate(ride.last_fix_at)}`
                  : 'Poslední známá poloha',
              } : null}
            />
          )}

          {q.points > 0 && q.sparse && (
            <p className="text-xs rounded-card" style={{
              background: '#fffbeb', border: '1px solid #fde68a', color: '#92400e', padding: '8px 10px',
            }}>
              ⚠️ <b>Řídká stopa</b> — {q.points} bodů na {Number(ride.distance_km || 0).toFixed(1)} km
              {q.gaps > 0 && `, ${q.gaps}× výpadek signálu`}
              {ride.gap_sec > 0 && ` (celkem ${fmtGap(ride.gap_sec)} bez signálu)`}.
              Šedé přerušované úseky na mapě jsou místa, kde appka polohu
              neposílala — tudy zákazník jet nemusel a nepočítají se ani do
              kilometrů. Typicky starší verze appky bez záznamu na pozadí.
            </p>
          )}

          {stuck && (
            <div className="rounded-card" style={{
              background: '#fef2f2', border: '1px solid #fecaca', padding: '10px 12px',
            }}>
              <p className="text-xs mb-2" style={{ color: '#991b1b' }}>
                <b>Záznam visí.</b> Tváří se jako běžící, ale poslední GPS bod
                dorazil {fmtDate(ride.last_fix_at)}. Dokud je otevřený,
                nevznikne zákazníkovi žádná další jízda. Server ho uklidí sám
                do tří hodin — tímhle to uzavřete hned.
              </p>
              <SmallBtn color="#dc2626" onClick={closeStuck}>
                {closing ? 'Ukončuji…' : 'Ukončit záznam'}
              </SmallBtn>
            </div>
          )}

          {/* statistiky jízdy — kompletní přehled */}
          <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
            {[
              ['📏', 'Celkem ujeto', `${Number(ride.distance_km || 0).toFixed(1)} km`],
              ['⏱️', 'Celkový čas', fmtDur(ride.duration_min)],
              ['🏍️', 'Čas jízdy', fmtSec(ride.moving_sec)],
              ['⏸️', 'Čas stání', fmtSec(ride.idle_sec)],
              ['📊', 'Ø rychlost', fmtSpeed(ride.avg_speed_kmh)],
              ['🚀', 'Max. rychlost', fmtSpeed(ride.max_speed_kmh)],
              ['📵', 'Bez signálu', ride.gap_sec ? fmtGap(ride.gap_sec) : '—'],
              ['⛰️', 'Nastoupáno', ride.elevation_gain_m ? `${ride.elevation_gain_m} m` : '—'],
              ['📍', 'Zastávek', String(points.filter(p => p.kind === 'stop').length)],
              ['📷', 'Fotek', String(points.reduce((n, p) => n + (Array.isArray(p.photos) ? p.photos.length : 0), 0))],
              ['🛰️', 'Bodů stopy', track === null ? '…' : String(q.points)],
              ['🚦', 'Start', fmtDate(ride.started_at)],
              ['🏁', 'Konec', ride.ended_at ? fmtDate(ride.ended_at)
                : (stuck ? 'záznam visí' : 'nahrává se')],
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
          {ride.booking_id && (
            <a href={`/rezervace/${ride.booking_id}`} className="text-sm font-extrabold"
              style={{ color: '#1a8a18' }}>🔗 Otevřít rezervaci této výpůjčky</a>
          )}

          {/* editace jízdy */}
          <div className="grid gap-3" style={{ gridTemplateColumns: '1fr 1fr' }}>
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
          <div>
            <h4 className="font-extrabold text-sm mb-2" style={{ color: '#0f1a14' }}>
              Body jízdy ({points.length})
            </h4>
            {points.length === 0 ? (
              <p className="text-xs" style={{ color: '#8aab99' }}>Jízda zatím nemá žádné body.</p>
            ) : (
              <div className="flex flex-col gap-2">
                {points.map(p => (
                  <div key={p.id} className="rounded-card"
                    style={{ background: '#f1faf7', border: '1px solid #d4e8e0', padding: '10px 12px' }}>
                    <div className="flex items-center gap-2 mb-2 flex-wrap">
                      <span className="text-[9px] font-extrabold uppercase rounded-btn"
                        style={{ padding: '2px 6px', background: '#e8ffe8', color: '#1a8a18' }}>
                        {kindLabel(p.kind)}
                      </span>
                      <input
                        defaultValue={p.name || ''}
                        placeholder="Název bodu"
                        onBlur={e => {
                          const v = e.target.value.trim().slice(0, 120)
                          if (v !== (p.name || '')) savePoint(p, { name: v })
                        }}
                        style={{ ...inputStyle, flex: 1, minWidth: 180, padding: '5px 10px' }} />
                      <span className="text-[10px]" style={{ color: '#8aab99' }}>
                        {Number(p.lat).toFixed(4)}, {Number(p.lng).toFixed(4)}
                      </span>
                      {confirmDel === p.id ? (
                        <>
                          <SmallBtn color="#dc2626" onClick={() => deletePoint(p)}>Ano, smazat</SmallBtn>
                          <SmallBtn color="#6b7280" onClick={() => setConfirmDel(null)}>Zrušit</SmallBtn>
                        </>
                      ) : (
                        <SmallBtn color="#dc2626" onClick={() => setConfirmDel(p.id)}>Smazat bod</SmallBtn>
                      )}
                    </div>
                    <textarea
                      defaultValue={p.note || ''}
                      placeholder="Popisek zastávky"
                      onBlur={e => {
                        const v = e.target.value.trim()
                        if (v !== (p.note || '')) savePoint(p, { note: v || null })
                      }}
                      style={{ ...inputStyle, background: '#fff', minHeight: 50, resize: 'vertical' }} />
                    {Array.isArray(p.photos) && p.photos.length > 0 && (
                      <div className="flex gap-2 flex-wrap mt-2">
                        {p.photos.map((url, i) => (
                          <div key={i} style={{ position: 'relative' }}>
                            <a href={url} target="_blank" rel="noreferrer">
                              <img src={url} alt="" onError={e => { e.target.style.opacity = 0.3 }}
                                style={{ width: 72, height: 72, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }} />
                            </a>
                            <button onClick={() => removePhoto(p, url)} title="Odebrat fotku"
                              className="cursor-pointer"
                              style={{
                                position: 'absolute', top: -6, right: -6, width: 20, height: 20,
                                borderRadius: '50%', background: '#dc2626', color: '#fff',
                                border: '2px solid #fff', fontSize: 11, lineHeight: '16px', padding: 0,
                              }}>✕</button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* patička */}
        <div className="flex gap-2 justify-end p-4"
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
