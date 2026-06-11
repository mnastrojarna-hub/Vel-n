import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { WEB_PAGES } from './webTextsPages'

const ALL_FIELDS = WEB_PAGES.flatMap(p => (p.sections || []).flatMap(s => s.fields || []))

// Vsechny verejne URL webu pro SEO scan — ze static seznamu (ne z DB).
const SCAN_PATHS = [
  '/', '/pujcovna-motorek', '/katalog', '/katalog/cestovni', '/katalog/naked',
  '/katalog/supermoto', '/katalog/detske', '/jak-pujcit', '/jak-pujcit/postup',
  '/jak-pujcit/prevzeti', '/jak-pujcit/pristaveni', '/jak-pujcit/vraceni-pujcovna',
  '/jak-pujcit/vraceni-jinde', '/jak-pujcit/co-v-cene', '/jak-pujcit/dokumenty',
  '/jak-pujcit/faq', '/poukazy', '/koupit-darkovy-poukaz', '/eshop', '/blog',
  '/kontakt', '/mapa-stranek', '/partneri',
  '/dokumenty/obchodni-podminky', '/dokumenty/zasady-ochrany-osobnich-udaju',
  '/dokumenty/smlouva-o-pronajmu',
]

// Mapuje URL cestu -> WEB_PAGES definice (kvuli auto-jumpu na CMS pole pri opravě)
const PATH_TO_PAGE = {}
WEB_PAGES.forEach(p => { if (p.url) PATH_TO_PAGE[p.url] = p })

// SEO thresholdy (stejne co Seobility)
const TITLE_MIN = 30, TITLE_MAX = 65
const DESC_MIN = 80, DESC_MAX = 160
const H1_MIN = 3, H1_MAX = 120
const WORD_MIN_WARN = 500, WORD_MIN_CRIT = 200
const STRONG_MAX = 10

// Funkcni/transakcni stranky — content checky se neaplikuji
const FUNCTIONAL = new Set(['/kosik', '/objednavka', '/potvrzeni', '/upravit-rezervaci', '/rezervace'])

// Najde CMS pole (z webTexts def) ktere odpovida danemu typu na dane strance.
// Vrati { fieldKey, sectionId, pageId } nebo null pokud pro tento web nema CMS pole.
function findCmsTarget(path, type) {
  const page = PATH_TO_PAGE[path]
  if (!page) return null
  let predicate
  if (type === 'title') predicate = (f) => /\.seo\.title$|\.seoTitle$/i.test(f.key) || /title.*titulek.*záložky|seo.*title/i.test((f.label || '').toLowerCase())
  else if (type === 'description') predicate = (f) => /\.seo\.description$|\.seoDescription$/i.test(f.key) || /meta description|popisek.*google/i.test((f.label || '').toLowerCase())
  else if (type === 'h1') predicate = (f) => /\.h1$|\.h1\.text$/i.test(f.key) || /^h1\b|h1.*nadpis/i.test((f.label || '').toLowerCase())
  else if (type === 'body') predicate = (f) => /\.intro$|\.intro_p1$|\.intro\.body$|\.intro\.text$/i.test(f.key) || /úvodní.*text|intro|úvod/i.test((f.label || '').toLowerCase())
  else return null
  for (const section of (page.sections || [])) {
    for (const field of (section.fields || [])) {
      if (predicate(field, section)) return { fieldKey: field.key, sectionId: section.id, pageId: page.id }
    }
  }
  // Pro body — fallback na prvni textarea field
  if (type === 'body') {
    for (const section of (page.sections || [])) {
      for (const field of (section.fields || [])) {
        if (field.type === 'textarea') return { fieldKey: field.key, sectionId: section.id, pageId: page.id }
      }
    }
  }
  return null
}

