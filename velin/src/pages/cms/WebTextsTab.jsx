import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import WebTextSection from './WebTextSection'
import BlogSection from './BlogSection'
import { WEB_PAGES } from './webTextsPages'

// Celkový počet textů
const ALL_FIELDS = WEB_PAGES.flatMap(p => p.sections.flatMap(s => s.fields))
const TOTAL_FIELDS = ALL_FIELDS.length

// Veřejná URL webu — používá se pro tlačítko „Otevřít na webu" u každého textu.
// Lze přepsat přes Vite env `VITE_WEB_BASE_URL` (např. pro staging).
const WEB_BASE_URL = (import.meta?.env?.VITE_WEB_BASE_URL || 'https://motogo24.cz').replace(/\/$/, '')

// Sestaví URL na konkrétní stránku webu s admin tokenem a (volitelně) klíčem ke zvýraznění.
export function buildWebUrl(base, pageUrl, token, highlightKey) {
  const url = (base || '').replace(/\/$/, '') + (pageUrl || '/')
  const params = []
  if (token) params.push('cms_admin=' + encodeURIComponent(token))
  if (highlightKey) params.push('cms_highlight=' + encodeURIComponent(highlightKey))
  return params.length ? url + '?' + params.join('&') : url
}

export default function WebTextsTab() {
  const [activePage, setActivePage] = useState(WEB_PAGES[0].id)
  const [values, setValues] = useState({})
  const [loading, setLoading] = useState(true)
  const [seeding, setSeeding] = useState(false)
  const [adminToken, setAdminToken] = useState('')

  useEffect(() => { loadValues(); loadAdminToken() }, [])

  async function loadValues() {
    setLoading(true)
    const { data } = await supabase.from('cms_variables').select('key, value').eq('category', 'web')
    const map = {}
    ;(data || []).forEach(r => { map[r.key] = r.value })
    setValues(map)
    setLoading(false)
  }

  async function loadAdminToken() {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
    if (data?.value) {
      // value je jsonb — buď string přímo, nebo string-encoded
      const v = typeof data.value === 'string' ? data.value : (data.value ?? '')
      setAdminToken(String(v))
    }
  }

  function onSaved(key, val) {
    setValues(v => ({ ...v, [key]: val }))
  }

  // Naplnění výchozích textů do DB (jen ty co ještě neexistují)
  async function seedDefaults() {
    setSeeding(true)
    const missing = ALL_FIELDS.filter(f => !values[f.key] && f.default)
    // Batch insert max 50 najednou
    for (let i = 0; i < missing.length; i += 50) {
      const batch = missing.slice(i, i + 50).map(f => ({
        key: f.key, value: f.default, category: 'web'
      }))
      await supabase.from('cms_variables').insert(batch)
    }
    await loadValues()
    setSeeding(false)
  }

  const page = WEB_PAGES.find(p => p.id === activePage)
  const totalFilled = ALL_FIELDS.filter(f => values[f.key]).length

  function filledCount(p) {
    let total = 0, filled = 0
    p.sections.forEach(s => {
      s.fields.forEach(f => { total++; if (values[f.key]) filled++ })
    })
    return { total, filled }
  }

  return (
    <div>
      {/* Globální statistika */}
      <div className="flex items-center gap-4 mb-4 p-3 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="flex-1">
          <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>
            Texty webu: {totalFilled} / {TOTAL_FIELDS} uloženo v DB
          </span>
          <div className="mt-1 rounded-full overflow-hidden" style={{ height: 6, background: '#d4e8e0' }}>
            <div
              className="h-full rounded-full transition-all"
              style={{ width: `${(totalFilled / TOTAL_FIELDS) * 100}%`, background: totalFilled === TOTAL_FIELDS ? '#22c55e' : '#74FB71' }}
            />
          </div>
        </div>
        {totalFilled < TOTAL_FIELDS && (
          <button
            onClick={seedDefaults}
            disabled={seeding || loading}
            className="rounded-btn text-xs font-extrabold uppercase cursor-pointer shrink-0"
            style={{ padding: '8px 16px', background: '#1a2e22', color: '#74FB71', border: 'none' }}
          >
            {seeding ? 'Ukládám...' : 'Naplnit výchozí texty'}
          </button>
        )}
        {totalFilled === TOTAL_FIELDS && (
          <span className="text-xs font-bold" style={{ color: '#22c55e' }}>Vše uloženo</span>
        )}
      </div>

      <div className="flex gap-4" style={{ minHeight: '70vh' }}>
        {/* Levý panel - stránky webu */}
        <div className="shrink-0" style={{ width: 220 }}>
          <div className="text-xs font-extrabold uppercase mb-2" style={{ color: '#6b8f7b', letterSpacing: 1 }}>
            Stránky webu ({WEB_PAGES.length})
          </div>
          {WEB_PAGES.map(p => {
            const { total, filled } = filledCount(p)
            const active = p.id === activePage
            const allDone = filled === total && !loading
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
                  {allDone && <span style={{ color: '#22c55e', fontSize: 11 }}>&#10003;</span>}
                </div>
                <div className="text-xs mt-0.5" style={{ color: active ? 'rgba(255,255,255,.4)' : '#9ab3a5' }}>
                  {filled}/{total} textů
                </div>
              </button>
            )
          })}

          {/* Blog sekce - oddělená */}
          <div className="text-xs font-extrabold uppercase mt-4 mb-2" style={{ color: '#6b8f7b', letterSpacing: 1 }}>
            Dynamický obsah
          </div>
          <button
            onClick={() => setActivePage('blog')}
            className="w-full text-left mb-px cursor-pointer"
            style={{
              padding: '8px 12px', border: 'none', borderRadius: 10,
              background: activePage === 'blog' ? '#1a2e22' : 'transparent',
              color: activePage === 'blog' ? '#74FB71' : '#1a2e22',
              fontSize: 13, fontWeight: activePage === 'blog' ? 800 : 600,
            }}
          >
            <div className="flex items-center gap-2">
              <span>📰</span>
              <span className="flex-1">Blog & články</span>
            </div>
            <div className="text-xs mt-0.5" style={{ color: activePage === 'blog' ? 'rgba(255,255,255,.4)' : '#9ab3a5' }}>
              články z cms_pages
            </div>
          </button>
        </div>

        {/* Pravý panel - obsah stránky nebo blog */}
        <div className="flex-1 min-w-0">
          {activePage === 'blog' ? (
            <BlogSection />
          ) : page && (
            <>
              <div className="mb-4">
                <div className="flex items-center gap-3">
                  <span style={{ fontSize: 24 }}>{page.icon}</span>
                  <div className="flex-1">
                    <h2 className="text-lg font-extrabold" style={{ color: '#0f1a14', margin: 0 }}>{page.label}</h2>
                    <div className="text-xs font-mono" style={{ color: '#6b8f7b' }}>motogo24.cz{page.url}</div>
                  </div>
                  {page.url && (
                    <a
                      href={buildWebUrl(WEB_BASE_URL, page.url, adminToken, '')}
                      target="_blank" rel="noopener noreferrer"
                      title={adminToken ? 'Otevřít stránku v admin režimu (zvýrazní všechny texty)' : 'Token cms_admin_token v app_settings chybí — zvýraznění nebude fungovat'}
                      className="rounded-btn text-xs font-extrabold uppercase cursor-pointer shrink-0"
                      style={{
                        padding: '8px 14px',
                        background: adminToken ? '#1a2e22' : '#a8a8a8',
                        color: '#74FB71',
                        textDecoration: 'none',
                        border: 'none',
                      }}
                    >
                      🔗 Otevřít na webu
                    </a>
                  )}
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
                  <WebTextSection
                    key={section.id}
                    section={section}
                    values={values}
                    onSaved={onSaved}
                    pageUrl={page.url}
                    webBaseUrl={WEB_BASE_URL}
                    adminToken={adminToken}
                  />
                ))
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
