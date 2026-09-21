import { useState, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import { SmallBtn, Spinner, EmptyState } from './BranchHelpers'
import { catLabel, POI_COUNTRIES, poiPhoto } from '../lib/poiCategories'

// Hledání a slučování DUPLICITNÍCH míst v katalogu (points_of_interest).
//
// Proč to existuje: seed dávky z Wikidat kontrolovaly duplicity jen proti
// stavu katalogu PŘED svým vlastním insertem (a navíc přes `country = country`,
// což u řádku s country IS NULL nevyjde nikdy), takže v katalogu skončilo
// jedno fyzické místo víckrát pod různými názvy — „Křemešník" a „Pípalka"
// jsou 64 m od sebe a v appce to byly dva špendlíky přes sebe.
//
// Data i slučování dělá výhradně backend:
//   admin_poi_duplicate_groups(radius_m, country, limit) → dvojice do X metrů
//   admin_poi_merge(keep_id, drop_id)                     → sloučí a deaktivuje
// (supabase/migrations/20260920f_poi_dedupe.sql). Poražený se NIKDY nemaže —
// jen deaktivuje, aby se přes ON DELETE CASCADE nezahodila hodnocení zákazníků.

const RADII = [60, 100, 150, 250, 400]

export default function TrasyPoiDuplicates() {
  const [radius, setRadius] = useState(150)
  const [country, setCountry] = useState('CZ')
  // Výchozí je ZAPNUTO. Filtr „shodný název nebo kategorie" vypadá
  // rozumně, ale propadne skrz něj přesně ten typ dvojice, kvůli kterému
  // tahle záložka vznikla: „Rozhledna Doubravka" (lookout) × „Doubravská
  // Hora" (castle) 36 m od sebe. Změřeno nad katalogem CZ: do 60 m je
  // 608 dvojic a filtr jich vrátí 309 — tedy polovinu.
  const [showAll, setShowAll] = useState(true)
  const [pairs, setPairs] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [merging, setMerging] = useState(null)   // { keep, drop }
  const [done, setDone] = useState(() => new Set())

  const load = useCallback(async () => {
    setLoading(true); setError(null)
    try {
      const { data, error: err } = await supabase.rpc('admin_poi_duplicate_groups', {
        p_radius_m: radius, p_country: country === 'all' ? null : country, p_limit: 300,
        p_all: showAll,
      })
      if (err) throw err
      setPairs(Array.isArray(data) ? data : [])
      setDone(new Set())
    } catch (e) {
      setError(`Hledání duplicit selhalo: ${e.message}`)
      setPairs([])
    } finally { setLoading(false) }
  }, [radius, country, showAll])

  async function merge(keep, drop) {
    try {
      const { error: err } = await supabase.rpc('admin_poi_merge', { p_keep: keep.id, p_drop: drop.id })
      if (err) throw err
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'catalog_poi_merged',
          details: { keep: keep.name, dropped: drop.name, keep_id: keep.id, drop_id: drop.id },
        })
      } catch {}
      setDone(s => new Set(s).add(drop.id))
      setMerging(null)
      // Seznam je jen snímek — po sloučení se načte znovu, aby z něj zmizely
      // dvojice, kterých se právě skrytý bod týká (jinak by šlo „sloučit"
      // podruhé do bodu, který už není aktivní).
      load()
    } catch (e) { setError(`Sloučení selhalo: ${e.message}`); setMerging(null) }
  }

  const sel = { padding: '7px 10px', borderRadius: 8, border: '1px solid #d6ddd8', fontSize: 13, background: '#fff' }

  return (
    <Card className="mt-6">
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <h2 className="font-bold" style={{ fontSize: 16 }}>♊ Duplicitní místa</h2>
        <div className="flex-1" />
        <select style={sel} value={country} onChange={e => setCountry(e.target.value)}>
          <option value="CZ">CZ</option>
          <option value="SK">SK</option>
          {POI_COUNTRIES.filter(c => c !== 'CZ' && c !== 'SK').map(c => <option key={c} value={c}>{c}</option>)}
          <option value="all">Všechny země (pomalé)</option>
        </select>
        <select style={sel} value={radius} onChange={e => setRadius(Number(e.target.value))} title="Maximální vzdálenost dvojice">
          {RADII.map(r => <option key={r} value={r}>do {r} m</option>)}
        </select>
        <label className="flex items-center gap-2 text-sm" title="Bez tohohle se ukážou jen dvojice se shodným názvem nebo kategorií — a to je zhruba polovina">
          <input type="checkbox" checked={showAll} onChange={e => setShowAll(e.target.checked)} />
          i jiný název a kategorie
        </label>
        <SmallBtn color="#1a8a18" onClick={load}>Najít duplicity</SmallBtn>
      </div>

      <p className="text-xs mb-3" style={{ color: '#6b7280' }}>
        Hledají se AKTIVNÍ body do zvolené vzdálenosti. Se zaškrtnutým „i jiný název a kategorie"
        se ukáže VŠECHNO v daném okruhu — bez toho jen dvojice se shodným normalizovaným názvem
        (bez diakritiky a bez slov typu „hrad / rozhledna / vrch") nebo shodnou kategorií, což je
        zhruba polovina (a chybí mezi nimi případy jako „Rozhledna Doubravka" × „Doubravská Hora").
        Sloučením si vítěz vezme, co mu chybí (fotka, popis, okolí, galerie, překlady), převezme
        hodnocení a značky „navštíveno" a poražený se skryje — nemaže se.
      </p>

      {error && <div className="p-3 mb-3 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

      {loading ? <Spinner />
        : pairs === null ? <EmptyState text={'Zvol zemi a vzdálenost a klikni na „Najít duplicity".'} />
        : pairs.length === 0 ? <EmptyState text="Žádné duplicity v daném okruhu." />
        : (
          <div className="flex flex-col gap-2">
            <div className="text-sm font-semibold" style={{ color: '#374151' }}>
              Nalezeno {pairs.length} dvojic{pairs.length >= 300 ? ' (zobrazeno prvních 300)' : ''}
            </div>
            {pairs.map((p, i) => {
              const gone = done.has(p.a?.id) || done.has(p.b?.id)
              return (
                <div key={i} className="rounded-card p-3"
                  style={{ border: '1px solid #e5e7eb', background: gone ? '#f0fdf4' : '#fff', opacity: gone ? 0.6 : 1 }}>
                  <div className="text-xs font-bold mb-2" style={{ color: '#6b7280' }}>
                    {Math.round(Number(p.distance_m))} m od sebe {gone && '· sloučeno ✓'}
                  </div>
                  <div className="flex gap-3 flex-wrap">
                    {['a', 'b'].map(k => {
                      const me = p[k], other = p[k === 'a' ? 'b' : 'a']
                      if (!me) return null
                      return (
                        <div key={k} className="flex gap-2 items-start" style={{ flex: '1 1 280px', minWidth: 260 }}>
                          {poiPhoto(me)
                            ? <img src={poiPhoto(me)} alt="" loading="lazy" style={{ width: 62, height: 46, objectFit: 'cover', borderRadius: 6 }} />
                            : <div style={{ width: 62, height: 46, borderRadius: 6, background: '#f3f4f6', display: 'grid', placeItems: 'center', fontSize: 11, color: '#9ca3af' }}>bez foto</div>}
                          <div style={{ minWidth: 0 }}>
                            <div className="font-semibold text-sm">{me.name}</div>
                            <div className="text-xs" style={{ color: '#6b7280' }}>
                              {catLabel(me.category)} · {me.country || '—'} · {Number(me.lat).toFixed(4)}, {Number(me.lng).toFixed(4)}
                            </div>
                            <div className="text-xs" style={{ color: '#9ca3af' }}>{me.source || '—'}</div>
                            {!gone && (
                              <SmallBtn color="#1a8a18" disabled={loading}
                                onClick={() => setMerging({ keep: me, drop: other })}>
                                Nechat tenhle
                              </SmallBtn>
                            )}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )
            })}
          </div>
        )}

      {merging && (
        <ConfirmDialog
          open title="Sloučit místa?"
          message={`Zůstane „${merging.keep.name}". Bod „${merging.drop.name}" se skryje a jeho fotka, popis, překlady i hodnocení přejdou na ponechaný bod.`}
          onConfirm={() => merge(merging.keep, merging.drop)}
          onCancel={() => setMerging(null)}
        />
      )}
    </Card>
  )
}
