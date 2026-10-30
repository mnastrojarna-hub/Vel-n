import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { SmallBtn } from './BranchHelpers'

// Body projeté jízdy (start / cíl / zastávky s fotkami) v detailu jízdy —
// editace názvu a popisku, mazání fotek i celého bodu. Zápis jde přímo do
// `user_ride_points` (Velín má admin RLS politiku). Stav bodů drží rodič
// (TrasyJizdaModal), protože z nich kreslí i mapu a počítá dlaždice.

const kindLabel = (k) => k === 'start' ? 'Start' : k === 'end' ? 'Cíl' : 'Zastávka'

export default function TrasyJizdaBody({ points, setPoints, setErr, onChanged, inputStyle }) {
  const [confirmDel, setConfirmDel] = useState(null)

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

  return (
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
              <div className="flex items-center gap-2 mb-2 flex-wrap max-lg:[&>button]:min-h-[36px]">
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
                <span className="text-[10px] max-lg:text-xs" style={{ color: '#8aab99' }}>
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
                        className="cursor-pointer max-lg:!w-[30px] max-lg:!h-[30px] max-lg:!leading-[26px] max-lg:!top-[-9px] max-lg:!right-[-9px]"
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
  )
}
