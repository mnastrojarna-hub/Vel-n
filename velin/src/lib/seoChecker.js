// SEO checker — analyzuje POUZE texty uložené v cms_variables (CMS overlay).
//
// DŮLEŽITÉ: NEPOČÍTÁ skutečný obsah stránky! PHP šablony (data/*.php) mají
// vlastní bohaté fallbacky které nevidíme. Proto tu NEKONTROLUJEME:
//   - počet slov / odstavců na stránce (PHP přidá víc)
//   - klíčová slova v body (PHP body je bohatší)
// Tyto věci řeší externí crawl (Seobility / Google Search Console).
//
// KONTROLUJEME jen co je 100% měřitelné z CMS hodnot a fixovatelné z Velinu:
//   - Title (pokud existuje seo.title CMS pole): délka 30-65 znaků
//   - Meta description (pokud existuje seo.description): délka 80-160 znaků
//   - H1 (pokud existuje h1 pole): prázdné / příliš krátké (<3 znaky) / příliš dlouhé (>120)
//   - Title vs H1: měly by se lišit
//
// Funkční stránky (košík, pokladna, potvrzení, úprava rezervace, rezervace)
// jsou transakční — Seobility je sám ignoruje, takže je tu úplně přeskočíme.

// Stránky které jsou transakční / funkční — SEO obsahové kontroly se neaplikují
const FUNCTIONAL_PAGE_IDS = new Set([
  'kosik', 'objednavka', 'potvrzeni', 'upravit_rezervace', 'upravit-rezervace',
  'rezervace', 'layout', // PAGE_LAYOUT = header/footer/cookies, ne samostatna stranka
])

// Najde field a jeho sekci v page definici podle predikátu.
function findFieldWithSection(pageDef, predicate) {
  for (const section of (pageDef.sections || [])) {
    for (const field of (section.fields || [])) {
      if (predicate(field, section)) {
        return { fieldKey: field.key, sectionId: section.id }
      }
    }
  }
  return null
}

function findTitleField(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.seo\.title$|\.seoTitle$/i.test(f.key) ||
    /title.*titulek.*záložky|seo.*title/i.test((f.label || '').toLowerCase())
  )
}
function findDescField(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.seo\.description$|\.seoDescription$/i.test(f.key) ||
    /meta description|seo.*description|popisek.*google/i.test((f.label || '').toLowerCase())
  )
}
function findH1Field(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.h1$|\.h1\.text$/i.test(f.key) ||
    /^h1\b|h1.*nadpis/i.test((f.label || '').toLowerCase())
  )
}

