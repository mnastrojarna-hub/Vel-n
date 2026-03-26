// Texty webu: Kontakt + Poukazy + Rezervace
export const PAGE_KONTAKT = {
  id: 'kontakt', label: 'Kontakt', icon: '📞', url: '/kontakt',
  description: 'Kontaktní stránka s telefonem, emailem, adresou, mapou a fakturačními údaji.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.kontakt.h1', label: 'H1', default: 'Kontakty půjčovna motorek Motogo24' },
        { key: 'web.kontakt.intro', label: 'Úvodní text', type: 'textarea', default: 'Máte dotaz k půjčení motorky, chcete si objednat dárkový poukaz, poradit s výběrem nebo si rovnou domluvit rezervaci? Jsme tu pro vás každý den, nonstop.' },
      ]
    },
    {
      id: 'contact', label: 'Kontaktní údaje', location: 'Boxy s telefonem, emailem, datovkou',
      fields: [
        { key: 'web.kontakt.phone', label: 'Telefon', default: '+420 774 256 271' },
        { key: 'web.kontakt.email', label: 'Email', default: 'info@motogo24.cz' },
        { key: 'web.kontakt.ds', label: 'Datová schránka', default: 'iuw3vnb' },
      ]
    },
    {
      id: 'address', label: 'Provozovna', location: 'Sekce s adresou a provozní dobou',
      fields: [
        { key: 'web.kontakt.address', label: 'Adresa', default: 'Mezná 9, 393 01 Pelhřimov' },
        { key: 'web.kontakt.hours', label: 'Provozní doba', default: 'PO – NE: 00:00 – 24:00 (nonstop)\nVčetně víkendů a svátků' },
      ]
    },
    {
      id: 'billing', label: 'Fakturační údaje', location: 'Sekce fakturačních údajů',
      fields: [
        { key: 'web.kontakt.company', label: 'Název firmy', default: 'Bc. Petra Semorádová' },
        { key: 'web.kontakt.billing.addr', label: 'Fakturační adresa', default: 'Mezná 9, 393 01 Pelhřimov' },
        { key: 'web.kontakt.ico', label: 'IČO', default: '21874263' },
        { key: 'web.kontakt.vat', label: 'DPH', default: 'Nejsem plátce DPH' },
        { key: 'web.kontakt.reg', label: 'Registrace', default: 'Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.' },
      ]
    },
    {
      id: 'social', label: 'Sociální sítě', location: 'Odkazy na Facebook a Instagram',
      fields: [
        { key: 'web.kontakt.fb', label: 'Facebook URL', default: 'https://www.facebook.com/profile.php?id=61581614672839' },
        { key: 'web.kontakt.ig', label: 'Instagram URL', default: 'https://www.instagram.com/moto.go24/' },
      ]
    },
    {
      id: 'seo', label: 'SEO text', location: 'Textový odstavec dole na stránce',
      fields: [
        { key: 'web.kontakt.seo', label: 'SEO text', type: 'textarea', default: 'Motogo24 je moderní půjčovna motorek na Vysočině. Sídlíme v Pelhřimově, jsme otevřeni nonstop a půjčujeme bez kauce, s kompletní výbavou v ceně.' },
      ]
    },
  ]
}

