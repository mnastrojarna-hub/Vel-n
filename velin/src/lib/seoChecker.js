// SEO checker — analyzuje CMS texty per-stránka a vrací seznam issues
// se srozumitelnými hláškami v češtině pro non-programátory.
//
// Pravidla odpovidaji Seobility a Google Search Console doporucenim:
//   - Title 30-65 znaku
//   - Meta description 120-160 znaku
//   - H1 vzdy pritomny
//   - Body text >= 500 slov
//   - >= 3 odstavce
//   - H1 klicova slova obsazena v body text

// Najde pole v sekci ktere pasuje na vzor (pro auto-jump na konkretni field)
function findFieldKey(pageDef, predicate) {
  for (const section of (pageDef.sections || [])) {
    for (const field of (section.fields || [])) {
      if (predicate(field, section)) return field.key
    }
  }
  return null
}

// Hlavni analyzator — vrati { score, issues, stats }
// Kazdy issue ma:
//   severity: 'critical' | 'important' | 'tip'
//   title: kratky nazev problemu (CZ, lidsky)
//   message: detailni vysvetleni
//   example: ukazka idealniho textu (volitelne)
//   fieldKey: konkretni cms_variables klic co opravit
//   sectionId: id sekce v page definici (pro auto-scroll)
export function analyzeSeo(pageDef, valuesMap) {
  const issues = []
  const stats = { titleLen: 0, descLen: 0, h1: '', bodyLen: 0, paragraphCount: 0 }

  // Najdi klicove pole — title, description, h1
  const titleKey = findFieldKey(pageDef, (f) =>
    /\.seo\.title$|\.seoTitle$|\.title$/i.test(f.key) &&
    !/\.process\.|\.faq\.|\.gear\.|\.steps\./i.test(f.key)
  ) || findFieldKey(pageDef, (f) => /title|titulek/i.test(f.label || ''))

  const descKey = findFieldKey(pageDef, (f) =>
    /\.seo\.description$|\.seoDescription$|\.description$/i.test(f.key)
  ) || findFieldKey(pageDef, (f) => /description|popisek|meta description/i.test(f.label || ''))

  const h1Key = findFieldKey(pageDef, (f) => /\.h1$/i.test(f.key))

  const title = (titleKey ? valuesMap[titleKey] : '') || ''
  const description = (descKey ? valuesMap[descKey] : '') || ''
  const h1 = (h1Key ? valuesMap[h1Key] : '') || ''

  stats.titleLen = title.length
  stats.descLen = description.length
  stats.h1 = h1

  // === TITLE ===
  if (!title) {
    issues.push({
      severity: 'critical',
      title: 'Chybí Titulek stránky',
      message: 'Toto je text, který se zobrazí v záložce prohlížeče a jako modrý nadpis ve výsledcích Googlu. Bez něj si Google sám vymyslí náhradu (často špatnou).',
      example: 'Půjčovna motorek Pelhřimov | MotoGo24',
      fieldKey: titleKey, sectionId: 'seo'
    })
  } else if (title.length < 30) {
    issues.push({
      severity: 'tip',
      title: `Titulek je krátký (${title.length} znaků)`,
      message: 'Ideální titulek má 45-65 znaků a obsahuje hlavní klíčové slovo + brand. Můžete doplnit více informací.',
      example: `${title} | MotoGo24 Pelhřimov`,
      fieldKey: titleKey, sectionId: 'seo'
    })
  } else if (title.length > 65) {
    issues.push({
      severity: 'important',
      title: `Titulek je dlouhý (${title.length} znaků)`,
      message: 'Google v záložce zobrazí maximálně 65 znaků. Cokoliv navíc se utne třemi tečkami. Zkraťte na to nejdůležitější.',
      example: 'Zkraťte na max 65 znaků — odeberte opakující se brand nebo redundantní slova',
      fieldKey: titleKey, sectionId: 'seo'
    })
  }

  // === META DESCRIPTION ===
  if (!description) {
    issues.push({
      severity: 'important',
      title: 'Chybí Popisek pro Google',
      message: 'Popisek (meta description) je 1-3 věty pod modrým nadpisem ve výsledcích vyhledávání. Říká uživateli proč na váš web kliknout. Bez něj si Google vymyslí ukázku z náhodného textu na stránce.',
      example: 'Půjčovna motorek na Vysočině – bez kauce, výbava v ceně, online rezervace. Cestovní, naked i dětské motorky. Otevřeno nonstop.',
      fieldKey: descKey, sectionId: 'seo'
    })
  } else if (description.length < 80) {
    issues.push({
      severity: 'tip',
      title: `Popisek je krátký (${description.length} znaků)`,
      message: 'Ideální délka popisku je 120-160 znaků. Můžete přidat detaily nebo výhody co zákazník ocení.',
      example: 'Doplňte výhody: "Bez kauce, výbava v ceně, online rezervace, otevřeno nonstop, Pelhřimov Vysočina."',
      fieldKey: descKey, sectionId: 'seo'
    })
  } else if (description.length > 160) {
    issues.push({
      severity: 'important',
      title: `Popisek je dlouhý (${description.length} znaků)`,
      message: 'Google zobrazí max ~160 znaků a zbytek utne. Zkraťte na nejdůležitější informace — co zákazník potřebuje vědět hned.',
      example: 'Zkraťte na max 160 znaků — odeberte výplňková slova nebo redundance.',
      fieldKey: descKey, sectionId: 'seo'
    })
  }

  // === H1 ===
  if (!h1) {
    issues.push({
      severity: 'critical',
      title: 'Chybí Hlavní nadpis (H1)',
      message: 'H1 je velký nadpis nahoře na stránce. Google ho používá pro pochopení o čem stránka je. Každá stránka musí mít právě jeden H1.',
      example: 'Půjčovna motorek Pelhřimov – bez kauce, výbava v ceně',
      fieldKey: h1Key, sectionId: 'intro'
    })
  } else if (h1.length < 10) {
    issues.push({
      severity: 'tip',
      title: `Hlavní nadpis je krátký (${h1.length} znaků)`,
      message: 'Krátký H1 jako "Motorky" nestačí. Doplňte kontext — lokalita, výhoda, klíčové slovo.',
      example: 'Místo "Motorky" → "Půjčovna motorek na Vysočině"',
      fieldKey: h1Key, sectionId: 'intro'
    })
  } else if (h1.length > 80) {
    issues.push({
      severity: 'tip',
      title: `Hlavní nadpis je dlouhý (${h1.length} znaků)`,
      message: 'Příliš dlouhý H1 zhoršuje čitelnost. Zkraťte na 40-70 znaků s hlavními klíčovými slovy.',
      example: 'Zkraťte odeberte vedlejší informace, nechte hlavní téma + lokalitu',
      fieldKey: h1Key, sectionId: 'intro'
    })
  }

  // Title vs H1 — měly by být odlišné
  if (title && h1 && title.toLowerCase().trim() === h1.toLowerCase().trim()) {
    issues.push({
      severity: 'tip',
      title: 'Titulek a Hlavní nadpis jsou totožné',
      message: 'Titulek (záložka prohlížeče) a H1 (nadpis na stránce) by měly být ODLIŠNÉ. Titulek je pro Google, H1 pro lidi co už jsou na stránce.',
      example: 'Titulek: "Půjčovna motorek Pelhřimov | MotoGo24" / H1: "Vyber si motorku na pondělí ráno"',
      fieldKey: h1Key, sectionId: 'intro'
    })
  }

  // === BODY CONTENT ===
  const bodyTexts = []
  pageDef.sections?.forEach(section => {
    section.fields?.forEach(f => {
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
      issues.push({
        severity: 'important',
        title: `Velmi málo textu na stránce (${wordCount} slov)`,
        message: 'Google upřednostňuje stránky s 500+ slovy obsahu. Krátké stránky obtížně rankují. Doplňte popis služby, časté dotazy, výhody, postup, místní lokality.',
        example: 'Přidejte sekce: "Co dostanete v ceně", "Jak probíhá rezervace", "Kde nás najdete", FAQ s 3-5 otázkami.',
        fieldKey: null, sectionId: null
      })
    } else if (wordCount < 500) {
      issues.push({
        severity: 'tip',
        title: `Méně textu na stránce (${wordCount} slov)`,
        message: 'Ideál je 500+ slov pro dobrý SEO ranking. Můžete doplnit detaily, sekce s tipy nebo FAQ.',
        example: 'Doplňte 1-2 sekce — popis služby, výhody, často kladené dotazy.',
        fieldKey: null, sectionId: null
      })
    }
    if (paragraphCount > 0 && paragraphCount < 3) {
      issues.push({
        severity: 'tip',
        title: `Málo odstavců (${paragraphCount})`,
        message: 'Strukturovaný text je lépe čitelný. Rozdělte text do 3+ odstavců s podnadpisy.',
        example: 'Použijte: úvod → výhody → postup → FAQ → závěr s CTA',
        fieldKey: null, sectionId: null
      })
    }
  }

  // === H1 keywords v body ===
  if (h1 && bodyClean) {
    const h1Words = h1.toLowerCase().split(/\s+/).filter(w => w.length > 3 && !/^(jak|si|na|do|že|pro|bez|nebo|kdo|kde|nebo|mez|tom)$/i.test(w))
    const bodyLower = bodyClean.toLowerCase()
    const missing = h1Words.filter(w => !bodyLower.includes(w))
    if (missing.length > 0 && missing.length === h1Words.length) {
      issues.push({
        severity: 'important',
        title: 'Klíčová slova z Hlavního nadpisu nejsou v textu stránky',
        message: `H1 obsahuje slova "${missing.join(', ')}", ale v body textu nikde nejsou. Google čeká že o těchto slovech budete psát. Doplňte je do hlavního textu.`,
        example: `Vmíchejte slova "${missing.slice(0, 3).join('", "')}" přirozeně do prvních 1-2 odstavců textu.`,
        fieldKey: null, sectionId: null
      })
    } else if (missing.length > 0) {
      issues.push({
        severity: 'tip',
        title: `Některá slova z H1 nejsou v textu`,
        message: `Slova "${missing.join(', ')}" jsou v H1 ale nikde dál v textu. Pro lepší ranking je vmíchejte do popisu stránky.`,
        example: `Použijte slova "${missing.slice(0, 3).join('", "')}" v 1-2 dalších větách na stránce.`,
        fieldKey: null, sectionId: null
      })
    }
  }

  // Score: 100 - (25 critical, 12 important, 4 tip per issue), min 0, max 100
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
