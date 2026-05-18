// Texty webu: Půjčovna motorek + Jak si půjčit (overview)
//
// Klíče odpovídají vnořenému schématu, které čte PHP šablona
// `motogo-web-php/pages/pujcovna.php` přes `siteContent('pujcovna', $defaults)`.
// Velín tedy ukládá rovnou do těch řádků, které web reálně renderuje
// (žádný flat→nested mezikrok, žádná závislost na DB triggeru).
export const PAGE_PUJCOVNA = {
  id: 'pujcovna', label: 'Půjčovna motorek', icon: '🏍️', url: '/pujcovna-motorek',
  description: 'Hlavní prezentační stránka půjčovny s výhodami, kroky a FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'Hlavní nadpis a úvodní odstavec',
      fields: [
        { key: 'web.pujcovna.intro.h1', label: 'H1 nadpis', default: 'Půjčovna motorek Vysočina Motogo24' },
        { key: 'web.pujcovna.intro.body', label: 'Úvodní text', type: 'textarea', default: 'Naše <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.' },
      ]
    },
    {
      id: 'benefits', label: 'Výhody (6 boxů)', location: 'Sekce „Proč si půjčit motorku u nás" – 6 ikon',
      fields: [
        { key: 'web.pujcovna.benefits.title', label: 'Nadpis sekce', default: 'Proč si půjčit motorku u nás' },
        { key: 'web.pujcovna.benefits.items.0.title', label: 'Box 1 – nadpis', default: 'Bez kauce' },
        { key: 'web.pujcovna.benefits.items.0.text', label: 'Box 1 – popis', default: 'a bez skrytých poplatků' },
        { key: 'web.pujcovna.benefits.items.1.title', label: 'Box 2 – nadpis', default: 'Online rezervace' },
        { key: 'web.pujcovna.benefits.items.1.text', label: 'Box 2 – popis', default: 'na pár kliknutí' },
        { key: 'web.pujcovna.benefits.items.2.title', label: 'Box 3 – nadpis', default: 'Výbava pro řidiče v ceně' },
        { key: 'web.pujcovna.benefits.items.2.text', label: 'Box 3 – popis', default: 'helma, bunda, kalhoty a rukavice' },
        { key: 'web.pujcovna.benefits.items.3.title', label: 'Box 4 – nadpis', default: 'Nonstop provoz' },
        { key: 'web.pujcovna.benefits.items.3.text', label: 'Box 4 – popis', default: 'pro vyzvednutí i vrácení dle rezervace' },
        { key: 'web.pujcovna.benefits.items.4.title', label: 'Box 5 – nadpis', default: 'Jsme v tom společně' },
        { key: 'web.pujcovna.benefits.items.4.text', label: 'Box 5 – popis', default: 'když se něco přihodí' },
        { key: 'web.pujcovna.benefits.items.5.title', label: 'Box 6 – nadpis', default: 'Přistavení i vrácení motorky' },
        { key: 'web.pujcovna.benefits.items.5.text', label: 'Box 6 – popis', default: 'na domluvené místo' },
        { key: 'web.pujcovna.benefits.closing', label: 'Text pod výhodami', type: 'textarea', default: 'Hledáte <strong>půjčovnu motorek na Vysočině</strong>? Motogo24 – <strong>půjčovna motorek na Vysočině</strong> – nabízí férové podmínky, jasný postup a špičkově udržované stroje pro výlety po ČR i do zahraničí.' },
        { key: 'web.pujcovna.benefits.buttons.0.label', label: 'Tlačítko 1', default: 'Zobrazit motorky k pronájmu' },
        { key: 'web.pujcovna.benefits.buttons.1.label', label: 'Tlačítko 2', default: 'REZERVOVAT' },
      ]
    },
    {
      id: 'process', label: 'Kroky půjčení (8 kroků)', location: 'Sekce „Jak probíhá půjčení" – 8 karet s ikonami',
      fields: [
        { key: 'web.pujcovna.process.title', label: 'Nadpis sekce', default: 'Jak probíhá půjčení motorky na Vysočině' },
        { key: 'web.pujcovna.process.steps.0.title', label: 'Krok 1 – nadpis', default: '1. Vyber motorku' },
        { key: 'web.pujcovna.process.steps.0.text', label: 'Krok 1 – popis', type: 'textarea', default: 'Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje, odpovídá tvým zkušenostem a řidičskému oprávnění.' },
        { key: 'web.pujcovna.process.steps.1.title', label: 'Krok 2 – nadpis', default: '2. Rezervuj online' },
        { key: 'web.pujcovna.process.steps.1.text', label: 'Krok 2 – popis', type: 'textarea', default: 'Uskutečni rezervaci podle data nebo podle konkrétní motorky, kterou si chceš půjčit.' },
        { key: 'web.pujcovna.process.steps.2.title', label: 'Krok 3 – nadpis', default: '3. Vyber výbavu' },
        { key: 'web.pujcovna.process.steps.2.text', label: 'Krok 3 – popis', type: 'textarea', default: 'Výbava pro řidiče je v ceně, pro spolujezdce za příplatek. Velikost si můžeš zvolit až na místě.' },
        { key: 'web.pujcovna.process.steps.3.title', label: 'Krok 4 – nadpis', default: '4. Zaplať' },
        { key: 'web.pujcovna.process.steps.3.text', label: 'Krok 4 – popis', type: 'textarea', default: 'Zaplať jednoduše online prostřednictvím platební brány.' },
        { key: 'web.pujcovna.process.steps.4.title', label: 'Krok 5 – nadpis', default: '5. Převezmi motorku' },
        { key: 'web.pujcovna.process.steps.4.text', label: 'Krok 5 – popis', type: 'textarea', default: 'Motorku si vyzvedni přímo v půjčovně, nebo na místě, které jsi zvolil při rezervaci.' },
        { key: 'web.pujcovna.process.steps.5.title', label: 'Krok 6 – nadpis', default: '6. Užij si jízdu' },
        { key: 'web.pujcovna.process.steps.5.text', label: 'Krok 6 – popis', type: 'textarea', default: 'Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.' },
        { key: 'web.pujcovna.process.steps.6.title', label: 'Krok 7 – nadpis', default: '7. Vrať motorku' },
        { key: 'web.pujcovna.process.steps.6.text', label: 'Krok 7 – popis', type: 'textarea', default: 'Motorku jednoduše vrať ve sjednaný den – přímo v půjčovně, nebo na předem domluveném místě.' },
        { key: 'web.pujcovna.process.steps.7.title', label: 'Krok 8 – nadpis', default: 'Sleva na příští jízdu' },
        { key: 'web.pujcovna.process.steps.7.text', label: 'Krok 8 – popis', type: 'textarea', default: 'Po vrácení motorky ti automaticky zašleme slevový kód 200 Kč na další rezervaci.' },
      ]
    },
    {
      id: 'faq', label: 'Často kladené otázky (4 položky)', location: 'Sekce FAQ na konci stránky',
      fields: [
        { key: 'web.pujcovna.faq.title', label: 'Nadpis sekce', default: 'Často kladené otázky' },
        { key: 'web.pujcovna.faq.items.0.q', label: 'Otázka 1', default: 'Jak si mohu rezervovat motorku?' },
        { key: 'web.pujcovna.faq.items.0.a', label: 'Odpověď 1', type: 'textarea', default: 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.' },
        { key: 'web.pujcovna.faq.items.1.q', label: 'Otázka 2', default: 'Můžu si motorku půjčit i bez předchozí rezervace?' },
        { key: 'web.pujcovna.faq.items.1.a', label: 'Odpověď 2', type: 'textarea', default: 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit.' },
        { key: 'web.pujcovna.faq.items.2.q', label: 'Otázka 3', default: 'Musím složit kauci?' },
        { key: 'web.pujcovna.faq.items.2.a', label: 'Odpověď 3', type: 'textarea', default: 'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.' },
        { key: 'web.pujcovna.faq.items.3.q', label: 'Otázka 4', default: 'Můžu odcestovat s motorkou do zahraničí?' },
        { key: 'web.pujcovna.faq.items.3.a', label: 'Odpověď 4', type: 'textarea', default: 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).' },
      ]
    },
    {
      id: 'cta', label: 'CTA sekce', location: 'Závěrečná výzva k akci',
      fields: [
        { key: 'web.pujcovna.cta.title', label: 'Nadpis', default: 'Rezervuj svou motorku online' },
        { key: 'web.pujcovna.cta.text', label: 'Text', type: 'textarea', default: 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.' },
        { key: 'web.pujcovna.cta.buttons.0.label', label: 'Tlačítko 1', default: 'REZERVOVAT MOTORKU' },
        { key: 'web.pujcovna.cta.buttons.1.label', label: 'Tlačítko 2', default: 'Dárkový poukaz' },
        { key: 'web.pujcovna.cta.buttons.2.label', label: 'Tlačítko 3', default: 'Tipy na trasy' },
      ]
    },
  ]
}

// PAGE_JAK_OVERVIEW odstraněn — stránka /jak-pujcit byla smazána, protože byla
// obsahově duplicitní s podstránkami. V menu zůstává jen rodičovský label
// "Jak si půjčit motorku" jako neklickatelný rozcestník nad podmenu.
// Klíče web.jak_pujcit.* v cms_variables zůstávají v DB (nezasahujeme), ale už
// se nikde nečtou — admin je může smazat ručně, pokud chce.
