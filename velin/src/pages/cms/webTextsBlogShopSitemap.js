// Texty webu: Blog (rozcestník), E-shop (rozcestník), Mapa stránek
// Tyto stránky mají DB-driven obsah (články, produkty, odkazy) — editovatelná je
// pouze úvodní/závěrečná textová sekce, která se přidává jako SEO doplněk.

export const PAGE_BLOG = {
  id: 'blog', label: 'Blog (rozcestník)', icon: '✍️', url: '/blog',
  description: 'Výpis článků blogu s tagy. Editovatelná závěrečná textová sekce pod gridem článků.',
  sections: [
    {
      id: 'outro', label: 'Sekce pod výpisem článků', location: 'H2 + 2 odstavce pod gridem článků — SEO obsah a vysvětlení blogu.',
      fields: [
        { key: 'web.blog.outro.title', label: 'H2 nadpis', default: 'O našem blogu' },
        { key: 'web.blog.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'Na blogu MotoGo24 najdete tipy pro motorkáře, recenze našich strojů, rady jak si vybrat <strong>správnou motorku k pronájmu</strong> a inspiraci na trasy po Vysočině i celé České republice. Pravidelně přidáváme články o dárkových poukazech, údržbě motorek i o tom, jak <strong>půjčit motorku bez kauce</strong> a co všechno je v ceně nájmu zahrnuto.' },
        { key: 'web.blog.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: 'Pokud hledáte praktické informace o mototuristice, výbavě nebo o tom, jak to funguje v naší půjčovně, jste na správném místě. Máte téma, které by vás zajímalo? <a href="/kontakt">Napište nám</a> a rádi se mu věnujeme v dalším článku.' },
      ]
    },
  ]
}

export const PAGE_ESHOP = {
  id: 'eshop', label: 'E-shop (rozcestník)', icon: '🛒', url: '/eshop',
  description: 'Výpis produktů e-shopu. Editovatelná závěrečná textová sekce pod produkty.',
  sections: [
    {
      id: 'outro', label: 'Sekce pod výpisem produktů', location: 'H2 + 2 odstavce pod gridem produktů — SEO obsah a vysvětlení e-shopu.',
      fields: [
        { key: 'web.eshop.outro.title', label: 'H2 nadpis', default: 'Motorkářské doplňky pro každého jezdce' },
        { key: 'web.eshop.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'V e-shopu MotoGo24 najdete <strong>motorkářské doplňky</strong>, oblečení a merchandise, který se hodí na cesty i do města. Sortiment průběžně doplňujeme — od trik, čepic a kuklí přes reflexní prvky až po praktické drobnosti, které využijete při každé jízdě. Většinu zboží máme skladem v půjčovně v Pelhřimově a expedujeme do druhého pracovního dne.' },
        { key: 'web.eshop.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: 'Doručujeme po celé České republice — můžete si vybrat <strong>osobní vyzvednutí v půjčovně</strong>, doručení Zásilkovnou nebo Českou poštou. Platba probíhá online přes platební bránu. Pokud něco hledáte a v nabídce to nevidíte, ozvěte se nám telefonicky nebo e-mailem — rádi poradíme s výběrem nebo doporučíme alternativu.' },
      ]
    },
  ]
}

export const PAGE_MAPA_STRANEK = {
  id: 'mapa-stranek', label: 'Mapa stránek', icon: '🗺️', url: '/mapa-stranek',
  description: 'Mapa všech stránek webu s odkazy. Editovatelný úvodní odstavec a závěrečná textová sekce.',
  sections: [
    {
      id: 'intro', label: 'Úvodní odstavec', location: 'Pod H1 „Mapa stránek" před výpisem odkazů.',
      fields: [
        { key: 'web.mapa_stranek.intro', label: 'Úvodní text (HTML)', type: 'textarea', default: 'Tato mapa stránek slouží jako přehled <strong>celého webu MotoGo24</strong> — najdete tu odkazy na katalog motorek k pronájmu, postup půjčení krok za krokem, ceník, dárkové poukazy, blog s tipy pro motorkáře, e-shop s motorkářskými doplňky i právní dokumenty.' },
      ]
    },
    {
      id: 'outro', label: 'Sekce pod výpisem odkazů', location: 'H2 + 2 odstavce dole pod seznamem všech stránek.',
      fields: [
        { key: 'web.mapa_stranek.outro.title', label: 'H2 nadpis', default: 'Hledáte něco konkrétního?' },
        { key: 'web.mapa_stranek.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'Pokud nemůžete najít to, co hledáte, zkuste začít na <strong>domovské stránce</strong> nebo si projděte sekci <a href="/jak-pujcit">Jak si půjčit motorku</a>, kde jsou všechny informace ke způsobu rezervace, převzetí, vrácení i co je v ceně nájmu. Pro rychlou orientaci nabízíme také <a href="/jak-pujcit/faq">časté dotazy</a> a podrobný popis u každé motorky v <a href="/katalog">katalogu</a>.' },
        { key: 'web.mapa_stranek.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: 'Stále se neorientujete? Ozvěte se nám telefonicky, e-mailem nebo přes naše sociální sítě — najdete je v sekci <a href="/kontakt">Kontakt</a>. Jsme dostupní nonstop a rádi poradíme s výběrem motorky, termínem nebo s objednávkou dárkového poukazu.' },
      ]
    },
  ]
}
