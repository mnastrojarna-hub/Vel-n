import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import WebTextSection from './WebTextSection'
import BlogSection from './BlogSection'
import FaqSection from './FaqSection'
import TranslateEverythingButton from '../../components/cms/TranslateEverythingButton'
import { WEB_PAGES } from './webTextsPages'

// Celkový počet textů
const ALL_FIELDS = WEB_PAGES.flatMap(p => p.sections.flatMap(s => s.fields))
const TOTAL_FIELDS = ALL_FIELDS.length

// Veřejná URL webu — používá se pro tlačítko „Otevřít na webu" u každého textu.
// Default je .cz (česká verze = master jazyk; ostatní jazyky se z CS překládají).
// Lze přepsat přes Vite env `VITE_WEB_BASE_URL`.
const WEB_BASE_URL = (import.meta?.env?.VITE_WEB_BASE_URL || 'https://www.motogo24.cz').replace(/\/$/, '')

// Sestaví URL na konkrétní stránku webu s admin tokenem a (volitelně) klíčem ke zvýraznění.
// `extra` je objekt s dalšími query parametry (např. `{ preview: 'pending' }`).
export function buildWebUrl(base, pageUrl, token, highlightKey, extra) {
  const url = (base || '').replace(/\/$/, '') + (pageUrl || '/')
  const params = []
  if (token) params.push('cms_admin=' + encodeURIComponent(token))
  if (highlightKey) params.push('cms_highlight=' + encodeURIComponent(highlightKey))
  if (extra && typeof extra === 'object') {
    Object.keys(extra).forEach(k => {
      if (extra[k] != null && extra[k] !== '') {
        params.push(encodeURIComponent(k) + '=' + encodeURIComponent(extra[k]))
      }
    })
  }
  return params.length ? url + '?' + params.join('&') : url
}