// Z reálných metrik (z edge fn) vyrobi seznam issues s lidskymi hlaskami.
function buildIssues(path, m) {
  const issues = []
  if (m.error) {
    issues.push({ severity: 'critical', title: `Stránka nedostupná (${m.error})`, message: 'Crawler nemohl stránku načíst. Zkontroluj že URL funguje v prohlížeči.', target: null })
    return issues
  }
  // Obrana proti neúplné/starší metrice z edge fn (chybějící h1/h1Count by jinak
  // shodily render reportu na `m.h1.map`/`m.h1[0]`). Normalizujeme na bezpečné typy.
  const h1Arr = Array.isArray(m.h1) ? m.h1 : []
  const h1Count = typeof m.h1Count === 'number' ? m.h1Count : h1Arr.length
  const isFunc = FUNCTIONAL.has(path)

  // REDIRECT — edge fn vrací `redirected` + finalUrl; bez upozornění by skenovaná
  // cesta (která 301 přesměrovává jinam) vypadala OK, ale měří se cizí stránka.
  if (m.redirected && m.finalUrl) {
    issues.push({ severity: 'important', title: 'Stránka přesměrovává jinam (redirect)', message: `Tato URL se přesměrovává na ${m.finalUrl}. Měřené hodnoty patří cílové stránce, ne této. Pokud má cesta existovat samostatně, oprav přesměrování; jinak ji odeber z odkazů/sitemap.`, target: null })
  }

  // TITLE
  if (!m.title) {
    issues.push({ severity: 'critical', title: 'Chybí Titulek stránky (<title>)', message: 'Titulek se zobrazí v záložce prohlížeče a jako modrý nadpis ve výsledcích Googlu. Bez něj si Google vymyslí náhradu.', example: 'Půjčovna motorek Pelhřimov | MotoGo24', target: findCmsTarget(path, 'title') })
  } else if (m.titleLen < TITLE_MIN) {
    issues.push({ severity: 'tip', title: `Titulek je krátký (${m.titleLen} znaků, ideál ${TITLE_MIN}-${TITLE_MAX})`, message: `Aktuální titulek: „${m.title}". Doplň lokalitu nebo výhodu pro lepší využití prostoru v Googlu.`, example: `„${m.title} | MotoGo24 Pelhřimov"`, target: findCmsTarget(path, 'title') })
  } else if (m.titleLen > TITLE_MAX) {
    issues.push({ severity: 'important', title: `Titulek je dlouhý (${m.titleLen} znaků, max ${TITLE_MAX})`, message: `Aktuální titulek: „${m.title}". Google ho v záložce utne. Zkrať na ${TITLE_MIN}-${TITLE_MAX} znaků.`, example: 'Nech klíčové slovo + lokalitu + brand, odeber výplň', target: findCmsTarget(path, 'title') })
  }

  // META DESCRIPTION
  if (!m.description) {
    issues.push({ severity: 'important', title: 'Chybí Popisek pro Google (meta description)', message: 'Popisek je 1-3 věty pod modrým nadpisem ve výsledcích vyhledávání — láká uživatele na klik. Bez něj Google ukáže náhodný text ze stránky.', example: 'Půjčovna motorek na Vysočině – bez kauce, výbava v ceně, online rezervace. Cestovní, naked i dětské motorky. Otevřeno nonstop.', target: findCmsTarget(path, 'description') })
  } else if (m.descLen < DESC_MIN) {
    issues.push({ severity: 'tip', title: `Popisek je krátký (${m.descLen} znaků, ideál ${DESC_MIN}-${DESC_MAX})`, message: `Aktuální popisek: „${m.description}". Doplň výhody co zákazník ocení.`, example: 'Doplň: „Bez kauce, výbava v ceně, online rezervace, Pelhřimov Vysočina."', target: findCmsTarget(path, 'description') })
  } else if (m.descLen > DESC_MAX) {
    issues.push({ severity: 'important', title: `Popisek je dlouhý (${m.descLen} znaků, max ${DESC_MAX})`, message: `Google zobrazí max ~${DESC_MAX} znaků, zbytek utne. Zkrať na nejdůležitější informace.`, example: 'Odeber druhou polovinu věty nebo redundantní slova', target: findCmsTarget(path, 'description') })
  }

  // H1
  if (h1Count === 0) {
    issues.push({ severity: 'critical', title: 'Stránka nemá žádný Hlavní nadpis (H1)', message: 'Každá stránka musí mít právě jeden H1 — velký nadpis nahoře co Google používá k pochopení obsahu.', example: 'Půjčovna motorek Pelhřimov – bez kauce', target: findCmsTarget(path, 'h1') })
  } else if (h1Count > 1) {
    issues.push({ severity: 'important', title: `Stránka má ${h1Count} H1 nadpisů (smí být jen 1)`, message: `Nalezené H1: ${h1Arr.map(h => `„${h}"`).join(', ')}. Druhý a další H1 demotuj na H2 — v CMS editoru použij styl "Nadpis 2" místo "Nadpis 1".`, example: 'Nech jen 1 hlavní H1, ostatní nadpisy v textu jako H2/H3', target: findCmsTarget(path, 'h1') })
  } else {
    const h1 = h1Arr[0] || ''
    if (h1.length < H1_MIN) {
      issues.push({ severity: 'important', title: `Hlavní nadpis je příliš krátký (${h1.length} znaků): „${h1}"`, message: 'Krátký nadpis nic neříká. Doplň klíčové slovo + lokalitu.', example: 'Půjčovna motorek na Vysočině – bez kauce', target: findCmsTarget(path, 'h1') })
    } else if (h1.length > H1_MAX) {
      issues.push({ severity: 'tip', title: `Hlavní nadpis je dlouhý (${h1.length} znaků, doporučeno do 70)`, message: `Aktuální H1: „${h1}". Zkrať na hlavní téma + lokalitu + jednu výhodu.`, example: 'Max 70 znaků, nejdůležitější vepředu', target: findCmsTarget(path, 'h1') })
    }
    // Title vs H1
    if (m.title && h1 && m.title.toLowerCase().trim() === h1.toLowerCase().trim()) {
      issues.push({ severity: 'tip', title: 'Titulek (záložka) a Hlavní nadpis (na stránce) jsou totožné', message: `Oba: „${m.title}". Měly by se lišit — titulek pro Google, H1 pro lidi na stránce.`, example: 'H1: „Vyber si motorku na Vysočině – ráno si ji vyzvedneš"', target: findCmsTarget(path, 'h1') })
    }
  }

  // CONTENT — jen pro NE-funkcni stranky
  if (!isFunc) {
    if (m.wordCount < WORD_MIN_CRIT) {
      issues.push({ severity: 'important', title: `Velmi málo textu na stránce (${m.wordCount} slov, doporučeno ${WORD_MIN_WARN}+)`, message: 'Google upřednostňuje stránky s 500+ slovy. Krátké stránky obtížně rankují. Doplň sekce s detaily, postupem, FAQ.', example: 'Přidej: „Co dostanete v ceně", „Jak probíhá rezervace", „Kde nás najdete", FAQ 3-5 otázek', target: findCmsTarget(path, 'body') })
    } else if (m.wordCount < WORD_MIN_WARN) {
      issues.push({ severity: 'tip', title: `Méně textu na stránce (${m.wordCount} slov, doporučeno ${WORD_MIN_WARN}+)`, message: 'Ideál je 500+ slov. Rozšiř popis služby nebo přidej sekce s tipy/FAQ.', example: 'Doplň 1-2 sekce o výhodách, postupu nebo často kladených dotazech', target: findCmsTarget(path, 'body') })
    }
    if (m.paragraphCount > 0 && m.paragraphCount < 3) {
      issues.push({ severity: 'tip', title: `Málo odstavců (${m.paragraphCount}, doporučeno 3+)`, message: 'Strukturovaný text je čitelnější. Rozděl do 3+ odstavců s podnadpisy.', example: 'Struktura: úvod → výhody → postup → FAQ → CTA', target: findCmsTarget(path, 'body') })
    }
  }

  // IMAGES bez alt
  if (m.imagesNoAlt > 0) {
    issues.push({ severity: 'tip', title: `${m.imagesNoAlt} obrázků bez popisku (alt)`, message: 'Obrázky by měly mít alt popisek pro Google Images a čtečky. (Web má automatický fallback, ale ruční popisek je lepší.)', example: 'Při uploadu obrázku ve Velíně doplň jeho popis', target: null })
  }

  // STRONG/BOLD spam
  if (m.strongCount > STRONG_MAX) {
    issues.push({ severity: 'tip', title: `Příliš mnoho tučného textu (${m.strongCount} výrazů, doporučeno do ${STRONG_MAX})`, message: 'Hodně tučného textu vypadá jako over-optimalizace. Nech tučně jen 1-3 nejdůležitější fráze.', example: 'Odeber zbytečné tučnění z méně důležitých slov', target: findCmsTarget(path, 'body') })
  }

  return issues
}

export default function SeoHealthTab({ onJumpToText }) {
  const [scanResults, setScanResults] = useState(null) // { [path]: metrics }
  const [scanning, setScanning] = useState(false)
  const [scanError, setScanError] = useState(null)
  const [checkedAt, setCheckedAt] = useState(null)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [expanded, setExpanded] = useState({})
  // promote defaults
  const [variables, setVariables] = useState({})
  const [seeding, setSeeding] = useState(false)
  const [seedResult, setSeedResult] = useState(null)

  async function runScan() {
    setScanning(true); setScanError(null)
    try {
      const { data, error } = await supabase.functions.invoke('seo-check', { body: { paths: SCAN_PATHS } })
      if (error) throw error
      if (data?.results) {
        setScanResults(data.results)
        setCheckedAt(data.checkedAt || new Date().toISOString())
      } else {
        setScanError('Edge funkce nevrátila výsledky. Zkontroluj že je nasazená: supabase functions deploy seo-check')
      }
    } catch (e) {
      setScanError('Chyba při scanu: ' + (e?.message || e) + '. Pravděpodobně edge funkce "seo-check" ještě není nasazená — spusť: supabase functions deploy seo-check')
    } finally { setScanning(false) }
  }

  async function loadVariables() {
    const { data } = await supabase.from('cms_variables').select('key, value')
    const map = {}
    ;(data || []).forEach(r => { if (r.key && typeof r.value === 'string') map[r.key] = r.value })
    setVariables(map)
  }

  useEffect(() => { runScan(); loadVariables() }, [])

  async function promoteAllDefaults() {
    if (!confirm('Uloží všechny výchozí texty z Velínu do databáze. Existující ručně upravené texty zůstanou beze změny. Pokračovat?')) return
    setSeeding(true); setSeedResult(null)
    const missing = ALL_FIELDS.filter(f => !variables[f.key] && f.default != null && f.default !== '')
    let inserted = 0, failed = 0
    for (let i = 0; i < missing.length; i += 50) {
      const batch = missing.slice(i, i + 50).map(f => ({ key: f.key, value: String(f.default), category: 'web' }))
      // upsert s ignoreDuplicates = INSERT ... ON CONFLICT (key) DO NOTHING:
      // klíč, který mezitím vznikl (inline edit z webu / jiný admin), neshodí
      // celý batch a existující ručně upravené texty se nikdy nepřepíšou.
      const { error } = await supabase.from('cms_variables').upsert(batch, { onConflict: 'key', ignoreDuplicates: true })
      if (error) failed += batch.length; else inserted += batch.length
    }
    await loadVariables()
    setSeedResult({ inserted, failed })
    setSeeding(false)
  }

  const reports = useMemo(() => {
    if (!scanResults) return []
    return SCAN_PATHS.map(path => {
      const m = scanResults[path] || { error: 'Nezkontrolováno' }
      const issues = buildIssues(path, m)
      let penalty = 0
      issues.forEach(i => { penalty += i.severity === 'critical' ? 25 : (i.severity === 'important' ? 12 : 4) })
      const score = m.error ? 0 : Math.max(0, Math.min(100, 100 - penalty))
      const page = PATH_TO_PAGE[path]
      return { path, page, metrics: m, issues, score, label: page?.label || path, icon: page?.icon || '🌐' }
    }).sort((a, b) => a.score - b.score)
  }, [scanResults])

  const totals = useMemo(() => {
    let critical = 0, important = 0, tip = 0
    reports.forEach(r => r.issues.forEach(i => {
      if (i.severity === 'critical') critical++; else if (i.severity === 'important') important++; else tip++
    }))
    const checked = reports.filter(r => !r.metrics.error)
    const avg = checked.length ? Math.round(checked.reduce((s, r) => s + r.score, 0) / checked.length) : 0
    return { critical, important, tip, avg, count: reports.length, checked: checked.length }
  }, [reports])

  const filtered = useMemo(() => {
    const s = search.toLowerCase().trim()
    return reports.filter(r => {
      if (s && !r.label.toLowerCase().includes(s) && !r.path.toLowerCase().includes(s)) return false
      if (filter === 'all') return true
      if (filter === 'ok') return r.issues.length === 0
      return r.issues.some(i => i.severity === filter)
    })
  }, [reports, filter, search])

  function handleFix(target) {
    if (target && target.pageId) {
      onJumpToText && onJumpToText(target.pageId, target.fieldKey, target.sectionId)
    }
  }

  const scoreColor = (s) => s >= 90 ? '#16a34a' : (s >= 70 ? '#f59e0b' : '#dc2626')
  const sevColor = (s) => s === 'critical' ? '#dc2626' : (s === 'important' ? '#f59e0b' : '#16a34a')
  const sevIcon = (s) => s === 'critical' ? '⛔' : (s === 'important' ? '⚠️' : '💡')
  const missingDefaults = ALL_FIELDS.filter(f => !variables[f.key] && f.default != null && f.default !== '').length

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
        <div style={{ flex: 1 }}>
          <h2 style={{ fontSize: 18, fontWeight: 800, margin: 0 }}>SEO Health — analýza živého webu</h2>
          <div style={{ fontSize: 12, color: '#6b7a72', marginTop: 2 }}>
            Kontroluje SKUTEČNÉ stránky na motogo24.cz (ne jen CMS texty).
            {checkedAt && <> Poslední scan: {new Date(checkedAt).toLocaleString('cs-CZ')}</>}
          </div>
        </div>
        <button onClick={runScan} disabled={scanning} className="rounded-btn cursor-pointer"
          style={{ padding: '8px 18px', background: '#74FB71', color: '#1a2e22', border: 'none', fontWeight: 800, fontSize: 13, textTransform: 'uppercase' }}>
          {scanning ? 'Skenuji…' : '↻ Znovu naskenovat'}
        </button>
      </div>

      {scanError && (
        <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 8, padding: 14, marginBottom: 16, color: '#991b1b', fontSize: 13 }}>
          <strong>⚠️ {scanError}</strong>
        </div>
      )}

      {scanning && !scanResults && (
        <div style={{ padding: 40, textAlign: 'center', color: '#6b7a72' }}>Skenuji {SCAN_PATHS.length} stránek na motogo24.cz…</div>
      )}

      {scanResults && (
        <>
          {/* Stats */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16 }}>
            <StatCard label={`Průměr (${totals.checked} stránek)`} value={`${totals.avg}%`} color={scoreColor(totals.avg)} />
            <StatCard label="K opravě hned" value={totals.critical} color="#dc2626" icon="⛔" />
            <StatCard label="Důležité" value={totals.important} color="#f59e0b" icon="⚠️" />
            <StatCard label="Doporučení" value={totals.tip} color="#16a34a" icon="💡" />
          </div>

          {/* Promote defaults */}
          {(missingDefaults > 0 || seedResult) && (
            <div style={{ background: '#fffbeb', padding: 12, borderRadius: 8, marginBottom: 16, borderLeft: '4px solid #f59e0b', display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ flex: 1, fontSize: 13 }}>
                {seedResult ? <span><strong style={{ color: '#16a34a' }}>✓ Uloženo!</strong> {seedResult.inserted} výchozích textů do DB.{seedResult.failed > 0 && <span style={{ color: '#dc2626' }}> {seedResult.failed} chyb.</span>}</span>
                  : <span><strong>📌 {missingDefaults} textů z Velínu není v databázi.</strong> Uloží je hromadně, existující ručně upravené se nepřepíšou.</span>}
              </div>
              {!seedResult && <button onClick={promoteAllDefaults} disabled={seeding} className="rounded-btn cursor-pointer" style={{ padding: '8px 14px', background: '#1a2e22', color: '#74FB71', border: 'none', fontWeight: 700, fontSize: 12, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>{seeding ? 'Ukládám…' : `Uložit ${missingDefaults} textů`}</button>}
            </div>
          )}

          {/* Filter */}
          <div style={{ display: 'flex', gap: 8, marginBottom: 14, flexWrap: 'wrap', alignItems: 'center' }}>
            <span style={{ fontSize: 12, fontWeight: 700, color: '#6b7a72', textTransform: 'uppercase' }}>Filtr:</span>
            {[
              { id: 'all', label: 'Vše', count: reports.length },
              { id: 'critical', label: '⛔ K opravě', count: reports.filter(r => r.issues.some(i => i.severity === 'critical')).length, color: '#dc2626' },
              { id: 'important', label: '⚠️ Důležité', count: reports.filter(r => r.issues.some(i => i.severity === 'important')).length, color: '#f59e0b' },
              { id: 'tip', label: '💡 Doporučení', count: reports.filter(r => r.issues.some(i => i.severity === 'tip')).length, color: '#16a34a' },
              { id: 'ok', label: '✓ Bez problémů', count: reports.filter(r => r.issues.length === 0).length, color: '#16a34a' },
            ].map(f => (
              <button key={f.id} onClick={() => setFilter(f.id)} className="rounded-btn cursor-pointer"
                style={{ padding: '6px 14px', fontSize: 13, fontWeight: 700, background: filter === f.id ? (f.color || '#1a2e22') : '#f1faf7', color: filter === f.id ? '#fff' : '#1a2e22', border: filter === f.id ? `2px solid ${f.color || '#1a2e22'}` : '2px solid transparent' }}>
                {f.label} <span style={{ opacity: 0.7, fontSize: 11 }}>({f.count})</span>
              </button>
            ))}
            <input type="text" placeholder="Hledat stránku…" value={search} onChange={e => setSearch(e.target.value)} style={{ flex: 1, minWidth: 200, padding: '6px 12px', borderRadius: 8, border: '1px solid #d4e8e0' }} />
          </div>

          {/* Help */}
          <div style={{ background: '#f1faf7', padding: 12, borderRadius: 8, fontSize: 13, marginBottom: 16, borderLeft: '4px solid #74FB71' }}>
            <strong>Jak to funguje:</strong> Tlačítko <strong>↻ Znovu naskenovat</strong> stáhne všech {SCAN_PATHS.length} stránek z motogo24.cz a změří je.
            Klik na stránku → seznam problémů s vysvětlením + příkladem. Klik <strong>Opravit →</strong> otevře přesné CMS pole (pokud existuje).
            U problémů co se řídí z kódu (ne CMS) je poznámka kde to upravit.
          </div>

          {/* Pages */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {filtered.length === 0 && <div style={{ padding: 30, textAlign: 'center', color: '#6b7a72', background: '#fafafa', borderRadius: 12 }}>Žádné stránky neodpovídají filtru.</div>}
            {filtered.map(r => (
              <PageRow key={r.path} report={r} expanded={!!expanded[r.path]} onToggle={() => setExpanded(s => ({ ...s, [r.path]: !s[r.path] }))} onFix={handleFix} scoreColor={scoreColor} sevColor={sevColor} sevIcon={sevIcon} />
            ))}
          </div>
        </>
      )}
    </div>
  )
}

function StatCard({ label, value, color, icon }) {
  return <div style={{ background: '#fff', padding: 16, borderRadius: 12, border: '1px solid #e2ece7', borderTop: `4px solid ${color}`, textAlign: 'center' }}>
    <div style={{ fontSize: 28, fontWeight: 800, color, marginBottom: 4 }}>{icon && <span style={{ marginRight: 6 }}>{icon}</span>}{value}</div>
    <div style={{ fontSize: 11, color: '#6b7a72', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
  </div>
}

function PageRow({ report, expanded, onToggle, onFix, scoreColor, sevColor, sevIcon }) {
  const { path, label, icon, metrics: m, issues, score } = report
  const color = scoreColor(score)
  const c = { critical: issues.filter(i => i.severity === 'critical').length, important: issues.filter(i => i.severity === 'important').length, tip: issues.filter(i => i.severity === 'tip').length }
  return (
    <div style={{ background: '#fff', borderRadius: 12, border: '1px solid #e2ece7', borderLeft: `5px solid ${color}`, overflow: 'hidden' }}>
      <div onClick={onToggle} style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', background: expanded ? '#f1faf7' : '#fff' }}>
        <div style={{ minWidth: 60, fontWeight: 800, fontSize: 22, color, textAlign: 'center' }}>{m.error ? '?' : `${score}%`}</div>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, fontSize: 15 }}>{icon} {label}<span style={{ marginLeft: 8, fontSize: 12, color: '#6b7a72', fontWeight: 400 }}>{path}</span></div>
          <div style={{ fontSize: 12, color: '#6b7a72', marginTop: 3 }}>
            {m.error ? <span style={{ color: '#dc2626' }}>⚠️ {m.error}</span>
              : issues.length === 0 ? '✓ Vše v pořádku'
              : `${issues.length} ${issues.length === 1 ? 'problém' : (issues.length < 5 ? 'problémy' : 'problémů')}`}
            {!m.error && <> · {m.wordCount} slov · {m.h1Count} H1 · titulek {m.titleLen}zn · popisek {m.descLen}zn{m.imagesNoAlt > 0 && ` · ${m.imagesNoAlt} obr. bez alt`}</>}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {c.critical > 0 && <Badge color="#dc2626" icon="⛔" count={c.critical} />}
          {c.important > 0 && <Badge color="#f59e0b" icon="⚠️" count={c.important} />}
          {c.tip > 0 && <Badge color="#16a34a" icon="💡" count={c.tip} />}
          <span style={{ fontSize: 20, color: '#6b7a72', marginLeft: 4 }}>{expanded ? '▾' : '▸'}</span>
        </div>
      </div>
      {expanded && (
        <div style={{ padding: '0 16px 14px 16px', borderTop: '1px solid #e2ece7' }}>
          {issues.length === 0 ? (
            <div style={{ padding: '12px 0', fontSize: 13, color: '#16a34a' }}>✓ Stránka splňuje všechny kontroly. {m.wordCount} slov · {m.paragraphCount} odstavců · 1 H1 · titulek {m.titleLen} znaků · popisek {m.descLen} znaků.</div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
              {issues.map((iss, idx) => (
                <div key={idx} style={{ background: '#fafafa', borderRadius: 8, padding: 12, borderLeft: `4px solid ${sevColor(iss.severity)}`, fontSize: 13 }}>
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
                    <div style={{ fontSize: 18 }}>{sevIcon(iss.severity)}</div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontWeight: 700, color: sevColor(iss.severity), marginBottom: 4, fontSize: 14 }}>{iss.title}</div>
                      <div style={{ color: '#1a2e22', lineHeight: 1.5 }}>{iss.message}</div>
                      {iss.example && <div style={{ marginTop: 8, padding: '8px 12px', background: '#f0fdf4', borderRadius: 6, borderLeft: '3px solid #16a34a', fontSize: 12, color: '#14532d', whiteSpace: 'pre-wrap' }}><strong>👍 Příklad / doporučení:</strong>{' '}<span style={{ fontStyle: 'italic' }}>{iss.example}</span></div>}
                      {!iss.target && <div style={{ marginTop: 8, fontSize: 11, color: '#92400e', background: '#fffbeb', padding: '6px 10px', borderRadius: 6 }}>ℹ️ Tento text se neupravuje z Velínu — řídí ho kód webu (data soubory). Pokud ho chceš editovat z CMS, napiš vývojáři ať přidá pole.</div>}
                    </div>
                    {iss.target ? (
                      <button onClick={() => onFix(iss.target)} className="rounded-btn cursor-pointer" style={{ background: '#74FB71', color: '#1a2e22', border: 'none', padding: '6px 14px', fontSize: 12, fontWeight: 800, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Opravit →</button>
                    ) : (
                      <span style={{ fontSize: 11, color: '#9ca3af', whiteSpace: 'nowrap' }}>—</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
          <div style={{ marginTop: 12, fontSize: 12 }}>
            <a href={`https://www.motogo24.cz${path}`} target="_blank" rel="noopener noreferrer" style={{ color: '#0d6e0d', textDecoration: 'underline', fontWeight: 600 }}>↗ Otevřít {path} na webu</a>
          </div>
        </div>
      )}
    </div>
  )
}

function Badge({ color, icon, count }) {
  return <span style={{ background: color, color: '#fff', fontSize: 11, padding: '3px 9px', borderRadius: 12, fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: 4 }}>{icon} {count}</span>
}
