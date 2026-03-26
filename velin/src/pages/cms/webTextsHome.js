// Texty webu: Domovská stránka
export const PAGE_HOME = {
  id: 'home', label: 'Domovská stránka', icon: '🏠', url: '/',
  description: 'Hlavní vstupní stránka webu s hero bannerem, signposty, kroky procesu a FAQ.',
  sections: [
    {
      id: 'hero', label: 'Hero banner', location: 'Velký banner nahoře na stránce s obrázkem',
      fields: [
        { key: 'web.home.hero.title', label: 'Nadpis', default: 'Půjčovna motorek na Vysočině' },
        { key: 'web.home.hero.subtitle', label: 'Podnadpis', type: 'textarea', default: 'Půjč si motorku na Vysočině snadno online.\nVyber si z cestovních, sportovních i enduro modelů.\nRezervace s platbou kartou a rychlým převzetím.' },
        { key: 'web.home.hero.cta1', label: 'CTA tlačítko 1', default: 'VYBER SI MOTORKU' },
        { key: 'web.home.hero.cta2', label: 'CTA tlačítko 2', default: 'JAK TO FUNGUJE' },
      ]
    },
    {
      id: 'h1', label: 'Hlavní nadpis H1', location: 'Pod hero bannerem, hlavní SEO nadpis',
      fields: [
        { key: 'web.home.h1', label: 'H1 nadpis', default: 'Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop' },
      ]
    },
    {
      id: 'signposts', label: 'Signposty (6 navigačních karet)', location: 'Sekce pod H1 - 6 karet s ikonami a CTA',
      fields: [
        { key: 'web.home.sign.1.title', label: 'Karta 1 - nadpis', default: 'Katalog motorek' },
        { key: 'web.home.sign.1.text', label: 'Karta 1 - text', default: 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.' },
        { key: 'web.home.sign.2.title', label: 'Karta 2 - nadpis', default: 'Jak si půjčit motorku' },
        { key: 'web.home.sign.2.text', label: 'Karta 2 - text', default: 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte, vyjeďte.' },
        { key: 'web.home.sign.3.title', label: 'Karta 3 - nadpis', default: 'Online rezervace motorky' },
        { key: 'web.home.sign.3.text', label: 'Karta 3 - text', default: 'Zarezervujte si motorku na pronájem přes snadný systém.' },
        { key: 'web.home.sign.4.title', label: 'Karta 4 - nadpis', default: 'Kontakty a mapa' },
        { key: 'web.home.sign.4.text', label: 'Karta 4 - text', default: 'Navštivte naši půjčovnu motorek v Pelhřimově nebo nás kontaktujte.' },
        { key: 'web.home.sign.5.title', label: 'Karta 5 - nadpis', default: 'Často kladené dotazy' },
        { key: 'web.home.sign.5.text', label: 'Karta 5 - text', default: 'Nejčastější dotazy k půjčení motorky přehledně.' },
        { key: 'web.home.sign.6.title', label: 'Karta 6 - nadpis', default: 'Motocyklové výlety' },
        { key: 'web.home.sign.6.text', label: 'Karta 6 - text', default: 'Objevte nejlepší motocyklové trasy v Česku pro turisty.' },
      ]
    },
    {
      id: 'motos', label: 'Sekce motorek', location: 'Výpis 4 motorek z DB pod signposty',
      fields: [
        { key: 'web.home.motos.title', label: 'Nadpis sekce', default: 'Naše motorky k pronájmu na Vysočině' },
        { key: 'web.home.motos.text', label: 'Popis', default: 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší půjčovny motorek na Vysočině.' },
      ]
    },
    {
      id: 'steps', label: 'Kroky procesu (4 karty)', location: 'Sekce „Jak probíhá půjčení" se 4 kroky',
      fields: [
        { key: 'web.home.steps.title', label: 'Nadpis sekce', default: 'Jak probíhá půjčení motorky na Vysočině' },
        { key: 'web.home.steps.1.title', label: 'Krok 1 - nadpis', default: '1. Vyber' },
        { key: 'web.home.steps.1.text', label: 'Krok 1 - text', default: 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.' },
        { key: 'web.home.steps.2.title', label: 'Krok 2 - nadpis', default: '2. Rezervuj' },
        { key: 'web.home.steps.2.text', label: 'Krok 2 - text', default: 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.' },
        { key: 'web.home.steps.3.title', label: 'Krok 3 - nadpis', default: '3. Převzetí' },
        { key: 'web.home.steps.3.text', label: 'Krok 3 - text', default: 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.' },
        { key: 'web.home.steps.4.title', label: 'Krok 4 - nadpis', default: '4. Užij jízdu' },
        { key: 'web.home.steps.4.text', label: 'Krok 4 - text', default: 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (4 otázky)', location: 'Sekce s častými dotazy pod kroky',
      fields: [
        { key: 'web.home.faq.1.q', label: 'Otázka 1', default: 'Jak si mohu rezervovat motorku?' },
        { key: 'web.home.faq.1.a', label: 'Odpověď 1', type: 'textarea', default: 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.' },
        { key: 'web.home.faq.2.q', label: 'Otázka 2', default: 'Můžu si motorku půjčit i bez předchozí rezervace?' },
        { key: 'web.home.faq.2.a', label: 'Odpověď 2', type: 'textarea', default: 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit – online, telefonicky, e-mailem nebo přes sociální sítě.' },
        { key: 'web.home.faq.3.q', label: 'Otázka 3', default: 'Musím složit kauci?' },
        { key: 'web.home.faq.3.a', label: 'Odpověď 3', type: 'textarea', default: 'Ne! U nás žádnou kauci platit nemusíš. Naše půjčovna se tímto zásadně liší od většiny konkurence.' },
        { key: 'web.home.faq.4.q', label: 'Otázka 4', default: 'Můžu odcestovat s motorkou do zahraničí?' },
        { key: 'web.home.faq.4.a', label: 'Odpověď 4', type: 'textarea', default: 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).' },
      ]
    },
    {
      id: 'cta', label: 'CTA sekce', location: 'Zelená výzva k akci dole na stránce',
      fields: [
        { key: 'web.home.cta.title', label: 'Nadpis CTA', default: 'Rezervuj svou motorku online' },
        { key: 'web.home.cta.text', label: 'Text CTA', type: 'textarea', default: 'Naše půjčovna motorek Vysočina je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.' },
      ]
    },
  ]
}
