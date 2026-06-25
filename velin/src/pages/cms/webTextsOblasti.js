// Texty webu: Oblasti (rozcestník krajů + krajské landing stránky)
//
// Klíče odpovídají schématu, které čte PHP přes `siteContent('oblasti')`
// (motogo-web-php/pages/oblasti.php a oblasti-detail.php):
//   - přehled /oblasti:        web.oblasti.{hero,regionsTitle,citiesLabel,regionCta,cta,seo}.*
//   - kraj   /oblasti/<slug>:  web.oblasti.region.<slug>.*  (přepíše šablonu JEN pro daný kraj)
//
// POZOR: v klíči kraje jsou pomlčky nahrazeny podtržítky
// (jihomoravsky-kraj → jihomoravsky_kraj), protože cms-save edge funkce
// (KEY_RE) povoluje v klíči jen [a-zA-Z0-9_]. PHP (oblasti-detail.php) dělá
// stejnou náhradu, takže klíče sedí.

export const PAGE_OBLASTI = {
  id: 'oblasti', label: 'Oblasti (přehled krajů)', icon: '📍', url: '/oblasti',
  description: 'Rozcestník krajů — karty s výpisem měst. Cílí na SEO „motopůjčovna {město}".',
  sections: [
    {
      id: 'hero', label: 'Úvod / hero', location: 'Hlavní nadpis a úvodní text nahoře',
      fields: [
        { key: 'web.oblasti.hero.h1', label: 'H1 nadpis', default: 'Motopůjčovna ve vašem kraji a městě' },
        { key: 'web.oblasti.hero.intro', label: 'Úvodní text', type: 'textarea', default: 'Hledáte <strong>půjčovnu motorek</strong> ve svém okolí? MotoGo24 přistaví a doručí motorku do měst po celé České republice. Vyberte si svůj kraj a podívejte se, kam všude motorku přivezeme – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a kompletní výbavou v ceně.' },
      ]
    },
    {
      id: 'regions', label: 'Karty krajů', location: 'Nadpis a popisky karet krajů',
      fields: [
        { key: 'web.oblasti.regionsTitle', label: 'Nadpis sekce krajů', default: 'Vyberte si kraj' },
        { key: 'web.oblasti.citiesLabel', label: 'Popisek nad výčtem měst', default: 'Půjčovna motorek ve městech:' },
        { key: 'web.oblasti.regionCta', label: 'Tlačítko na kartě kraje', default: 'Zobrazit kraj' },
      ]
    },
    {
      id: 'cta', label: 'CTA sekce', location: 'Závěrečná výzva k akci',
      fields: [
        { key: 'web.oblasti.cta.title', label: 'Nadpis', default: 'Nenašli jste své město?' },
        { key: 'web.oblasti.cta.text', label: 'Text', type: 'textarea', default: 'Motorku přistavíme prakticky kamkoliv v ČR. Napište nám nebo rovnou rezervujte online.' },
        { key: 'web.oblasti.cta.buttons.0.label', label: 'Tlačítko 1', default: 'REZERVOVAT MOTORKU' },
        { key: 'web.oblasti.cta.buttons.1.label', label: 'Tlačítko 2', default: 'Kontaktujte nás' },
      ]
    },
    {
      id: 'seo_meta', label: 'SEO (meta v hlavičce – Google)', location: 'Neviditelné — titulek a popisek ve výsledcích vyhledávání',
      fields: [
        { key: 'web.oblasti.seo.title', label: 'Meta title', default: 'Oblasti – motopůjčovna v krajích a městech ČR | MotoGo24' },
        { key: 'web.oblasti.seo.description', label: 'Meta description', type: 'textarea', default: 'Motopůjčovna MotoGo24 přiveze a přistaví motorku do měst po celé ČR. Vyberte si svůj kraj a město – půjčovna motorek bez kauce, s online rezervací a výbavou v ceně.' },
        { key: 'web.oblasti.seo.keywords', label: 'Meta keywords', type: 'textarea', default: 'motopůjčovna, půjčovna motorek, motopůjčovna podle města, pronájem motorek, motorka bez kauce, MotoGo24' },
      ]
    },
  ]
}

