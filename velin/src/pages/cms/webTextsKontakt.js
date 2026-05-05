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

const range = n => Array.from({ length: n });

export const PAGE_POUKAZY = {
  id: 'poukazy', label: 'Poukazy', icon: '🎁', url: '/poukazy',
  description: 'Dárkové poukazy na pronájem motorky. Editace ve Velíně i inline na webu.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1, úvodní text, CTA',
      fields: [
        { key: 'web.poukazy.h1', label: 'H1', default: 'Kup dárkový poukaz – daruj zážitek na dvou kolech!' },
        { key: 'web.poukazy.intro_left', label: 'Úvodní text (levý sloupec, HTML)', type: 'textarea', default: '' },
        { key: 'web.poukazy.intro_cta.label', label: 'Tlačítko „Objednat poukaz"', default: 'OBJEDNAT DÁRKOVÝ POUKAZ' },
      ]
    },
    {
      id: 'steps', label: 'Kroky nákupu (3 karty)', location: 'Sekce „Jak to funguje"',
      fields: range(3).flatMap((_, i) => ([
        { key: `web.poukazy.steps.${i}.title`, label: `Krok ${i + 1} — titulek`, default: '' },
        { key: `web.poukazy.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
      ]))
    },
    {
      id: 'validity', label: 'Platnost poukazu',
      fields: [
        { key: 'web.poukazy.validity_note', label: 'Text o platnosti', type: 'textarea', default: 'Všechny vouchery mají platnost 3 roky od data vystavení.' },
      ]
    },
    {
      id: 'why', label: 'Proč zakoupit (6 bodů)', location: 'Levý sloupec',
      fields: [
        { key: 'web.poukazy.why.title', label: 'Nadpis sekce', default: 'Proč zakoupit poukaz' },
        ...range(6).map((_, i) => ({
          key: `web.poukazy.why.items.${i}`, label: `Důvod ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'how', label: 'Jak poukaz využít (4 body)', location: 'Pravý sloupec',
      fields: [
        { key: 'web.poukazy.how.title', label: 'Nadpis sekce', default: 'Jak poukaz využít' },
        ...range(4).map((_, i) => ({
          key: `web.poukazy.how.items.${i}`, label: `Bod ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'catalog_cta', label: 'Tlačítko „Zobrazit katalog"',
      fields: [
        { key: 'web.poukazy.catalog_cta.label', label: 'Text tlačítka', default: 'ZOBRAZIT KATALOG MOTOREK' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (5 otázek)', location: 'Často kladené dotazy k poukazům',
      fields: [
        { key: 'web.poukazy.faq.title', label: 'Nadpis sekce', default: 'Často kladené dotazy k dárkovým poukazům' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.poukazy.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.poukazy.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'Závěrečná CTA sekce',
      fields: [
        { key: 'web.poukazy.cta.title', label: 'Nadpis', default: 'Dárkový poukaz na pronájem motorky – Vysočina' },
        { key: 'web.poukazy.cta.text', label: 'Text', type: 'textarea', default: '' },
        { key: 'web.poukazy.cta.buttons.0.label', label: 'Tlačítko 1', default: 'OBJEDNAT VOUCHER' },
      ]
    },
  ]
}

// POZN. ke konvenci klíčů u sekcí Kalendář / Skener / Validace:
// Klíče v `lang/*.php` mají tvar `rez.cal.month.0`, `rez.cam.shoot`, …
// Aby je admin přepsal přes CMS bez deployi, používáme prefix
// `web.layout.<key>` — `_i18nCmsOverlay()` v PHP strne `web.layout.` a zbytek
// použije jako klíč pro `t()`. (Prefix se historicky jmenuje „layout", ale ve
// skutečnosti to je obecný t()-overlay; rozšíření o non-layout klíče je čistá
// reuse.) Auto-překlad přes `translations` jsonb funguje stejně jako u home.
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
        { key: 'web.rez.delivery.tooltip', label: 'Přistavení tooltip', type: 'textarea', default: 'Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (20 Kč/km × 2 cesty = 40 Kč/km).' },
        { key: 'web.rez.passenger.label', label: 'Výbava spolujezdce', default: 'Základní výbavu spolujezdce - 690,- Kč' },
        { key: 'web.rez.boots.rider', label: 'Boty řidič', default: 'Zapůjčení bot pro řidiče - 290,- Kč' },
        { key: 'web.rez.boots.passenger', label: 'Boty spolujezdec', default: 'Zapůjčení bot pro spolujezdce - 290,- Kč' },
      ]
    },
    {
      id: 'calendar', label: 'Kalendář', location: 'Kalendář dostupnosti motorky (pages-rezervace-calendar.js)',
      fields: [
        { key: 'web.layout.rez.cal.month.0', label: 'Měsíc 1', default: 'Leden' },
        { key: 'web.layout.rez.cal.month.1', label: 'Měsíc 2', default: 'Únor' },
        { key: 'web.layout.rez.cal.month.2', label: 'Měsíc 3', default: 'Březen' },
        { key: 'web.layout.rez.cal.month.3', label: 'Měsíc 4', default: 'Duben' },
        { key: 'web.layout.rez.cal.month.4', label: 'Měsíc 5', default: 'Květen' },
        { key: 'web.layout.rez.cal.month.5', label: 'Měsíc 6', default: 'Červen' },
        { key: 'web.layout.rez.cal.month.6', label: 'Měsíc 7', default: 'Červenec' },
        { key: 'web.layout.rez.cal.month.7', label: 'Měsíc 8', default: 'Srpen' },
        { key: 'web.layout.rez.cal.month.8', label: 'Měsíc 9', default: 'Září' },
        { key: 'web.layout.rez.cal.month.9', label: 'Měsíc 10', default: 'Říjen' },
        { key: 'web.layout.rez.cal.month.10', label: 'Měsíc 11', default: 'Listopad' },
        { key: 'web.layout.rez.cal.month.11', label: 'Měsíc 12', default: 'Prosinec' },
        { key: 'web.layout.rez.cal.dayShort.0', label: 'Den (zkratka) — Po', default: 'Po' },
        { key: 'web.layout.rez.cal.dayShort.1', label: 'Den (zkratka) — Út', default: 'Út' },
        { key: 'web.layout.rez.cal.dayShort.2', label: 'Den (zkratka) — St', default: 'St' },
        { key: 'web.layout.rez.cal.dayShort.3', label: 'Den (zkratka) — Čt', default: 'Čt' },
        { key: 'web.layout.rez.cal.dayShort.4', label: 'Den (zkratka) — Pá', default: 'Pá' },
        { key: 'web.layout.rez.cal.dayShort.5', label: 'Den (zkratka) — So', default: 'So' },
        { key: 'web.layout.rez.cal.dayShort.6', label: 'Den (zkratka) — Ne', default: 'Ne' },
        { key: 'web.layout.rez.cal.prev', label: 'Aria-label "předchozí měsíc"', default: 'Předchozí měsíc' },
        { key: 'web.layout.rez.cal.next', label: 'Aria-label "další měsíc"', default: 'Další měsíc' },
        { key: 'web.layout.rez.cal.legend.free', label: 'Legenda — Volné', default: 'Volné' },
        { key: 'web.layout.rez.cal.legend.selected', label: 'Legenda — Vybraný termín', default: 'Vybraný termín' },
        { key: 'web.layout.rez.cal.legend.occupied', label: 'Legenda — Obsazené', default: 'Obsazené' },
        { key: 'web.layout.rez.cal.legend.unconfirmed', label: 'Legenda — Nepotvrzené', default: 'Nepotvrzené' },
        { key: 'web.layout.rez.cal.noMotoInRange', label: 'Hláška — žádná motorka v termínu', default: 'V tomto termínu bohužel není dostupná žádná motorka.' },
        { key: 'web.layout.rez.cal.freeInRange', label: 'Badge — Volné v termínu', default: 'Volné v termínu' },
        { key: 'web.layout.rez.cal.pickFromList', label: 'Label — Vyberte motorku ze seznamu', default: 'Vyberte motorku ze seznamu' },
        { key: 'web.layout.rez.cal.selectMoto', label: 'Placeholder — vyberte motorku', default: 'vyberte motorku' },
      ]
    },
    {
      id: 'camera', label: 'Skener dokladů', location: 'Mobilní kamera pro OP/ŘP (pages-rezervace-camera.js)',
      fields: [
        { key: 'web.layout.rez.cam.docs.id', label: 'Titulek — OP', default: 'Doklad totožnosti' },
        { key: 'web.layout.rez.cam.docs.license', label: 'Titulek — ŘP', default: 'Řidičský průkaz' },
        { key: 'web.layout.rez.cam.close', label: 'Aria-label — Zavřít', default: 'Zavřít' },
        { key: 'web.layout.rez.cam.hint', label: 'Hint pod rámečkem', type: 'textarea', default: 'Vložte doklad celý do rámečku. Držte telefon rovně, dobré osvětlení.' },
        { key: 'web.layout.rez.cam.shoot', label: 'CTA — Spustit sken', default: 'Spustit sken' },
        { key: 'web.layout.rez.cam.progress', label: 'Status — Snímám', default: 'Snímám…' },
      ]
    },
    {
      id: 'alerts', label: 'Validační hlášky', location: 'alert() pop-upy při neúplném formuláři (pages-rezervace-steps.js)',
      fields: [
        { key: 'web.layout.rez.alert.selectSize', label: 'Vyberte velikost', default: 'Nejdřív vyberte velikost.' },
      ]
    },
  ]
}
