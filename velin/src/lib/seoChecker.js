// SEO checker — analyzuje CMS texty per-stránka pro lidsky srozumitelné issues.
//
// Pro KAŽDÝ issue vrací:
//   severity, title, message, example, fieldKey, sectionId
// fieldKey + sectionId vycházejí z REÁLNÉ struktury webTexts*.js stránky
// (ne natvrdo hardcoded), takže auto-scroll vždy najde to pole.

// Najde field a jeho sekci v page definici podle predikátu.
// Vrací { fieldKey, sectionId } nebo null pokud nenalezeno.
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

// Najde Title field (seo.title) — typicky existuje jen pro hlavní stránky
function findTitleField(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.seo\.title$|\.seoTitle$/i.test(f.key) ||
    /title.*titulek.*záložky|seo.*title/i.test((f.label || '').toLowerCase())
  )
}

// Najde Description field (seo.description / meta description)
function findDescField(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.seo\.description$|\.seoDescription$/i.test(f.key) ||
    /meta description|seo.*description|popisek.*google/i.test((f.label || '').toLowerCase())
  )
}

// Najde H1 field
function findH1Field(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.h1$|\.h1\.text$/i.test(f.key) ||
    /^h1\b|h1.*nadpis/i.test((f.label || '').toLowerCase())
  )
}

// Najde první body text field (intro, intro_p1, intro.body, atd.)
// Pro issues kde není konkrétní pole (málo slov, klíčová slova mismatch),
// otevřeme intro sekci aby admin mohl rozšířit obsah.
function findIntroField(pageDef) {
  return findFieldWithSection(pageDef, (f) =>
    /\.intro$|\.intro_p1$|\.intro\.body$|\.intro\.text$/i.test(f.key) ||
    /úvodní.*text|intro|úvod/i.test((f.label || '').toLowerCase())
  )
}

