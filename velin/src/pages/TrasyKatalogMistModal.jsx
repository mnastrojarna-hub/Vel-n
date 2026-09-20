import { useState } from 'react'
import { supabase } from '../lib/supabase'
import ImageUploader from '../components/ui/ImageUploader'
import { SmallBtn } from './BranchHelpers'
import { POI_CATS, POI_COUNTRIES } from '../lib/poiCategories'
import { autoTranslateRow } from '../lib/autoTranslate'

// Editace (a NOVĚ i zakládání) katalogového místa.
//
// Oproti původnímu modalu umí navíc:
//   * GPS — bez toho nešlo opravit špatně umístěný bod z Wikidat ani posunout
//     vítěze slučování na správný vrchol,
//   * galerii přes ImageUploader (bucket `media`, složka poi/<id>) místo
//     holého textového pole s URL,
//   * založit nové místo (RLS to povolovala od začátku, chybělo jen UI —
//     studánky a kopce tak šlo doplnit jedině SQL migrací),
//   * po uložení spustit automatický překlad (points_of_interest edge funkce
//     translate-content povoluje, jen to Velín nikdy nevolal).

export default function PoiEditModal({ poi, onClose, onSaved, onError }) {
  const isNew = !!poi._new
  const [f, setF] = useState({
    ...poi,
    images: Array.isArray(poi.images) ? poi.images : [],
    lat: poi.lat ?? '', lng: poi.lng ?? '',
  })
  const [saving, setSaving] = useState(false)
  const set = (patch) => setF(s => ({ ...s, ...patch }))
  const sel = { padding: '7px 10px', borderRadius: 8, border: '1px solid #d6ddd8', fontSize: 13, background: '#fff' }

  async function save() {
    const lat = Number(String(f.lat).replace(',', '.'))
    const lng = Number(String(f.lng).replace(',', '.'))
    if (!f.name?.trim()) { onError?.('Název je povinný.'); return }
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      onError?.('Zadej platné souřadnice (např. 49.4039 a 15.3278).'); return
    }
    setSaving(true)
    try {
      const payload = {
        name: f.name.trim(),
        description: f.description || null,
        surroundings: f.surroundings || null,
        category: f.category,
        country: f.country || null,
        lat, lng,
        images: f.images,
        // Titulní fotka = první z galerie, jinak ručně zadaná URL. Dřív si
        // stávající image_url drželo přednost, takže nahrání nové galerie
        // titulní fotku nezměnilo a odznak „HLAVNÍ" lhal.
        image_url: (f.images && f.images[0]) || f.image_url || null,
        is_active: !!f.is_active,
        updated_at: new Date().toISOString(),
      }
      let saved
      if (isNew) {
        const { data, error: err } = await supabase.from('points_of_interest')
          .insert({ ...payload, source: 'velin-manual' }).select('id, name, description, surroundings, translations').single()
        if (err) throw err
        saved = data
      } else {
        const { data, error: err } = await supabase.from('points_of_interest')
          .update(payload).eq('id', f.id).select('id, name, description, surroundings, translations').single()
        if (err) throw err
        saved = data
      }
      // Překlady jsou best-effort — když edge funkce nedojede, místo je uložené.
      try {
        await autoTranslateRow({ table: 'points_of_interest', id: saved.id, row: saved })
      } catch {}
      onSaved?.(isNew ? 'catalog_poi_created' : 'catalog_poi_updated', payload.name)
    } catch (e) {
      onError?.(`Uložení selhalo: ${e.message}`)
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.45)' }} onClick={onClose}>
      <div className="bg-white rounded-card p-5" style={{ width: 560, maxWidth: '92vw', maxHeight: '88vh', overflowY: 'auto' }} onClick={e => e.stopPropagation()}>
        <h3 className="font-bold mb-3" style={{ fontSize: 15 }}>{isNew ? 'Nové místo v katalogu' : 'Upravit místo'}</h3>

        <label className="block text-xs font-bold mb-1">Název</label>
        <input style={{ ...sel, width: '100%', marginBottom: 10 }} value={f.name || ''}
          onChange={e => set({ name: e.target.value })} />

        <label className="block text-xs font-bold mb-1">Popis (česky)</label>
        <textarea style={{ ...sel, width: '100%', minHeight: 90, marginBottom: 10 }} value={f.description || ''}
          onChange={e => set({ description: e.target.value })} />

        <label className="block text-xs font-bold mb-1">Popis okolí (česky)</label>
        <textarea style={{ ...sel, width: '100%', minHeight: 70, marginBottom: 10 }} value={f.surroundings || ''}
          placeholder="Co je v okolí — tipy na zastávky, občerstvení, výhledy…"
          onChange={e => set({ surroundings: e.target.value })} />

        <div className="flex gap-3 mb-3">
          <div style={{ flex: 1 }}>
            <label className="block text-xs font-bold mb-1">Kategorie</label>
            <select style={{ ...sel, width: '100%' }} value={f.category}
              onChange={e => set({ category: e.target.value })}>
              {Object.entries(POI_CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
          <div style={{ width: 110 }}>
            <label className="block text-xs font-bold mb-1">Země</label>
            <select style={{ ...sel, width: '100%' }} value={f.country || ''}
              onChange={e => set({ country: e.target.value })}>
              <option value="">—</option>
              {POI_COUNTRIES.map(c => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
        </div>

        <div className="flex gap-3 mb-3">
          <div style={{ flex: 1 }}>
            <label className="block text-xs font-bold mb-1">Šířka (lat)</label>
            <input style={{ ...sel, width: '100%' }} value={f.lat} inputMode="decimal" placeholder="49.4039"
              onChange={e => set({ lat: e.target.value })} />
          </div>
          <div style={{ flex: 1 }}>
            <label className="block text-xs font-bold mb-1">Délka (lng)</label>
            <input style={{ ...sel, width: '100%' }} value={f.lng} inputMode="decimal" placeholder="15.3278"
              onChange={e => set({ lng: e.target.value })} />
          </div>
        </div>
        <p className="text-xs mb-3" style={{ color: '#6b7280' }}>
          Souřadnice se dají zkopírovat z Mapy.com / Google Maps (formát 49.4039, 15.3278).
        </p>

        <label className="block text-xs font-bold mb-1">Fotky (první = titulní)</label>
        <div className="mb-3">
          <ImageUploader
            value={f.images}
            onChange={(urls) => set({ images: urls })}
            folder={`poi/${f.id || 'new'}`}
            helperText="Nahrané fotky jdou do bucketu media. První fotka je titulní a zobrazí se v seznamu i na kartě místa."
          />
        </div>

        <label className="block text-xs font-bold mb-1">URL titulní fotky (když se nenahrává)</label>
        <input style={{ ...sel, width: '100%', marginBottom: 10 }} value={f.image_url || ''}
          onChange={e => set({ image_url: e.target.value })} />

        <label className="flex items-center gap-2 text-sm mb-4">
          <input type="checkbox" checked={!!f.is_active}
            onChange={e => set({ is_active: e.target.checked })} />
          Aktivní (zobrazuje se v appce)
        </label>

        <div className="flex justify-end gap-2">
          <SmallBtn color="#6b7280" onClick={onClose}>Zrušit</SmallBtn>
          <SmallBtn color="#1a8a18" onClick={saving ? undefined : save}>{saving ? 'Ukládám…' : 'Uložit'}</SmallBtn>
        </div>
      </div>
    </div>
  )
}
