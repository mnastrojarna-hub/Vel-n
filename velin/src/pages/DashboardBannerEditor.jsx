import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { purgeWebCache } from '../lib/webCache'
import Card from '../components/ui/Card'
import {
  BANNER_LANGS, sha1Hex, parseBannerValue, freshTranslations, bannerLangStatus, translateBannerText,
} from './bannerI18n'

// Banner se zobrazuje v appce (banner_provider.dart) i nahoře na webu (layout-banner.php).
// Po uložení CZ textu se automaticky přeloží do 7 jazyků (bannerI18n.js); selhání překladu
// uložení neblokuje — web a appka v nepřeložených jazycích ukážou češtinu.

const STATUS = {
  fresh: { label: 'aktuální', color: '#1a8a18' },
  stale: { label: 'zastaralý → čeština', color: '#b45309' },
  missing: { label: 'chybí → čeština', color: '#8aab99' },
  checking: { label: '…', color: '#8aab99' },
}

export default function BannerEditor() {
  const [banner, setBanner] = useState({ enabled: false, text: '', bg: '#1a2e22', color: '#74FB71' })
  const [saving, setSaving] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const [hash, setHash] = useState(undefined) // sha1 aktuálního CZ textu (undefined = počítá se)
  const [tr, setTr] = useState(null) // { ok: bool|null, text } — stav překladu (nevyskakovací)

  useEffect(() => {
    supabase.from('app_settings').select('value').eq('key', 'header_banner').maybeSingle()
      .then(({ data }) => {
        const v = parseBannerValue(data?.value)
        if (v) setBanner(prev => ({ ...prev, ...v }))
        setLoaded(true)
      })
      .catch(() => setLoaded(true))
  }, [])

  useEffect(() => {
    let alive = true
    setHash(undefined)
    sha1Hex(banner.text || '').then(h => { if (alive) setHash(h) })
    return () => { alive = false }
  }, [banner.text])

  async function translateAndStore(text, h, fresh, langs) {
    setTr({ ok: null, text: `Překládám do: ${langs.join(', ')}…` })
    const r = await translateBannerText(text, langs)
    let saveErr = ''
    if (Object.keys(r.translations).length) {
      try {
        // Zapiš jen pokud se text banneru mezitím nezměnil (jiné uložení) — klíče
        // enabled/text/bg/color bere z aktuální DB hodnoty beze změny.
        const { data } = await supabase.from('app_settings').select('value').eq('key', 'header_banner').maybeSingle()
        const cur = parseBannerValue(data?.value)
        if (!cur || cur.text !== text) {
          saveErr = 'text banneru se mezitím změnil'
        } else {
          const translations = { ...fresh, ...r.translations }
          const { error } = await supabase.from('app_settings').upsert(
            { key: 'header_banner', value: { ...cur, translations, translations_src: h } },
            { onConflict: 'key' }
          )
          if (error) throw error
          purgeWebCache()
          setBanner(prev => (prev.text === text ? { ...prev, translations, translations_src: h } : prev))
        }
      } catch (e) {
        saveErr = e?.message || String(e)
      }
    }
    if (saveErr) {
      setTr({ ok: false, text: `Překlad se nepodařilo uložit (${saveErr}). Web a appka zatím v cizích jazycích ukazují český text.` })
    } else if (r.failed.length) {
      setTr({ ok: false, text: `Nepřeloženo: ${r.failed.join(', ')}${r.error ? ` (${r.error})` : ''}. V těchto jazycích web a appka zatím ukazují český text — pro dokončení klikni znovu „Uložit banner“.` })
    } else {
      setTr({ ok: true, text: `Přeloženo do: ${langs.join(', ')}.` })
    }
  }

  async function saveBanner() {
    setSaving(true)
    const text = banner.text || ''
    const h = await sha1Hex(text)
    const fresh = freshTranslations(banner, h)
    // Česky se uloží hned (překlad uložení nikdy neblokuje); platné zůstanou jen čerstvé překlady.
    const value = { ...banner, translations: fresh, translations_src: h || null }
    try {
      const { error } = await supabase.from('app_settings').upsert(
        { key: 'header_banner', value },
        { onConflict: 'key' }
      )
      if (error) throw error
      setBanner(value)
      purgeWebCache()
    } catch (e) {
      setSaving(false)
      alert('Chyba: ' + e.message)
      return
    }
    setSaving(false)
    alert('Banner uložen!')
    const missing = text.trim() ? BANNER_LANGS.filter(l => !fresh[l]) : []
    if (missing.length && !h) {
      setTr({ ok: false, text: 'Prohlížeč neumí spočítat otisk textu (SHA-1) — banner uložen jen česky.' })
    } else if (missing.length) {
      translateAndStore(text, h, fresh, missing)
    }
  }

  if (!loaded) return null
  const translating = tr?.ok === null

  return (
    <Card>
      <div className="flex items-center justify-between mb-3">
        <div className="text-[13px] font-extrabold" style={{ color: '#0f1a14' }}>📢 Banner v aplikaci a na webu</div>
        {/* mobil/tablet (< lg): větší přepínač a dotyková plocha */}
        <label className="flex items-center gap-2 cursor-pointer max-lg:min-h-[40px] max-lg:pl-2">
          <span className="text-xs font-bold" style={{ color: banner.enabled ? '#1a8a18' : '#8aab99' }}>
            {banner.enabled ? 'Zapnuto' : 'Vypnuto'}
          </span>
          <input
            type="checkbox"
            checked={banner.enabled}
            onChange={e => setBanner(prev => ({ ...prev, enabled: e.target.checked }))}
            className="w-4 h-4 accent-green-500 max-lg:w-6 max-lg:h-6"
          />
        </label>
      </div>
      <div className="space-y-2">
        <div>
          <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Text banneru</label>
          <input
            type="text"
            value={banner.text}
            onChange={e => setBanner(prev => ({ ...prev, text: e.target.value }))}
            placeholder="Letní akce -20% na všechny motorky!"
            className="w-full px-3 py-2 rounded-lg border text-sm font-medium"
            style={{ borderColor: '#d4e8e0', color: '#0f1a14' }}
          />
        </div>
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Barva pozadí</label>
            <div className="flex items-center gap-2">
              <input type="color" value={banner.bg} onChange={e => setBanner(prev => ({ ...prev, bg: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0 max-lg:w-10 max-lg:h-10" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.bg}</span>
            </div>
          </div>
          <div className="flex-1">
            <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Barva textu</label>
            <div className="flex items-center gap-2">
              <input type="color" value={banner.color} onChange={e => setBanner(prev => ({ ...prev, color: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0 max-lg:w-10 max-lg:h-10" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.color}</span>
            </div>
          </div>
        </div>
        {banner.text && (
          <div className="rounded-lg overflow-hidden mt-2" style={{ background: banner.bg, padding: '6px 12px' }}>
            <div className="text-xs font-bold truncate" style={{ color: banner.color }}>Náhled: {banner.text}</div>
          </div>
        )}
        {banner.text && (
          <details className="text-xs">
            <summary className="cursor-pointer font-bold max-lg:min-h-[40px] max-lg:flex max-lg:items-center" style={{ color: '#1a2e22' }}>
              Překlady ({BANNER_LANGS.filter(l => bannerLangStatus(banner, hash, l) === 'fresh').length}/{BANNER_LANGS.length} aktuálních)
            </summary>
            <div className="mt-1 space-y-0.5">
              {BANNER_LANGS.map(l => {
                const st = STATUS[bannerLangStatus(banner, hash, l)]
                const val = banner.translations?.[l] || ''
                return (
                  <div key={l} className="flex items-center gap-2 min-w-0">
                    <span className="font-mono font-bold uppercase w-6 shrink-0" style={{ color: '#1a2e22' }}>{l}</span>
                    <span className="shrink-0 font-bold" style={{ color: st.color }}>{st.label}</span>
                    <span className="truncate" title={val} style={{ color: '#4a6b5a' }}>{val}</span>
                  </div>
                )
              })}
            </div>
          </details>
        )}
        <button
          onClick={saveBanner}
          disabled={saving || translating}
          className="w-full py-2 rounded-lg text-sm font-bold text-white mt-1 max-lg:py-2.5"
          style={{ background: saving || translating ? '#8aab99' : '#1a8a18' }}
        >
          {saving ? 'Ukládání...' : translating ? 'Překládám…' : 'Uložit banner'}
        </button>
        {tr && (
          <div role="status" className="text-xs font-bold" style={{ color: tr.ok === false ? '#b45309' : tr.ok ? '#1a8a18' : '#4a6b5a' }}>
            {tr.text}
          </div>
        )}
      </div>
    </Card>
  )
}