export function analyzeSeo(pageDef, valuesMap) {
  const issues = []
  const stats = { titleLen: 0, descLen: 0, h1: '', bodyLen: 0, paragraphCount: 0 }

  const titleField = findTitleField(pageDef)
  const descField = findDescField(pageDef)
  const h1Field = findH1Field(pageDef)
  const introField = findIntroField(pageDef)

  const title = (titleField && valuesMap[titleField.fieldKey]) || ''
  const description = (descField && valuesMap[descField.fieldKey]) || ''
  const h1 = (h1Field && valuesMap[h1Field.fieldKey]) || ''

  stats.titleLen = title.length
  stats.descLen = description.length
  stats.h1 = h1

  // === TITLE ===
  // Pokud stránka NEMÁ seo.title field v CMS, je v PHP — adminu jasně řekneme
  if (!titleField) {
    // Title pro tuto stránku není editovatelný z CMS — preskoč issue
  } else if (!title) {
    issues.push({
      severity: 'critical',
      title: 'Chybí Titulek stránky',
      message: 'Toto je text, který se zobrazí v záložce prohlížeče a jako modrý nadpis ve výsledcích Googlu. Bez něj si Google vymyslí náhradu (často špatnou). Klikni Opravit → otevře se přesné pole "Title".',
      example: 'Půjčovna motorek Pelhřimov | MotoGo24',
      ...titleField,
    })
  } else if (title.length < 30) {
    issues.push({
      severity: 'tip',
      title: `Titulek je krátký (${title.length} znaků, ideál 45-65)`,
      message: `Ideální Titulek (Title) má 45-65 znaků a obsahuje hlavní klíčové slovo + brand. Aktuálně je krátký — doplň lokalitu nebo hlavní výhodu.`,
      example: `"${title} | MotoGo24 Pelhřimov" nebo "${title} – bez kauce | MotoGo24"`,
      ...titleField,
    })
  } else if (title.length > 65) {
    issues.push({
      severity: 'important',
      title: `Titulek je dlouhý (${title.length} znaků, max 65)`,
      message: `Google v záložce zobrazí maximálně 65 znaků. Cokoliv navíc se utne třemi tečkami. Zkrať na 45-65 znaků s tím nejdůležitějším vepředu.`,
      example: 'Nech jen klíčové slovo + lokalitu + brand. Odstraň výplňková slova jako "v půjčovně", "naše", "nabídka", atd.',
      ...titleField,
    })
  }

  // === META DESCRIPTION ===
  if (!descField) {
    // Description není v CMS — řízeno z PHP
  } else if (!description) {
    issues.push({
      severity: 'important',
      title: 'Chybí Popisek pro Google (meta description)',
      message: 'Popisek je 1-3 věty pod modrým nadpisem ve výsledcích Googlu. Říká uživateli proč na váš web kliknout. Bez něj si Google vymyslí ukázku z náhodného textu na stránce. Klikni Opravit → otevře se přesné pole "Meta description".',
      example: 'Půjčovna motorek na Vysočině – bez kauce, výbava v ceně, online rezervace. Cestovní, naked i dětské motorky. Otevřeno nonstop.',
      ...descField,
    })
  } else if (description.length < 80) {
    issues.push({
      severity: 'tip',
      title: `Popisek je krátký (${description.length} znaků, ideál 120-160)`,
      message: 'Ideální Popisek má 120-160 znaků. Doplň výhody co zákazník ocení (bez kauce, výbava v ceně, online rezervace, lokalita).',
      example: 'Aktuální: "' + description.substring(0, 50) + '..."' + '\nDoporučeno: doplnit "Bez kauce, výbava v ceně, online rezervace, Pelhřimov Vysočina."',
      ...descField,
    })
  } else if (description.length > 160) {
    issues.push({
      severity: 'important',
      title: `Popisek je dlouhý (${description.length} znaků, max 160)`,
      message: 'Google zobrazí max ~160 znaků a zbytek utne. Zkrať na 120-160 znaků — nech nejdůležitější informace co zákazník potřebuje hned.',
      example: 'Odstraň druhou polovinu věty nebo redundantní slova. Drž se 1-2 vět s konkrétní hodnotou.',
      ...descField,
    })
  }

  // === H1 ===
  if (!h1Field) {
    // Strange: page bez H1 field. Skip.
  } else if (!h1) {
    issues.push({
      severity: 'critical',
      title: 'Chybí Hlavní nadpis (H1)',
      message: 'H1 je velký nadpis nahoře na stránce. Google ho používá pro pochopení o čem stránka je. Každá stránka musí mít právě jeden H1. Klikni Opravit → otevře se přesné pole "H1 nadpis".',
      example: 'Půjčovna motorek Pelhřimov – bez kauce, výbava v ceně',
      ...h1Field,
    })
  } else if (h1.length < 10) {
    issues.push({
      severity: 'tip',
      title: `Hlavní nadpis je krátký (${h1.length} znaků)`,
      message: 'Krátký H1 jako "Motorky" nestačí. Doplň kontext — lokalitu, výhodu, klíčové slovo.',
      example: 'Místo "Motorky" → "Půjčovna motorek na Vysočině"',
      ...h1Field,
    })
  } else if (h1.length > 80) {
    issues.push({
      severity: 'tip',
      title: `Hlavní nadpis je dlouhý (${h1.length} znaků)`,
      message: 'Příliš dlouhý H1 zhoršuje čitelnost. Zkrať na 40-70 znaků s hlavními klíčovými slovy.',
      example: 'Odeber vedlejší informace, nech hlavní téma + lokalitu + jednu výhodu',
      ...h1Field,
    })
  }

  // Title vs H1 — měly by být odlišné
  if (titleField && h1Field && title && h1 && title.toLowerCase().trim() === h1.toLowerCase().trim()) {
    issues.push({
      severity: 'tip',
      title: 'Titulek a Hlavní nadpis jsou totožné',
      message: 'Titulek (záložka prohlížeče) a H1 (nadpis na stránce) by měly být ODLIŠNÉ. Titulek je pro Google + záložku, H1 pro lidi co už jsou na stránce. Klikni Opravit → otevře se H1 pole, změň ho aby se lišil od titulku.',
      example: `Aktuálně oba: "${title}"\nDoporučeno H1: "Vyber si motorku na Vysočině – bez kauce"`,
      ...h1Field,
    })
  }

  // === BODY CONTENT — vsechny issues smeruji do intro/body sekce ===
  const bodyTexts = []
  pageDef.sections?.forEach(section => {
    section.fields?.forEach(f => {
      if (titleField && f.key === titleField.fieldKey) return
      if (descField && f.key === descField.fieldKey) return
      if (h1Field && f.key === h1Field.fieldKey) return
      if (/\.(label|btn|cta|aria|alt|placeholder|href|icon|img|image|map_src|map_title|empty)$/i.test(f.key)) return
      const v = valuesMap[f.key]
      if (typeof v === 'string' && v.trim().length > 30) bodyTexts.push(v)
    })
  })
  const bodyClean = bodyTexts.join(' ').replace(/<[^>]*>/g, ' ').replace(/&[a-z]+;/gi, ' ')
  const wordCount = bodyClean.trim().split(/\s+/).filter(Boolean).length
  const paragraphCount = bodyTexts.filter(t => t.length > 100).length

  stats.bodyLen = wordCount
  stats.paragraphCount = paragraphCount

  // Body issues — všechny smerujou na introField (existuje na vsech strankach)
  const bodyTarget = introField || h1Field || { fieldKey: null, sectionId: null }

  if (wordCount > 0) {
    if (wordCount < 200) {
      issues.push({
        severity: 'important',
        title: `Velmi málo textu (${wordCount} slov, doporučeno 500+)`,
        message: 'Google upřednostňuje stránky s 500+ slovy. Krátké stránky obtížně rankují. Klikni Opravit → otevře se "Úvodní text" — doplň zde sekci s detaily, postupem nebo FAQ.',
        example: 'Přidej sekce: "Co dostanete v ceně", "Jak probíhá rezervace", "Kde nás najdete", FAQ s 3-5 otázkami.',
        ...bodyTarget,
      })
    } else if (wordCount < 500) {
      issues.push({
        severity: 'tip',
        title: `Méně textu (${wordCount} slov, doporučeno 500+)`,
        message: 'Ideál je 500+ slov. Klikni Opravit → rozšiř "Úvodní text" nebo navazující sekce.',
        example: 'Doplň 1-2 sekce o specifických výhodách, postupu nebo často kladených dotazech.',
        ...bodyTarget,
      })
    }
    if (paragraphCount > 0 && paragraphCount < 3) {
      issues.push({
        severity: 'tip',
        title: `Málo odstavců (${paragraphCount}, doporučeno 3+)`,
        message: 'Strukturovaný text je čitelnější. Rozděl text do 3+ odstavců s podnadpisy. Klikni Opravit → otevře se hlavní text.',
        example: 'Struktura: úvod → výhody → postup → FAQ → závěr s CTA',
        ...bodyTarget,
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
        title: 'Klíčová slova z H1 nejsou v textu stránky',
        message: `H1 obsahuje slova "${missing.join(', ')}", ale v body textu nikde nejsou. Google čeká že o těchto slovech budete psát. Klikni Opravit → otevře se "Úvodní text", vmíchej tato slova přirozeně do prvních vět.`,
        example: `Aktuální H1: "${h1}"\nDoplň v body textu věty obsahující slova: ${missing.slice(0, 5).join(', ')}.`,
        ...bodyTarget,
      })
    } else if (missing.length > 0) {
      issues.push({
        severity: 'tip',
        title: `Některá slova z H1 chybí v textu: ${missing.slice(0, 3).join(', ')}`,
        message: `Pro lepší ranking vmíchej tato slova do popisu stránky.`,
        example: `Použij slova "${missing.slice(0, 3).join('", "')}" v 1-2 dalších větách na stránce.`,
        ...bodyTarget,
      })
    }
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