// Sestaví Velín stránku pro jeden kraj. `cmsSlug` má podtržítka (klíč),
// `url` má pomlčky (veřejná adresa). Defaulty = český text se substituovaným
// krajem (admin vidí výchozí znění, může přepsat jen pro tento kraj).
function regionPage({ id, label, url, cmsSlug, seoName, regionLoc }) {
  const sub = (s) => s.split('{region}').join(seoName).split('{regionLoc}').join(regionLoc)
  const k = (f) => `web.oblasti.region.${cmsSlug}.${f}`
  return {
    id, label, icon: '🗺️', url,
    description: `Krajská landing stránka. Uložené texty přepíšou společnou šablonu JEN pro kraj ${seoName}.`,
    sections: [
      {
        id: 'hero', label: 'Hero banner', location: 'Banner s obrázkem nahoře',
        fields: [
          { key: k('heroTagline'), label: 'Text v banneru', type: 'textarea', default: sub('Půjčte si motorku {regionLoc} – bez kauce, s výbavou v ceně a nonstop převzetím.') },
          { key: k('heroCta'), label: 'Tlačítko v banneru', default: 'REZERVOVAT MOTORKU' },
        ]
      },
      {
        id: 'intro', label: 'Úvod o kraji', location: 'H1 nadpis a úvodní odstavec',
        fields: [
          { key: k('h1'), label: 'H1 nadpis', default: sub('Motopůjčovna {region}') },
          { key: k('intro'), label: 'Úvodní text', type: 'textarea', default: sub('Hledáte spolehlivou <strong>motopůjčovnu {regionLoc}</strong>? MotoGo24 vám přiveze a přistaví motorku přímo do vašeho města. Nabízíme <strong>pronájem motorek bez kauce</strong>, online rezervaci a kompletní motorkářskou výbavu v ceně. Ať bydlíte ve velkém městě, nebo menší obci, motorku vám rádi doručíme na domluvené místo a po skončení pronájmu si ji opět vyzvedneme.') },
        ]
      },
      {
        id: 'cities', label: 'Města kraje', location: 'Sekce s výčtem měst (text, ne karty)',
        fields: [
          { key: k('citiesTitle'), label: 'Nadpis sekce měst', default: 'Kam motorku přivezeme' },
          { key: k('citiesIntro'), label: 'Text nad výčtem měst', type: 'textarea', default: sub('Motorku přistavíme i vrátíme {regionLoc} – například ve městech a jejich okolí:') },
        ]
      },
      {
        id: 'cta', label: 'CTA sekce', location: 'Závěrečná výzva k akci',
        fields: [
          { key: k('ctaTitle'), label: 'CTA nadpis', default: sub('Rezervujte si motorku {regionLoc}') },
          { key: k('ctaText'), label: 'CTA text', type: 'textarea', default: 'Vyberte si stroj, zvolte termín a my vám motorku přivezeme. Půjčovna MotoGo24 je otevřená nonstop.' },
        ]
      },
    ]
  }
}

export const PAGE_OBLASTI_VYSOCINA = regionPage({
  id: 'oblasti_vysocina', label: 'Oblasti — Kraj Vysočina', url: '/oblasti/vysocina',
  cmsSlug: 'vysocina', seoName: 'Vysočina', regionLoc: 'na Vysočině',
})
export const PAGE_OBLASTI_JIHOMORAVSKY = regionPage({
  id: 'oblasti_jihomoravsky', label: 'Oblasti — Jihomoravský kraj', url: '/oblasti/jihomoravsky-kraj',
  cmsSlug: 'jihomoravsky_kraj', seoName: 'Jihomoravský kraj', regionLoc: 'v Jihomoravském kraji',
})
export const PAGE_OBLASTI_JIHOCESKY = regionPage({
  id: 'oblasti_jihocesky', label: 'Oblasti — Jihočeský kraj', url: '/oblasti/jihocesky-kraj',
  cmsSlug: 'jihocesky_kraj', seoName: 'Jihočeský kraj', regionLoc: 'v Jihočeském kraji',
})