export const PAGE_POUKAZY = {
  id: 'poukazy', label: 'Poukazy', icon: '🎁', url: '/poukazy',
  description: 'Dárkové poukazy na pronájem motorky.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní odstavce',
      fields: [
        { key: 'web.poukazy.h1', label: 'H1', default: 'Kup dárkový poukaz – daruj zážitek na dvou kolech!' },
        { key: 'web.poukazy.intro', label: 'Intro text', type: 'textarea', default: 'Hledáš originální dárek pro partnera, kamaráda nebo tátu?\nNaše dárkové poukazy na pronájem motorky od Motogo24 – půjčovna motorek Vysočina – potěší začátečníky i zkušené jezdce.\nVyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.' },
      ]
    },
    {
      id: 'steps', label: 'Kroky (3)', location: '3 karty s kroky nákupu',
      fields: [
        { key: 'web.poukazy.step.1', label: 'Krok 1', default: '1. Vyber – Vybereš si hodnotu poukazu nebo konkrétní motorku.' },
        { key: 'web.poukazy.step.2', label: 'Krok 2', default: '2. Zaplať – Zaplatíš online.' },
        { key: 'web.poukazy.step.3', label: 'Krok 3', default: '3. Vyzvedni – Poukaz po zaplacení přistane do tvé e-mailové schránky.' },
        { key: 'web.poukazy.validity', label: 'Platnost', default: 'Všechny vouchery mají platnost 3 roky od data vystavení. Obdarovaný si sám zvolí termín výpůjčky.' },
      ]
    },
    {
      id: 'why', label: 'Proč zakoupit (6 bodů)', location: 'Levý sloupec – důvody ke koupi',
      fields: [
        { key: 'web.poukazy.why.1', label: 'Důvod 1', default: 'Flexibilní volba – hodnota poukazu nebo konkrétní motorka.' },
        { key: 'web.poukazy.why.2', label: 'Důvod 2', default: 'Platnost 3 roky – obdarovaný si sám vybere termín.' },
        { key: 'web.poukazy.why.3', label: 'Důvod 3', default: 'Bez kauce – férové podmínky.' },
        { key: 'web.poukazy.why.4', label: 'Důvod 4', default: 'Výbava v ceně – helma, bunda, kalhoty a rukavice zdarma.' },
        { key: 'web.poukazy.why.5', label: 'Důvod 5', default: 'Nonstop provoz – vyzvednutí i vrácení kdykoli.' },
        { key: 'web.poukazy.why.6', label: 'Důvod 6', default: 'Online objednávka – poukaz ti po zaplacení přijde e-mailem.' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (5 otázek)', location: 'Často kladené dotazy k poukazům',
      fields: [
        { key: 'web.poukazy.faq.1.q', label: 'Otázka 1', default: 'Jaká je platnost dárkového poukazu?' },
        { key: 'web.poukazy.faq.1.a', label: 'Odpověď 1', default: 'Všechny vouchery mají platnost 3 roky od data vystavení.' },
        { key: 'web.poukazy.faq.2.q', label: 'Otázka 2', default: 'Jak poukaz doručíte?' },
        { key: 'web.poukazy.faq.2.a', label: 'Odpověď 2', default: 'Okamžitě e-mailem po úhradě. Na požádání umíme připravit i dárkový tisk.' },
        { key: 'web.poukazy.faq.3.q', label: 'Otázka 3', default: 'Musí obdarovaný skládat kauci?' },
        { key: 'web.poukazy.faq.3.a', label: 'Odpověď 3', default: 'Ne. Půjčujeme bez kauce. Podmínky jsou jasné a férové.' },
        { key: 'web.poukazy.faq.4.q', label: 'Otázka 4', default: 'Lze změnit termín uplatnění?' },
        { key: 'web.poukazy.faq.4.a', label: 'Odpověď 4', default: 'Ano, termín lze po domluvě změnit dle dostupnosti konkrétní motorky.' },
        { key: 'web.poukazy.faq.5.q', label: 'Otázka 5', default: 'Na jaké motorky lze voucher uplatnit?' },
        { key: 'web.poukazy.faq.5.a', label: 'Odpověď 5', default: 'Na cestovní, sportovní, enduro i dětské motorky v nabídce Motogo24.' },
      ]
    },
  ]
}

export const PAGE_REZERVACE = {
  id: 'rezervace', label: 'Rezervace', icon: '📅', url: '/rezervace',
  description: 'Rezervační stránka s kalendářem a formulářem.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a vysvětlující texty nad formulářem',
      fields: [
        { key: 'web.rez.h1', label: 'H1', default: 'Rezervace motorky' },
        { key: 'web.rez.subtitle', label: 'Podnadpis', default: 'Jak rezervace funguje?' },
        { key: 'web.rez.text1', label: 'Text 1', type: 'textarea', default: 'Pokud si chcete půjčit motorku v konkrétním termínu, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.' },
        { key: 'web.rez.text2', label: 'Text 2', type: 'textarea', default: 'V případě, že si chcete vyzkoušet konkrétní motorku, vyberte ji ze seznamu a v kalendáři se vám zobrazí dostupné termíny.' },
        { key: 'web.rez.text3', label: 'Text 3', default: 'Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.' },
      ]
    },
    {
      id: 'form', label: 'Formulář', location: 'Rezervační formulář pod kalendářem',
      fields: [
        { key: 'web.rez.delivery.label', label: 'Přistavení label', default: 'Přistavení motorky jinam, než na adresu motopůjčovny' },
        { key: 'web.rez.delivery.tooltip', label: 'Přistavení tooltip', type: 'textarea', default: 'Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (20 Kč/1 km).' },
        { key: 'web.rez.passenger.label', label: 'Výbava spolujezdce', default: 'Základní výbava spolujezdce - 690,- Kč' },
        { key: 'web.rez.boots.rider', label: 'Boty řidič', default: 'Zapůjčení bot pro řidiče - 290,- Kč' },
        { key: 'web.rez.boots.passenger', label: 'Boty spolujezdec', default: 'Zapůjčení bot pro spolujezdce - 290,- Kč' },
      ]
    },
  ]
}
