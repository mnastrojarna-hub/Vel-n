// Texty webu: Domovská stránka
// Klíče přesně mapují strukturu `$defaults` v motogo-web-php/pages/home.php,
// aby se overlay z `cms_variables` (přes fetchWebTexts → cmsDeepMerge)
// promítl 1:1 na rendered HTML. Editace ve Velínu = okamžitý dopad na web.
export const PAGE_HOME = {
  id: 'home', label: 'Domovská stránka', icon: '🏠', url: '/',
  description: 'Hlavní vstupní stránka webu s hero bannerem, signposty, kroky procesu a FAQ.',
  sections: [
    {
      id: 'seo', label: 'SEO meta', location: '<head> — title, description, keywords (zobrazují se v Googlu a sociálních sítích)',
      fields: [
        { key: 'web.home.seo.title', label: 'Title (titulek záložky)', default: 'Půjčovna motorek na Vysočině | MotoGo24' },
        { key: 'web.home.seo.description', label: 'Meta description', type: 'textarea', default: 'Půjčte si motorku na Vysočině. Bez kauce, výbava v ceně, nonstop provoz. Cestovní, sportovní, enduro i dětské motorky. Online rezervace.' },
        { key: 'web.home.seo.keywords', label: 'Meta keywords', type: 'textarea', default: 'půjčovna motorek Vysočina, pronájem motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna, motorky k pronájmu, online rezervace motorky' },
      ]
    },
    {
      id: 'hero', label: 'Hero banner', location: 'Velký banner nahoře na stránce s obrázkem',
      fields: [
        { key: 'web.home.hero.alt', label: 'ALT obrázku', hint: 'pro screen readery a SEO', default: 'Půjčovna motorek Vysočina' },
        { key: 'web.home.hero.eyebrow', label: 'Horní řádek (HTML povolený)', hint: 'může obsahovat <strong>', default: '<strong>Půjčovna motorek</strong> na Vysočině' },
        { key: 'web.home.hero.body', label: 'Hlavní text (HTML povolený)', type: 'textarea', default: 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z cestovních, sportovních i enduro modelů.<br>Rezervace s platbou kartou a rychlým převzetím.' },
        { key: 'web.home.hero.cta_primary.label', label: 'CTA tlačítko 1 — text', default: 'VYBER SI MOTORKU' },
        { key: 'web.home.hero.cta_secondary.label', label: 'CTA tlačítko 2 — text', default: 'JAK TO FUNGUJE' },
      ]
    },
    {
      id: 'h1', label: 'Hlavní nadpis H1 a úvodní odstavec', location: 'Pod hero bannerem, hlavní SEO nadpis',
      fields: [
        { key: 'web.home.h1', label: 'H1 nadpis', default: 'Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop' },
        { key: 'web.home.intro', label: 'Úvodní odstavec (HTML povolený)', type: 'textarea', default: 'Vítejte v <strong>Motogo24</strong> – vaší půjčovně motorek na Vysočině. U nás si půjčíte motorku <strong>bez kauce</strong>, s výbavou v ceně a v režimu <strong>nonstop</strong>. Ať hledáte cestovní, sportovní, enduro nebo dětskou motorku, Motogo24 vám v srdci Vysočiny nabídne motorku na míru.' },
      ]
    },
    {
      id: 'signposts', label: 'Signposty (6 navigačních karet)', location: 'Sekce pod H1 — 6 karet s ikonami a CTA',
      fields: [
        { key: 'web.home.signposts_title', label: 'Nadpis sekce', default: 'Rychlý rozcestník po Motogo24' },
        { key: 'web.home.signposts.0.title', label: 'Karta 1 — nadpis', default: 'Katalog motorek' },
        { key: 'web.home.signposts.0.text', label: 'Karta 1 — text', type: 'textarea', default: 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.' },
        { key: 'web.home.signposts.0.btn', label: 'Karta 1 — tlačítko', default: 'KATALOG MOTOREK' },
        { key: 'web.home.signposts.1.title', label: 'Karta 2 — nadpis', default: 'Jak si půjčit motorku' },
        { key: 'web.home.signposts.1.text', label: 'Karta 2 — text', type: 'textarea', default: 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte a vyjeďte.' },
        { key: 'web.home.signposts.1.btn', label: 'Karta 2 — tlačítko', default: 'JAK SI PŮJČIT MOTORKU' },
        { key: 'web.home.signposts.2.title', label: 'Karta 3 — nadpis', default: 'Online rezervace motorky' },
        { key: 'web.home.signposts.2.text', label: 'Karta 3 — text', type: 'textarea', default: 'Zarezervujte si motorku na pronájem přes snadný online systém.' },
        { key: 'web.home.signposts.2.btn', label: 'Karta 3 — tlačítko', default: 'REZERVOVAT MOTORKU' },
        { key: 'web.home.signposts.3.title', label: 'Karta 4 — nadpis', default: 'Kontakty a mapa' },
        { key: 'web.home.signposts.3.text', label: 'Karta 4 — text', type: 'textarea', default: 'Navštivte naši půjčovnu motorek v Pelhřimově nebo nás kontaktujte.' },
        { key: 'web.home.signposts.3.btn', label: 'Karta 4 — tlačítko', default: 'KONTAKT' },
        { key: 'web.home.signposts.4.title', label: 'Karta 5 — nadpis', default: 'Často kladené dotazy' },
        { key: 'web.home.signposts.4.text', label: 'Karta 5 — text', type: 'textarea', default: 'Nejčastější dotazy k půjčení motorky přehledně na jednom místě.' },
        { key: 'web.home.signposts.4.btn', label: 'Karta 5 — tlačítko', default: 'ČASTÉ DOTAZY' },
        { key: 'web.home.signposts.5.title', label: 'Karta 6 — nadpis', default: 'Motocyklové výlety' },
        { key: 'web.home.signposts.5.text', label: 'Karta 6 — text', type: 'textarea', default: 'Objevte nejlepší motocyklové trasy v Česku pro turisty i místní.' },
        { key: 'web.home.signposts.5.btn', label: 'Karta 6 — tlačítko', default: 'MOTOCYKLOVÉ TRASY' },
      ]
    },
    {
      id: 'motos', label: 'Sekce motorek', location: 'Výpis 4 motorek z DB pod signposty',
      fields: [
        { key: 'web.home.motos_section.title', label: 'Nadpis sekce', default: 'Naše motorky k pronájmu na Vysočině' },
        { key: 'web.home.motos_section.intro', label: 'Popis', type: 'textarea', default: 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší půjčovny motorek na Vysočině.' },
        { key: 'web.home.motos_section.empty', label: 'Text pokud nejsou motorky', default: 'Momentálně nemáme žádné motorky v nabídce.' },
        { key: 'web.home.motos_section.cta_label', label: 'Tlačítko pod sekcí', default: 'KATALOG MOTOREK' },
      ]
    },
    {
      id: 'process', label: 'Kroky procesu (4 karty)', location: 'Sekce „Jak probíhá půjčení" se 4 kroky',
      fields: [
        { key: 'web.home.process.title', label: 'Nadpis sekce', default: 'Jak probíhá půjčení motorky na Vysočině' },
        { key: 'web.home.process.steps.0.title', label: 'Krok 1 — nadpis', default: '1. Vyber' },
        { key: 'web.home.process.steps.0.text', label: 'Krok 1 — text', type: 'textarea', default: 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.' },
        { key: 'web.home.process.steps.1.title', label: 'Krok 2 — nadpis', default: '2. Rezervuj' },
        { key: 'web.home.process.steps.1.text', label: 'Krok 2 — text', type: 'textarea', default: 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.' },
        { key: 'web.home.process.steps.2.title', label: 'Krok 3 — nadpis', default: '3. Převzetí' },
        { key: 'web.home.process.steps.2.text', label: 'Krok 3 — text', type: 'textarea', default: 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.' },
        { key: 'web.home.process.steps.3.title', label: 'Krok 4 — nadpis', default: '4. Užij jízdu' },
        { key: 'web.home.process.steps.3.text', label: 'Krok 4 — text', type: 'textarea', default: 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (řízeno přes DB)', location: 'Sekce s častými dotazy pod kroky — položky se editují v záložce „Časté dotazy"',
      fields: [
        { key: 'web.home.faq.title', label: 'Nadpis FAQ sekce', default: 'Často kladené otázky' },
      ]
    },
    {
      id: 'cta', label: 'CTA sekce', location: 'Zelená výzva k akci dole na stránce',
      fields: [
        { key: 'web.home.cta.title', label: 'Nadpis CTA', default: 'Rezervuj svou motorku online' },
        { key: 'web.home.cta.text', label: 'Text CTA (HTML povolený)', type: 'textarea', default: 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.' },
        { key: 'web.home.cta.buttons.0.label', label: 'Tlačítko 1 — text', default: 'REZERVOVAT MOTORKU' },
        { key: 'web.home.cta.buttons.1.label', label: 'Tlačítko 2 — text', default: 'Dárkový poukaz' },
        { key: 'web.home.cta.buttons.2.label', label: 'Tlačítko 3 — text', default: 'Tipy na trasy' },
      ]
    },
    {
      id: 'blog', label: 'Sekce „Blog a tipy"', location: 'Náhled 3 článků pod CTA',
      fields: [
        { key: 'web.home.blog.title', label: 'Nadpis sekce', default: 'Blog a tipy' },
        { key: 'web.home.blog.empty', label: 'Text pokud nejsou články', default: 'Zatím nemáme žádné články.' },
        { key: 'web.home.blog.cta_label', label: 'Tlačítko pod sekcí', default: 'ČÍST VÍCE V BLOGU' },
      ]
    },
    {
      id: 'reviews', label: 'Sekce „Co o nás říkají zákazníci"', location: 'Recenze (zobrazí se jen pokud jsou v DB)',
      fields: [
        { key: 'web.home.reviews.title', label: 'Nadpis sekce', default: 'Co o nás říkají zákazníci' },
        { key: 'web.home.reviews.intro', label: 'Popis', type: 'textarea', default: 'Reálné recenze od motorkářů, kteří si u nás půjčili. Děkujeme za každé hodnocení.' },
      ]
    },
  ]
}
