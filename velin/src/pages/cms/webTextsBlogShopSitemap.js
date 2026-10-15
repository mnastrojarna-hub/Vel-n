// Texty webu: Blog (rozcestník), E-shop (rozcestník), Mapa stránek
// Tyto stránky mají DB-driven obsah (články, produkty, odkazy) — editovatelná je
// pouze úvodní/závěrečná textová sekce, která se přidává jako SEO doplněk.

export const PAGE_BLOG = {
  id: 'blog-landing', label: 'Blog (rozcestník)', icon: '✍️', url: '/blog',
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

// Sdílené SEO outro sekce pro DYNAMICKÉ detail-stránky (jeden výskyt na všechny
// detail produkty / motorky / dokumenty). Vlastní obsah (popis produktu / motorky)
// se edituje v sekci Produkty / Fleet / Dokumenty Velína.

export const PAGE_ESHOP_DETAIL = {
  id: 'eshop-detail', label: 'E-shop — detail produktu', icon: '🛍️', url: '/eshop/{id}',
  description: 'Sdílená SEO sekce zobrazená pod každým produktem v e-shopu. Vlastní popis produktu se edituje v sekci Produkty.',
  sections: [
    {
      id: 'outro', label: 'Společná SEO sekce pod produktem', location: 'H2 + 2 odstavce pod popisem produktu — stejné pro všechny produkty.',
      fields: [
        { key: 'web.eshop_detail.outro.title', label: 'H2 nadpis', default: 'Nákup motorkářských doplňků u MotoGo24' },
        { key: 'web.eshop_detail.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'V e-shopu MotoGo24 najdete pečlivě vybrané <strong>motorkářské oblečení a doplňky</strong> v běžných i atypických velikostech. Sortiment doplňujeme podle potřeb našich zákazníků z půjčovny i pravidelných jezdců, kteří chtějí drobnosti od trika přes čepici až po reflexní kuklu pod helmu. Vše máme fyzicky skladem v půjčovně v Pelhřimově — můžete přijít, vyzkoušet velikost a odvézt si zboží na místě.' },
        { key: 'web.eshop_detail.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: 'Doručujeme po celé České republice — můžete si vybrat <strong>osobní vyzvednutí v půjčovně zdarma</strong>, doručení Zásilkovnou nebo Českou poštou. Po objednání obdržíte automatický potvrzovací e-mail a my zboží odešleme do druhého pracovního dne. Pokud něco potřebujete poradit (velikost, materiál, kombinace s motorkářskou výbavou), ozvěte se nám — odpovíme zpravidla do hodiny.' },
      ]
    },
  ]
}

export const PAGE_KATALOG_DETAIL = {
  id: 'katalog-detail', label: 'Katalog — detail motorky', icon: '🏍️', url: '/katalog/{id}',
  description: 'Sdílená SEO sekce zobrazená pod každou motorkou v katalogu. Vlastní popis motorky se edituje v sekci Fleet.',
  sections: [
    {
      id: 'outro', label: 'Společná SEO sekce pod motorkou', location: 'H2 + 2 odstavce pod parametry motorky a ceníkem — stejné pro všechny motorky.',
      fields: [
        { key: 'web.katalog_detail.outro.title', label: 'H2 nadpis', default: 'Půjčení motorky bez obav a stresu' },
        { key: 'web.katalog_detail.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'Všechny motorky v naší flotile pečlivě udržujeme — pravidelný servis, kontrola pneumatik, brzd a celkového stavu stroje jsou samozřejmost. Před každým vyzvednutím motorku připravíme, prohlédneme její stav, vyfotíme a vystavíme předávací protokol.<br>Motocykly půjčujeme <strong>bez kauce (i při první rezervaci)</strong> a check-in si uděláš jednoduše <strong>online</strong> sám/sama z pohodlí domova. <strong>Rezervaci můžeš i po zaplacení dál spravovat.</strong> Potřebuješ změnit termín? Vyměnit motorku? Prodloužit výpůjčku? Není problém. Úpravy můžeš provádět opakovaně na webu v sekci <strong>Upravit rezervaci</strong> nebo ve své <strong>aplikaci</strong> MotoGo24 — a to dokonce 1 den před výpůjčkou dle VOP.' },
        { key: 'web.katalog_detail.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: '<strong>S našimi motorkami můžeš bez obav vyrazit do zahraničí — i mimo EU!</strong> Stačí se řídit pokyny v zelené kartě. <strong>Neomezujeme ani najeté kilometry</strong>, takže nemusíš mít strach z doplatků za překročené limity — u nás žádné nenajdeš.<br>Pokud bys cestou narazil/a na jakýkoliv problém, jednoduše nás kontaktuj. <strong>Pro naše zákazníky jsme na telefonu k dispozici 24/7.</strong>' },
      ]
    },
  ]
}

export const PAGE_DOKUMENTY_DETAIL = {
  id: 'dokumenty-detail', label: 'Dokumenty — detail', icon: '📄', url: '/dokumenty/{slug}',
  description: 'Sdílená SEO sekce zobrazená pod každým dokumentem. Vlastní obsah dokumentu se edituje v sekci Dokumenty.',
  sections: [
    {
      id: 'outro', label: 'Společná SEO sekce pod dokumentem', location: 'H2 + 2 odstavce pod obsahem dokumentu — stejné pro všechny dokumenty.',
      fields: [
        { key: 'web.dokumenty_detail.outro.title', label: 'H2 nadpis', default: 'O našich dokumentech' },
        { key: 'web.dokumenty_detail.outro.body1', label: '1. odstavec (HTML)', type: 'textarea', default: 'Všechny smluvní dokumenty a protokoly MotoGo24 jsou vždy <strong>aktuální verze</strong> — pravidelně je revidujeme s ohledem na změny v legislativě a zpětnou vazbu zákazníků. Najdete je v textové i tištěné podobě, můžete si je stáhnout ve formátu PDF a vytisknout, nebo si je prohlédnout přímo zde na webu. Plné znění obchodních podmínek, smlouvy o pronájmu a zásad ochrany osobních údajů máme dostupné v sekci <a href="/jak-pujcit/dokumenty">Dokumenty a návody</a>.' },
        { key: 'web.dokumenty_detail.outro.body2', label: '2. odstavec (HTML)', type: 'textarea', default: 'Pokud máte jakýkoli dotaz ke smluvním podmínkám, postupu při převzetí nebo vrácení motorky či k pojištění, neváhejte nás kontaktovat. Naše smlouvy záměrně píšeme tak, aby byly <strong>srozumitelné</strong> — bez drobného písma a skrytých podmínek. Pokud chcete dokumenty fyzicky podepsat předem nebo si je s námi projít osobně, můžete přijet do půjčovny v Pelhřimově nebo si je necháme připravit k vyzvednutí.' },
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
