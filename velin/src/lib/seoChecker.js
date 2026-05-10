// SEO checker — analyzuje CMS texty per-stránka a vrací seznam issues s
// severity (critical/important/tip). Pouzivany v SeoHealthTab pro Velín dashboard.
//
// Pravidla odpovidaji Seobility a Google Search Console doporucenim:
//   - Title 30-65 znaku (~580 px)
//   - Meta description 120-160 znaku (~1000 px)
//   - H1 vzdy pritomny, neprazdny, ne stejny jako title
//   - Body text >= 500 slov (Content Quality)
//   - >= 3 odstavce (Readability)
//   - H1 klicova slova obsazena v body text (Topical Relevance)

// Vraci `{ score, issues: [{severity, message, fix?}], stats: {...} }`
export function analyzeSeo(pageDef, valuesMap) {
  const issues = []
  const stats = { titleLen: 0, descLen: 0, h1: '', bodyLen: 0, paragraphCount: 0 }

  // Vyextrahuj klicove pole — title, description, h1, body texty
  const titleKey = pageDef.sections?.flatMap(s => s.fields || [])
    .find(f => /\.(title|h1)$/i.test(f.key) || /title|seo.title|nadpis/i.test(f.label || ''))?.key
  const descKey = pageDef.sections?.flatMap(s => s.fields || [])
    .find(f => /\.(description|seoDescription|meta)$/i.test(f.key) || /description|popis/i.test(f.label || ''))?.key
  const h1Key = pageDef.sections?.flatMap(s => s.fields || [])
    .find(f => /\.h1$/i.test(f.key) || /^h1|hlavni nadpis/i.test(f.label || ''))?.key

  const title = (titleKey ? valuesMap[titleKey] : '') || pageDef.seoTitle || ''
  const description = (descKey ? valuesMap[descKey] : '') || pageDef.seoDescription || ''
  const h1 = (h1Key ? valuesMap[h1Key] : '') || pageDef.h1 || ''

  stats.titleLen = title.length
  stats.descLen = description.length
  stats.h1 = h1

  // Title check
  if (!title) {
    issues.push({ severity: 'critical', message: 'Title chybí', fix: 'seo_title' })
  } else if (title.length < 30) {
    issues.push({ severity: 'tip', message: `Title je krátký (${title.length} znaků, ideál 45-65)`, fix: 'seo_title' })
  } else if (title.length > 65) {
    issues.push({ severity: 'important', message: `Title je dlouhý (${title.length} znaků, max 65)`, fix: 'seo_title' })
  }

  // Description check
  if (!description) {
    issues.push({ severity: 'important', message: 'Meta description chybí', fix: 'seo_description' })
  } else if (description.length < 80) {
    issues.push({ severity: 'tip', message: `Meta description je krátká (${description.length} znaků, ideál 120-160)`, fix: 'seo_description' })
  } else if (description.length > 160) {
    issues.push({ severity: 'important', message: `Meta description je dlouhá (${description.length} znaků, max 160)`, fix: 'seo_description' })
  }

  // H1 check
  if (!h1) {
    issues.push({ severity: 'critical', message: 'H1 nadpis chybí', fix: 'h1' })
  } else if (h1.length < 10) {
    issues.push({ severity: 'tip', message: `H1 je krátký (${h1.length} znaků)`, fix: 'h1' })
  } else if (h1.length > 80) {
    issues.push({ severity: 'tip', message: `H1 je dlouhý (${h1.length} znaků, max 80)`, fix: 'h1' })
  }

  // Title vs H1 — měly by být odlišné
  if (title && h1 && title.toLowerCase().trim() === h1.toLowerCase().trim()) {
    issues.push({ severity: 'tip', message: 'Title a H1 jsou totožné — měly by být odlišné', fix: 'seo_title' })
  }

  // Body content — agreguj všechna textová pole stránky (kromě title/description/h1/btn/cta)
  const bodyTexts = []
  pageDef.sections?.forEach(section => {
    section.fields?.forEach(f => {
      // Skip SEO meta + krátké labely
      if (f.key === titleKey || f.key === descKey || f.key === h1Key) return
      if (/\.(label|btn|cta|aria|alt|placeholder|href|icon|img|image|map_src|map_title|empty)$/i.test(f.key)) return
      const v = valuesMap[f.key]
      if (typeof v === 'string' && v.trim().length > 30) {
        bodyTexts.push(v)
      }
    })
  })
  const bodyText = bodyTexts.join(' ')
  const bodyClean = bodyText.replace(/<[^>]*>/g, ' ').replace(/&[a-z]+;/gi, ' ')
  const wordCount = bodyClean.trim().split(/\s+/).filter(Boolean).length
  const paragraphCount = bodyTexts.filter(t => t.length > 100).length

  stats.bodyLen = wordCount
  stats.paragraphCount = paragraphCount

  if (wordCount > 0) {
    if (wordCount < 200) {
      issues.push({ severity: 'important', message: `Velmi málo textu (${wordCount} slov, doporučeno 500+)`, fix: 'body' })
    } else if (wordCount < 500) {
      issues.push({ severity: 'tip', message: `Méně textu (${wordCount} slov, doporučeno 500+)`, fix: 'body' })
    }
    if (paragraphCount > 0 && paragraphCount < 3) {
      issues.push({ severity: 'tip', message: `Málo odstavců (${paragraphCount}, doporučeno 3+)`, fix: 'body' })
    }
  }

  // H1 keywords vs body text
  if (h1 && bodyClean) {
    const h1Words = h1.toLowerCase().split(/\s+/).filter(w => w.length > 3 && !/^(jak|si|na|do|že|pro|bez|nebo|kdo|kde|nebo|mez|tom)$/i.test(w))
    const bodyLower = bodyClean.toLowerCase()
    const missing = h1Words.filter(w => !bodyLower.includes(w))
    if (missing.length > 0 && missing.length === h1Words.length) {
      issues.push({ severity: 'important', message: `H1 klíčová slova nejsou v textu: "${missing.join(', ')}"`, fix: 'body' })
    } else if (missing.length > 0) {
      issues.push({ severity: 'tip', message: `Některá H1 slova nejsou v textu: "${missing.join(', ')}"`, fix: 'body' })
    }
  }

  // Score: 100 - (3 critical, 2 important, 1 tip per issue), min 0, max 100
  let penalty = 0
  issues.forEach(i => {
    penalty += i.severity === 'critical' ? 25 : (i.severity === 'important' ? 12 : 4)
  })
  const score = Math.max(0, Math.min(100, 100 - penalty))

  return { score, issues, stats }
}

export function severityColor(s) {
  return s === 'critical' ? '#dc2626' : (s === 'important' ? '#f59e0b' : '#16a34a')
}

export function severityLabel(s) {
  return s === 'critical' ? 'Kritické' : (s === 'important' ? 'Důležité' : 'Tip')
}

export function scoreColor(score) {
  if (score >= 90) return '#16a34a'
  if (score >= 70) return '#f59e0b'
  return '#dc2626'
}