export default function WebTextsTab({ initialPageId, initialFieldKey, initialSectionId, jumpTimestamp }) {
  // Pokud SEO Health tab predal pageId pres 'Opravit' tlacitko, otevreme tu stranku
  const startPage = initialPageId && WEB_PAGES.some(p => p.id === initialPageId)
    ? initialPageId : WEB_PAGES[0].id
  const [activePage, setActivePage] = useState(startPage)
  // Highlight key pro pulsujici zlute zvyrazneni cilove field
  const [highlightKey, setHighlightKey] = useState(initialFieldKey || null)

  // Reaguj na jump z SEO Health (zmena jumpTimestamp = re-trigger i kdyz user
  // klikne 2x stejne pole). Auto-scroll + 4s pulsing highlight.
  useEffect(() => {
    if (initialPageId && WEB_PAGES.some(p => p.id === initialPageId)) {
      setActivePage(initialPageId)
    }
    if (initialFieldKey) {
      setHighlightKey(initialFieldKey)
      // Scroll po renderu (200ms timeout aby DOM stihl mount sekci)
      const tm = setTimeout(() => {
        const target = document.querySelector(`[data-cms-field="${initialFieldKey}"]`)
        if (target) {
          target.scrollIntoView({ behavior: 'smooth', block: 'center' })
          target.classList.add('cms-field-highlight')
          setTimeout(() => target.classList.remove('cms-field-highlight'), 4000)
        }
      }, 300)
      return () => clearTimeout(tm)
    }
  }, [initialPageId, initialFieldKey, jumpTimestamp])
  const [values, setValues] = useState({})
  const [loading, setLoading] = useState(true)
  const [seeding, setSeeding] = useState(false)
  const [adminToken, setAdminToken] = useState('')

  useEffect(() => { loadValues(); loadAdminToken() }, [])

  async function loadValues() {
    setLoading(true)
    // Texty webu načítáme podle PREFIXU klíče `web.` — stejně jako web
    // (motogo-web-php/supabase.php → fetchWebTexts čte `key=like.web.<page>.*`),
    // NE podle `category`. Legacy řádky vzniklé před zavedením kategorie 'web'
    // (CHECK constraint rozšířen 2026-04-29) mají category='general'/'content';
    // web je vidí (čte podle prefixu), ale Velín je s `eq('category','web')`
    // přeskakoval → uložený text se na webu projevil, ale v editoru zůstával
    // výchozí. Stránkujeme po 1000 — jediný select bez limitu by se mohl uťat
    // na řádkovém stropu PostgREST a část textů by chyběla.
    const map = {}
    const PAGE = 1000
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await supabase
        .from('cms_variables')
        .select('key, value')
        .like('key', 'web.%')
        .order('key')
        .range(from, from + PAGE - 1)
      if (error || !data) break
      data.forEach(r => { map[r.key] = r.value })
      if (data.length < PAGE) break
    }
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
  // SEO note: missing = pole co MA neprazdny default a NENI ulozene v DB.
  // Tyto si zaslouzi byt seedovany (klik na 'Naplnit vychozi texty').
  const totalMissing = ALL_FIELDS.filter(f => !values[f.key] && f.default).length
  // Optional pole (default: '' nebo null) PHP-fallback obslouzi — neni co seedovat.
  const totalOptional = ALL_FIELDS.filter(f => !values[f.key] && (f.default === '' || f.default == null)).length

  // SEO note: pole s `default: ''` (prazdny) jsou OPTIONAL — PHP ma vlastni
  // fallback v data/*.php data souborech. Admin je nemusi vyplnovat, pokud
  // mu PHP defaulty staci. Pocitame proto 3 kategorie:
  //   - filled = realne ulozeno v cms_variables (zelene v UI)
  //   - optional = empty default, PHP fallback se pouzije (sede ale OK)
  //   - missing = pole s neprazdnym defaultem, ale neulozene v DB (sede a chce ulozit)
  function filledCount(p) {
    let total = 0, filled = 0, optional = 0, missing = 0
    p.sections.forEach(s => {
      s.fields.forEach(f => {
        total++
        const hasValue = !!values[f.key]
        const isOptional = !hasValue && (f.default === '' || f.default == null)
        if (hasValue) filled++
        else if (isOptional) optional++
        else missing++
      })
    })
    return { total, filled, optional, missing }
  }

  return (
    <div>
      {/* Globální statistika — rozliseni filled/optional/missing */}
      <div className="flex items-center gap-4 mb-4 p-3 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="flex-1">
          <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>
            Texty webu:
            <span style={{ color: '#16a34a' }}> {totalFilled} uloženo</span>
            {totalMissing > 0 && <span style={{ color: '#dc2626' }}> · {totalMissing} k doplnění</span>}
            {totalOptional > 0 && <span style={{ color: '#6b7a72' }}> · {totalOptional} volitelných</span>}
            {' '}/ {TOTAL_FIELDS} celkem
          </div>
          <div className="mt-1 rounded-full overflow-hidden flex" style={{ height: 6, background: '#d4e8e0' }}>
            <div className="h-full transition-all" style={{
              width: `${(totalFilled / TOTAL_FIELDS) * 100}%`, background: '#22c55e'
            }} />
            <div className="h-full transition-all" style={{
              width: `${(totalMissing / TOTAL_FIELDS) * 100}%`, background: '#dc2626'
            }} />
            <div className="h-full transition-all" style={{
              width: `${(totalOptional / TOTAL_FIELDS) * 100}%`, background: '#9ca3af'
            }} />
          </div>
          <div style={{ fontSize: 11, color: '#6b7a72', marginTop: 4 }}>
            <span style={{ color: '#16a34a' }}>● Uloženo</span> = ručně přepsané z Velínu
            <span style={{ marginLeft: 12, color: '#dc2626' }}>● K doplnění</span> = má výchozí text, ale ještě není v DB (klikni "Naplnit")
            <span style={{ marginLeft: 12, color: '#6b7a72' }}>● Volitelné</span> = PHP fallback obsluhuje (není potřeba vyplňovat)
          </div>
        </div>
        {totalMissing > 0 && (
          <button
            onClick={seedDefaults}
            disabled={seeding || loading}
            className="rounded-btn text-xs font-extrabold uppercase cursor-pointer shrink-0"
            style={{ padding: '8px 16px', background: '#1a2e22', color: '#74FB71', border: 'none' }}
          >
            {seeding ? 'Ukládám...' : `Naplnit ${totalMissing} výchozích`}
          </button>
        )}
        {totalMissing === 0 && (
          <span className="text-xs font-bold" style={{ color: '#22c55e' }}>✓ Vše uloženo</span>
        )}
      </div>

      {/* Jediné tlačítko pro celkovou synchronizaci překladů (master + cms_variables + FAQ + blog) */}
      <div className="mb-4 p-4 rounded-card" style={{ background: '#fff7ed', border: '2px solid #fed7aa' }}>
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="text-xs flex-1" style={{ color: '#9a3412', minWidth: 320 }}>
            <strong>🌍 Multilingvní překlad — vše naráz</strong><br />
            Postupně přeloží do EN/DE/ES/FR/NL/PL: (1) pages master z CS šablon,
            (2) cms_variables (web.*), (3) FAQ položky, (4) blog články.
            Vše se uloží do DB, weby na všech doménách čtou živě — <strong>bez FTP uploadu</strong>.
          </div>
          <TranslateEverythingButton />
        </div>
      </div>

      <div className="flex gap-4" style={{ minHeight: '70vh' }}>
        {/* Levý panel - stránky webu */}
        <div className="shrink-0" style={{ width: 220 }}>
          <div className="text-xs font-extrabold uppercase mb-2" style={{ color: '#6b8f7b', letterSpacing: 1 }}>
            Stránky webu ({WEB_PAGES.length})
          </div>
          {WEB_PAGES.map(p => {
            const { total, filled, optional, missing } = filledCount(p)
            const active = p.id === activePage
            // SEO: 'allDone' = vsechna pole s neprazdnym defaultem ulozena
            // (volitelne pole s default:'' se nepocitaji — PHP fallback je obslouzi).
            const allDone = missing === 0 && !loading
            // Procento dokoncenosti = filled / (filled+missing). Volitelne pole vyloucena.
            const required = filled + missing
            const pct = required > 0 ? Math.round((filled / required) * 100) : 100
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
                  {!allDone && missing > 0 && (
                    <span style={{
                      background: '#dc2626', color: '#fff', fontSize: 10,
                      padding: '1px 5px', borderRadius: 8, fontWeight: 700
                    }}>{missing}</span>
                  )}
                </div>
                <div className="text-xs mt-0.5" style={{ color: active ? 'rgba(255,255,255,.4)' : '#9ab3a5' }}>
                  {filled}/{required} povinných
                  {optional > 0 && <span style={{ opacity: 0.6 }}> · {optional} volit.</span>}
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

          <button
            onClick={() => setActivePage('faq')}
            className="w-full text-left mb-px cursor-pointer"
            style={{
              padding: '8px 12px', border: 'none', borderRadius: 10,
              background: activePage === 'faq' ? '#1a2e22' : 'transparent',
              color: activePage === 'faq' ? '#74FB71' : '#1a2e22',
              fontSize: 13, fontWeight: activePage === 'faq' ? 800 : 600,
            }}
          >
            <div className="flex items-center gap-2">
              <span>📋</span>
              <span className="flex-1">Časté dotazy</span>
            </div>
            <div className="text-xs mt-0.5" style={{ color: activePage === 'faq' ? 'rgba(255,255,255,.4)' : '#9ab3a5' }}>
              otázky z faq_items
            </div>
          </button>
        </div>

        {/* Pravý panel - obsah stránky nebo blog/faq */}
        <div className="flex-1 min-w-0">
          {activePage === 'blog' ? (
            <BlogSection />
          ) : activePage === 'faq' ? (
            <FaqSection />
          ) : page && (
            <>
              <div className="mb-4">
                <div className="flex items-center gap-3">
                  <span style={{ fontSize: 24 }}>{page.icon}</span>
                  <div className="flex-1">
                    <h2 className="text-lg font-extrabold" style={{ color: '#0f1a14', margin: 0 }}>{page.label}</h2>
                    <div className="text-xs font-mono" style={{ color: '#6b8f7b' }}>{WEB_BASE_URL.replace(/^https?:\/\//, '')}{page.url}</div>
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
                {page.previewVariants && page.url && (
                  <div className="flex items-center gap-2 mt-3 flex-wrap">
                    <span className="text-xs font-extrabold uppercase" style={{ color: '#6b8f7b', letterSpacing: 1 }}>
                      Náhled varianty:
                    </span>
                    {page.previewVariants.map(v => (
                      <a
                        key={v.id}
                        href={buildWebUrl(WEB_BASE_URL, page.url, adminToken, '', { preview: v.id })}
                        target="_blank" rel="noopener noreferrer"
                        title={adminToken ? `Otevřít náhled: ${v.label}` : 'Chybí cms_admin_token v app_settings'}
                        className="rounded-btn text-xs font-extrabold cursor-pointer"
                        style={{
                          padding: '4px 10px',
                          background: adminToken ? '#f1faf7' : '#f5f5f5',
                          color: adminToken ? '#1a2e22' : '#9ab3a5',
                          border: '1px solid #d4e8e0',
                          textDecoration: 'none',
                          pointerEvents: adminToken ? 'auto' : 'none',
                        }}
                      >
                        {v.icon} {v.label}
                      </a>
                    ))}
                  </div>
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
                    forceOpen={initialSectionId === section.id || section.fields.some(f => f.key === highlightKey)}
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