export function analyzeSeo(pageDef, valuesMap) {
  const issues = []
  const isFunctional = FUNCTIONAL_PAGE_IDS.has(pageDef.id)

  const titleField = findTitleField(pageDef)
  const descField = findDescField(pageDef)
  const h1Field = findH1Field(pageDef)

  const title = (titleField && valuesMap[titleField.fieldKey]) || ''
  const description = (descField && valuesMap[descField.fieldKey]) || ''
  const h1 = (h1Field && valuesMap[h1Field.fieldKey]) || ''

  const stats = {
    titleLen: title.length,
    descLen: description.length,
    h1,
    hasTitleField: !!titleField,
    hasDescField: !!descField,
    hasH1Field: !!h1Field,
    isFunctional,
  }

  // === TITLE === (jen pokud existuje CMS pole — jinak řídí PHP a admin nemá co opravit)
  if (titleField) {
    if (!title) {
      issues.push({
        severity: 'critical',
        title: 'Titulek stránky (Title) je prázdný',
        message: 'Titulek se zobrazí v záložce prohlížeče a jako modrý nadpis ve výsledcích Googlu. Klikni Opravit → otevře se přesné pole "Title", napiš tam titulek 45-65 znaků.',
        example: 'Půjčovna motorek Pelhřimov | MotoGo24',
        ...titleField,
      })
    } else if (title.length < 30) {
      issues.push({
        severity: 'tip',
        title: `Titulek je krátký (${title.length} znaků, ideál 45-65)`,
        message: `Krátký titulek nevyužívá prostor v Googlu. Doplň lokalitu nebo hlavní výhodu. Klikni Opravit → otevře se pole "Title".`,
        example: `Aktuálně: "${title}"\nDoporučeno: "${title} | MotoGo24 Pelhřimov" (delší, s brandem a lokalitou)`,
        ...titleField,
      })
    } else if (title.length > 65) {
      issues.push({
        severity: 'important',
        title: `Titulek je dlouhý (${title.length} znaků, max 65)`,
        message: `Google v záložce a ve výsledcích zobrazí maximálně ~65 znaků, zbytek utne třemi tečkami. Klikni Opravit → zkrať pole "Title".`,
        example: `Aktuálně: "${title}"\nZkrať na max 65 znaků — nech klíčové slovo + lokalitu + brand, odeber výplň.`,
        ...titleField,
      })
    }
  }

  // === META DESCRIPTION === (jen pokud existuje CMS pole)
  if (descField) {
    if (!description) {
      issues.push({
        severity: 'important',
        title: 'Popisek pro Google (meta description) je prázdný',
        message: 'Popisek je 1-3 věty pod modrým nadpisem ve výsledcích vyhledávání — láká uživatele na klik. Bez něj si Google vymyslí ukázku z náhodného textu. Klikni Opravit → otevře se pole "Meta description", napiš 120-160 znaků.',
        example: 'Půjčovna motorek na Vysočině – bez kauce, výbava v ceně, online rezervace. Cestovní, naked i dětské motorky. Otevřeno nonstop.',
        ...descField,
      })
    } else if (description.length < 80) {
      issues.push({
        severity: 'tip',
        title: `Popisek je krátký (${description.length} znaků, ideál 120-160)`,
        message: 'Krátký popisek nevyužívá prostor ve výsledcích. Doplň výhody co zákazník ocení. Klikni Opravit → otevře se pole "Meta description".',
        example: `Aktuálně: "${description}"\nDoporučeno doplnit: "Bez kauce, výbava v ceně, online rezervace, Pelhřimov Vysočina."`,
        ...descField,
      })
    } else if (description.length > 160) {
      issues.push({
        severity: 'important',
        title: `Popisek je dlouhý (${description.length} znaků, max 160)`,
        message: 'Google zobrazí max ~160 znaků a zbytek utne. Klikni Opravit → zkrať pole "Meta description" na nejdůležitější informace.',
        example: `Aktuálně ${description.length} znaků.\nZkrať na 120-160 — odeber druhou polovinu věty nebo redundantní slova.`,
        ...descField,
      })
    }
  }

  // === H1 === (jen pokud existuje CMS pole)
  if (h1Field) {
    if (!h1) {
      // POZN: PHP renderHeading() má auto-fallback "MotoGo24 — půjčovna motorek",
      // takže prázdné CMS H1 NENÍ kritické (stránka H1 stejně dostane). Ale je
      // lepší mít specifický H1 než generický fallback.
      issues.push({
        severity: 'tip',
        title: 'Hlavní nadpis (H1) není vyplněn z CMS',
        message: 'Stránka sice automaticky dostane výchozí H1, ale specifický nadpis je lepší pro SEO. Klikni Opravit → otevře se pole "H1 nadpis", napiš tam výstižný nadpis 20-70 znaků.',
        example: pageDef.label.includes('Postup') ? 'Postup půjčení motorky – krok za krokem'
          : pageDef.label.includes('Vrácení') ? 'Vrácení motorky – jednoduše a bez komplikací'
          : 'Půjčovna motorek Pelhřimov – bez kauce, výbava v ceně',
        ...h1Field,
      })
    } else if (h1.length < 3) {
      issues.push({
        severity: 'important',
        title: `Hlavní nadpis je příliš krátký (${h1.length} znaků)`,
        message: 'Nadpis jako "OK" nebo "Hi" nic neříká. Klikni Opravit → napiš výstižný nadpis 20-70 znaků s klíčovým slovem.',
        example: 'Půjčovna motorek na Vysočině – bez kauce',
        ...h1Field,
      })
    } else if (h1.length > 120) {
      issues.push({
        severity: 'tip',
        title: `Hlavní nadpis je dlouhý (${h1.length} znaků, doporučeno do 70)`,
        message: 'Příliš dlouhý nadpis zhoršuje čitelnost. Klikni Opravit → zkrať na hlavní téma + lokalitu + jednu výhodu.',
        example: 'Zkrať na max 70 znaků, nech to nejdůležitější vepředu.',
        ...h1Field,
      })
    }
  }

  // === Title vs H1 — měly by být odlišné === (jen pokud obě CMS pole existují a obě vyplněna)
  if (titleField && h1Field && title && h1 && title.toLowerCase().trim() === h1.toLowerCase().trim()) {
    issues.push({
      severity: 'tip',
      title: 'Titulek (záložka) a Hlavní nadpis (na stránce) jsou totožné',
      message: 'Měly by se LIŠIT. Titulek (Title) je pro Google a záložku prohlížeče — krátký, klíčová slova, brand. H1 je pro lidi co už jsou na stránce — může být víc lidský, akční. Klikni Opravit → změň pole "H1 nadpis" aby se lišil od titulku.',
      example: `Aktuálně oba: "${title}"\nDoporučeno H1: "Vyber si motorku na Vysočině – ráno si ji vyzvedneš"`,
      ...h1Field,
    })
  }

  // Score
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
  return s === 'critical' ? 'Důležité opravit hned' : (s === 'important' ? 'Důležité' : 'Doporučení')
}
export function severityIcon(s) {
  return s === 'critical' ? '⛔' : (s === 'important' ? '⚠️' : '💡')
}
export function scoreColor(score) {
  if (score >= 90) return '#16a34a'
  if (score >= 70) return '#f59e0b'
  return '#dc2626'
}
