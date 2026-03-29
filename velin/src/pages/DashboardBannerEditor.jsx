import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'

export default function BannerEditor() {
  const [banner, setBanner] = useState({ enabled: false, text: '', bg: '#1a2e22', color: '#74FB71' })
  const [saving, setSaving] = useState(false)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    supabase.from('app_settings').select('value').eq('key', 'header_banner').maybeSingle()
      .then(({ data }) => {
        if (data?.value) {
          const v = typeof data.value === 'string' ? JSON.parse(data.value) : data.value
          setBanner(prev => ({ ...prev, ...v }))
        }
        setLoaded(true)
      })
      .catch(() => setLoaded(true))
  }, [])

  async function saveBanner() {
    setSaving(true)
    try {
      const { error } = await supabase.from('app_settings').upsert(
        { key: 'header_banner', value: banner },
        { onConflict: 'key' }
      )
      if (error) throw error
      alert('Banner uložen!')
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  if (!loaded) return null

  return (
    <Card>
      <div className="flex items-center justify-between mb-3">
        <div className="text-[13px] font-extrabold" style={{ color: '#0f1a14' }}>📢 Banner v aplikaci</div>
        <label className="flex items-center gap-2 cursor-pointer">
          <span className="text-xs font-bold" style={{ color: banner.enabled ? '#1a8a18' : '#8aab99' }}>
            {banner.enabled ? 'Zapnuto' : 'Vypnuto'}
          </span>
          <input
            type="checkbox"
            checked={banner.enabled}
            onChange={e => setBanner(prev => ({ ...prev, enabled: e.target.checked }))}
            className="w-4 h-4 accent-green-500"
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
              <input type="color" value={banner.bg} onChange={e => setBanner(prev => ({ ...prev, bg: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.bg}</span>
            </div>
          </div>
          <div className="flex-1">
            <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Barva textu</label>
            <div className="flex items-center gap-2">
              <input type="color" value={banner.color} onChange={e => setBanner(prev => ({ ...prev, color: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.color}</span>
            </div>
          </div>
        </div>
        {banner.text && (
          <div className="rounded-lg overflow-hidden mt-2" style={{ background: banner.bg, padding: '6px 12px' }}>
            <div className="text-xs font-bold truncate" style={{ color: banner.color }}>Náhled: {banner.text}</div>
          </div>
        )}
        <button
          onClick={saveBanner}
          disabled={saving}
          className="w-full py-2 rounded-lg text-sm font-bold text-white mt-1"
          style={{ background: saving ? '#8aab99' : '#1a8a18' }}
        >
          {saving ? 'Ukládání...' : 'Uložit banner'}
        </button>
      </div>
    </Card>
  )
}
