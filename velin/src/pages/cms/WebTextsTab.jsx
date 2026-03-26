import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import WebTextSection from './WebTextSection'
import { WEB_PAGES } from './webTextsPages'

export default function WebTextsTab() {
  const [activePage, setActivePage] = useState(WEB_PAGES[0].id)
  const [values, setValues] = useState({})
  const [loading, setLoading] = useState(true)

  useEffect(() => { loadValues() }, [])

  async function loadValues() {
    setLoading(true)
    const { data } = await supabase.from('cms_variables').select('key, value').eq('group', 'web')
    const map = {}
    ;(data || []).forEach(r => { map[r.key] = r.value })
    setValues(map)
    setLoading(false)
  }

  function onSaved(key, val) {
    setValues(v => ({ ...v, [key]: val }))
  }

  const page = WEB_PAGES.find(p => p.id === activePage)

  // Počet vyplněných textů na stránku
  function filledCount(p) {
    let total = 0, filled = 0
    p.sections.forEach(s => {
      s.fields.forEach(f => { total++; if (values[f.key]) filled++ })
    })
    return { total, filled }
  }

  return (
    <div className="flex gap-4" style={{ minHeight: '70vh' }}>
      {/* Levý panel - stránky webu */}
      <div className="shrink-0" style={{ width: 220 }}>
        <div className="text-xs font-extrabold uppercase mb-2" style={{ color: '#6b8f7b', letterSpacing: 1 }}>
          Stránky webu
        </div>
        {WEB_PAGES.map(p => {
          const { total, filled } = filledCount(p)
          const active = p.id === activePage
          return (
            <button
              key={p.id}
              onClick={() => setActivePage(p.id)}
              className="w-full text-left mb-px cursor-pointer"
              style={{
                padding: '8px 12px', border: 'none', borderRadius: 10,
                background: active ? '#1a2e22' : 'transparent',
                color: active ? '#74FB71' : '#1a2e22',
                fontSize: 13, fontWeight: active ? 800 : 600,
              }}
            >
              <div className="flex items-center gap-2">
                <span>{p.icon}</span>
                <span className="flex-1 truncate">{p.label}</span>
              </div>
              <div className="text-xs mt-0.5" style={{ color: active ? 'rgba(255,255,255,.4)' : '#9ab3a5' }}>
                {filled}/{total} textů
              </div>
            </button>
          )
        })}
      </div>

      {/* Pravý panel - obsah stránky */}
      <div className="flex-1 min-w-0">
        {page && (
          <>
            <div className="mb-4">
              <div className="flex items-center gap-3">
                <span style={{ fontSize: 24 }}>{page.icon}</span>
                <div>
                  <h2 className="text-lg font-extrabold" style={{ color: '#0f1a14', margin: 0 }}>{page.label}</h2>
                  <div className="text-xs font-mono" style={{ color: '#6b8f7b' }}>motogo24.cz{page.url}</div>
                </div>
              </div>
              {page.description && (
                <p className="text-sm mt-2" style={{ color: '#4a6b5a' }}>{page.description}</p>
              )}
            </div>

            {loading ? (
              <div className="flex justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
              </div>
            ) : (
              page.sections.map(section => (
                <WebTextSection key={section.id} section={section} values={values} onSaved={onSaved} />
              ))
            )}
          </>
        )}
      </div>
    </div>
  )
}
