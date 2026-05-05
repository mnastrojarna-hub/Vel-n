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

// POZN. ke konvenci klíčů na /rezervace:
// Klíče v `lang/*.php` mají tvar `rez.h1`, `rez.intro.title`, `rez.cal.month.0`, …
// Aby je admin přepsal přes CMS bez deployi, používáme prefix
// `web.layout.<key>` — `_i18nCmsOverlay()` v PHP strne `web.layout.` a zbytek
// použije jako klíč pro `t()`. (Prefix se historicky jmenuje „layout", ale ve
// skutečnosti to je obecný t()-overlay.) Auto-překlad přes `translations`
// jsonb funguje stejně jako u home. Klíče `rezervace.*` (meta) zůstávají bez
// `rez.` prefixu — proto `web.layout.rezervace.title` apod.
export const PAGE_REZERVACE = {
  id: 'rezervace', label: 'Rezervace', icon: '📅', url: '/rezervace',
  description: 'Rezervační stránka s kalendářem, formulářem a kroky 1-6 (motorka, termín, kontakt, místo, výbava, souhlasy).',
  sections: [
    {
      id: 'meta', label: 'SEO meta',
      fields: [
        { key: 'web.layout.rezervace.title', label: 'Page <title>', default: 'Online rezervace motorky | MotoGo24' },
        { key: 'web.layout.rezervace.description', label: 'Meta description', type: 'textarea', default: 'Online rezervace motorky na Vysočině. Bez kauce, s výbavou v ceně a nonstop provozem. Vyberte motorku, termín a zaplaťte online.' },
        { key: 'web.layout.rezervace.keywords', label: 'Meta keywords', default: 'rezervace motorky online, půjčit motorku, pronájem motorky Vysočina, online booking' },
        { key: 'web.layout.rezervace.loading', label: 'Spinner overlay text', default: 'Načítám rezervační systém...' },
      ]
    },
    {
      id: 'intro', label: 'Úvod stránky (H1 + „Jak to funguje")',
      fields: [
        { key: 'web.layout.rez.h1', label: 'H1 nadpis', default: 'Rezervace motorky' },
        { key: 'web.layout.rez.intro.title', label: 'Podnadpis „Jak rezervace funguje?"', default: 'Jak rezervace funguje?' },
        { key: 'web.layout.rez.intro.specific', label: 'Text 1 — konkrétní termín', type: 'textarea', default: 'Chcete <strong>konkrétní termín</strong>? Vyberte „libovolná dostupná motorka" a v kalendáři vyznačte datum — zobrazí se všechny volné motorky.' },
        { key: 'web.layout.rez.intro.bike', label: 'Text 2 — konkrétní motorka', type: 'textarea', default: 'Chcete <strong>konkrétní motorku</strong>? Vyberte ji ze seznamu — kalendář ukáže její dostupné termíny.' },
        { key: 'web.layout.rez.intro.benefits', label: 'Text 3 — bez kauce, výbava zdarma', default: 'Bez kauce · výbava pro řidiče zdarma · velikost si vyberete v motopůjčovně' },
      ]
    },
    {
      id: 'resume', label: 'Pokračování v rozdělané rezervaci',
      fields: [
        { key: 'web.layout.rez.loading.resume', label: '„Načítám rezervaci…"', default: 'Načítám rezervaci...' },
        { key: 'web.layout.rez.notFound.title', label: 'Nadpis „Rezervace nenalezena"', default: 'Rezervace nenalezena' },
        { key: 'web.layout.rez.notFound.text', label: 'Text „Již dokončena/zrušena"', default: 'Rezervace již byla dokončena nebo zrušena.' },
        { key: 'web.layout.rez.notFound.create', label: 'Tlačítko „Vytvořit novou"', default: 'Vytvořit novou rezervaci' },
        { key: 'web.layout.rez.error.loading', label: 'Chyba „Při načítání"', default: 'Chyba při načítání rezervace' },
        { key: 'web.layout.rez.error.tryAgain', label: 'Chyba — výzva', default: 'Zkuste to prosím znovu nebo nás kontaktujte.' },
      ]
    },
    {
      id: 'steps', label: 'Nadpisy kroků 1–6',
      fields: [
        { key: 'web.layout.rez.step.moto', label: 'Krok 1 — Vyberte motorku', default: 'Vyberte motorku' },
        { key: 'web.layout.rez.step.date', label: 'Krok 2 — Vyberte termín', default: 'Vyberte termín' },
        { key: 'web.layout.rez.step.contact', label: 'Krok 3 — Kontaktní údaje', default: 'Vaše kontaktní údaje' },
        { key: 'web.layout.rez.step.location', label: 'Krok 4 — Vyzvednutí a vrácení', default: 'Vyzvednutí a vrácení' },
        { key: 'web.layout.rez.step.gear', label: 'Krok 5 — Výbava a velikosti', default: 'Výbava a velikosti' },
        { key: 'web.layout.rez.step.agreements', label: 'Krok 6 — Souhlasy', default: 'Souhlasy' },
      ]
    },
    {
      id: 'motoSelect', label: 'Krok 1 — výběr motorky',
      fields: [
        { key: 'web.layout.rez.motoSelect.label', label: 'Label „Konkrétní model nebo libovolná"', default: 'Konkrétní model nebo libovolná motorka' },
        { key: 'web.layout.rez.motoSelect.any', label: 'Možnost „libovolná dostupná"', default: 'libovolná dostupná motorka v mém termínu' },
      ]
    },
    {
      id: 'contact', label: 'Krok 3 — Kontaktní údaje',
      fields: [
        { key: 'web.layout.rez.contact.name', label: 'Label „Jméno a příjmení"', default: '* Jméno a příjmení' },
        { key: 'web.layout.rez.contact.street', label: 'Label „Ulice, č.p."', default: '* Ulice, č.p.' },
        { key: 'web.layout.rez.contact.zip', label: 'Label „PSČ"', default: '* PSČ' },
        { key: 'web.layout.rez.contact.city', label: 'Label „Město"', default: '* Město' },
        { key: 'web.layout.rez.contact.country', label: 'Label „Stát"', default: '* Stát' },
        { key: 'web.layout.rez.contact.countryDefault', label: 'Defaultní stát', default: 'Česká republika' },
        { key: 'web.layout.rez.contact.email', label: 'Label „E-mail"', default: '* E-mail' },
        { key: 'web.layout.rez.contact.phone', label: 'Label „Telefon"', default: '* Telefon (+420XXXXXXXXX)' },
        { key: 'web.layout.rez.contact.voucher', label: 'Label „Slevový kód / poukaz"', default: 'Slevový kód / dárkový poukaz' },
        { key: 'web.layout.rez.contact.apply', label: 'Tlačítko „Uplatnit"', default: 'UPLATNIT' },
        { key: 'web.layout.rez.contact.required', label: 'Hláška „Pole je povinné"', default: 'Toto pole je povinné' },
      ]
    },
    {
      id: 'pickup', label: 'Krok 4 — Vyzvednutí motorky',
      fields: [
        { key: 'web.layout.rez.pickup.title', label: 'Nadpis „Čas převzetí"', default: 'Čas převzetí nebo přistavení' },
        { key: 'web.layout.rez.pickup.sub', label: 'Pomocný text', default: 'Vyberte z nabídky nebo zadejte vlastní čas' },
        { key: 'web.layout.rez.pickup.recommended', label: 'Štítek „Doporučené časy"', default: 'Doporučené časy (06:00 — 14:00)' },
        { key: 'web.layout.rez.pickup.orCustom', label: 'Štítek „Nebo vlastní"', default: '· nebo vyberte vlastní čas vlevo' },
        { key: 'web.layout.rez.pickup.atRental', label: 'Možnost „V motopůjčovně"', default: 'Vyzvednutí v motopůjčovně' },
        { key: 'web.layout.rez.pickup.atRentalSub', label: 'Popis „V motopůjčovně"', default: 'Zdarma · 24/7 přístup s kódem · základní nastavení' },
        { key: 'web.layout.rez.pickup.delivery', label: 'Možnost „Přistavení"', default: 'Přistavení motorky jinam' },
        { key: 'web.layout.rez.pickup.deliverySub', label: 'Popis „Přistavení" (šablona)', default: '{base} + {perKm}/km od pobočky', hint: '{base}, {perKm}' },
        { key: 'web.layout.rez.pickup.deliveryTip', label: 'Tooltip „Přistavení"', type: 'textarea', default: 'Motorku vám dovezeme na domluvené místo. Cena: {base} + {perKm}/km od pobočky Mezná 9, 393 01 Mezná. Trasu spočítáme automaticky po zadání adresy.' },
        { key: 'web.layout.rez.pickup.deliveryAddr', label: 'Placeholder „Adresa přistavení"', default: 'Zadejte adresu přistavení (ulice, město)' },
        { key: 'web.layout.rez.pickup.sameAsDel', label: 'Checkbox „Vrátit na stejné adrese"', default: 'Vrátit motorku na stejné adrese' },
        { key: 'web.layout.rez.pickup.returnOther', label: 'Checkbox „Vrácení jinde"', default: 'Vrácení motorky jinde, než kde bylo vyzvednuto' },
        { key: 'web.layout.rez.pickup.returnTip', label: 'Tooltip „Vrácení jinde"', type: 'textarea', default: 'Motorku vám rádi vyzvedneme jinde. Cena: {base} + {perKm}/km od pobočky Mezná 9, 393 01 Mezná. Trasu spočítáme automaticky po zadání adresy.' },
        { key: 'web.layout.rez.pickup.returnAddr', label: 'Placeholder „Adresa vrácení"', default: 'Zadejte adresu vrácení' },
        { key: 'web.layout.rez.pickup.map', label: 'Tlačítko „Mapa"', default: 'Mapa' },
        { key: 'web.layout.rez.return.title', label: 'Nadpis „Čas vrácení"', default: 'Čas vrácení motorky' },
        { key: 'web.layout.rez.return.sub', label: 'Popis „Čas vrácení"', default: 'V kolik hodin vrátíte motorku na uvedené adrese?' },
      ]
    },
    {
      id: 'gear', label: 'Krok 5 — Výbava a velikosti (TEXTY)',
      fields: [
        { key: 'web.layout.rez.gear.intro', label: 'Úvodní text', type: 'textarea', default: 'Vyberte velikosti kliknutím na čtverečky níže. Pokud velikost nezvolíte, vyzkoušíme ji na místě.' },
        { key: 'web.layout.rez.gear.rider', label: 'Karta „Výbava řidiče" — název', default: 'Výbava řidiče' },
        { key: 'web.layout.rez.gear.riderSub', label: 'Karta „Výbava řidiče" — popis', default: 'Helma, bunda, rukavice, kalhoty' },
        { key: 'web.layout.rez.gear.riderFree', label: 'Štítek „v ceně · zdarma"', default: 'v ceně · zdarma' },
        { key: 'web.layout.rez.gear.riderOwn', label: 'Checkbox „Mám vlastní výbavu"', default: 'Mám vlastní výbavu — nepůjčuji' },
        { key: 'web.layout.rez.gear.passenger', label: 'Karta „Výbava spolujezdce" — název', default: 'Výbava spolujezdce' },
        { key: 'web.layout.rez.gear.passengerSub', label: 'Karta „Výbava spolujezdce" — popis', default: 'Helma, bunda, rukavice, kukla' },
        { key: 'web.layout.rez.gear.passengerTip', label: 'Tooltip „Výbava spolujezdce"', type: 'textarea', default: 'Základní výbava pro spolujezdce: helma, bunda, rukavice a kukla. Velikost si vyberete kliknutím níže nebo na místě.' },
        { key: 'web.layout.rez.gear.bootsRider', label: 'Karta „Boty pro řidiče" — název', default: 'Boty pro řidiče' },
        { key: 'web.layout.rez.gear.bootsRiderSub', label: 'Karta „Boty pro řidiče" — popis', default: 'Motocyklové boty (nejsou v základní výbavě)' },
        { key: 'web.layout.rez.gear.bootsPassenger', label: 'Karta „Boty pro spolujezdce" — název', default: 'Boty pro spolujezdce' },
        { key: 'web.layout.rez.gear.bootsPassengerSub', label: 'Karta „Boty pro spolujezdce" — popis', default: 'Motocyklové boty pro spolujezdce' },
        { key: 'web.layout.rez.gear.sizeHintGear', label: 'Hint — výbava řidiče', default: '✅ Zaškrtněte výše pro výběr velikostí (jinak se vyzkouší na místě)' },
        { key: 'web.layout.rez.gear.sizeHintPassenger', label: 'Hint — výbava spolujezdce', default: '✅ Zaškrtněte výše a rozbalí se výběr velikostí spolujezdce' },
        { key: 'web.layout.rez.gear.sizeHintBoots', label: 'Hint — boty', default: '✅ Zaškrtněte výše a rozbalí se výběr velikosti bot' },
        { key: 'web.layout.rez.gear.sizeChoose', label: 'Štítek „vyber"', default: 'vyber' },
        { key: 'web.layout.rez.gear.label.helmet', label: 'Položka „Helma"', default: 'Helma' },
        { key: 'web.layout.rez.gear.label.jacket', label: 'Položka „Bunda"', default: 'Bunda' },
        { key: 'web.layout.rez.gear.label.gloves', label: 'Položka „Rukavice"', default: 'Rukavice' },
        { key: 'web.layout.rez.gear.label.pants', label: 'Položka „Kalhoty"', default: 'Kalhoty' },
        { key: 'web.layout.rez.gear.label.boots', label: 'Položka „Boty"', default: 'Boty' },
        { key: 'web.layout.rez.gear.item.passengerExtras', label: 'Položka faktury „Výbava spolujezdce"', default: 'Výbava spolujezdce' },
        { key: 'web.layout.rez.gear.item.bootsRider', label: 'Položka faktury „Boty řidič"', default: 'Boty řidič' },
        { key: 'web.layout.rez.gear.item.bootsPassenger', label: 'Položka faktury „Boty spolujezdce"', default: 'Boty spolujezdce' },
        { key: 'web.layout.rez.gear.item.delivery', label: 'Položka faktury „Přistavení"', default: 'Přistavení motorky' },
        { key: 'web.layout.rez.gear.item.return', label: 'Položka faktury „Vrácení"', default: 'Vrácení motorky' },
      ]
    },
    {
      id: 'agreements', label: 'Krok 6 — Souhlasy',
      fields: [
        { key: 'web.layout.rez.agree.terms', label: 'Souhlas s VOP (HTML, povinné)', type: 'textarea', default: '* Souhlasím s <a href="/obchodni-podminky">obchodními podmínkami</a>' },
        { key: 'web.layout.rez.agree.gdpr', label: 'Souhlas GDPR (HTML)', type: 'textarea', default: 'Souhlasím se <a href="/gdpr">zpracováním osobních údajů</a>' },
        { key: 'web.layout.rez.agree.marketing', label: 'Souhlas marketing', default: 'Souhlasím se zasíláním marketingových sdělení' },
        { key: 'web.layout.rez.agree.photo', label: 'Souhlas fotografie', default: 'Souhlasím s využitím fotografií pro marketingové účely' },
      ]
    },
    {
      id: 'cta', label: 'CTA + cena',
      fields: [
        { key: 'web.layout.rez.cta.continue', label: 'Tlačítko „Pokračovat v rezervaci"', default: 'Pokračovat v rezervaci →' },
        { key: 'web.layout.rez.cta.continuePay', label: 'Tlačítko „Pokračovat k platbě"', default: 'Pokračovat k platbě' },
        { key: 'web.layout.rez.totalPrice', label: 'Šablona „Celková cena"', default: 'Celková cena: {price}', hint: '{price} = částka' },
        { key: 'web.layout.rez.discount', label: 'Šablona „Sleva"', default: 'Sleva: −{amount}', hint: '{amount}' },
      ]
    },
    {
      id: 'voucher', label: 'Voucher / slevový kód',
      fields: [
        { key: 'web.layout.rez.voucher.enter', label: 'Placeholder „Zadejte kód"', default: 'Zadejte kód' },
        { key: 'web.layout.rez.voucher.duplicate', label: 'Hláška „Kód již uplatněn"', default: 'Kód již uplatněn' },
        { key: 'web.layout.rez.voucher.verifying', label: 'Hláška „Ověřuji…"', default: 'Ověřuji...' },
        { key: 'web.layout.rez.voucher.error', label: 'Hláška „Chyba ověření"', default: 'Chyba ověření kódu: {msg}' },
        { key: 'web.layout.rez.voucher.invalid', label: 'Hláška „Neplatný kód"', default: 'Kód nebyl nalezen nebo není platný' },
        { key: 'web.layout.rez.voucher.percentOnce', label: 'Hláška „Dva procentuální"', default: 'Nelze kombinovat dva procentuální kódy' },
        { key: 'web.layout.rez.voucher.discountApplied', label: 'Hláška „Sleva uplatněna"', default: '✓ Sleva {label} uplatněna (−{amt})' },
        { key: 'web.layout.rez.voucher.voucherApplied', label: 'Hláška „Poukaz uplatněn"', default: '✓ Poukaz {amt} uplatněn' },
      ]
    },
    {
      id: 'alerts', label: 'Validační hlášky (alerty)',
      fields: [
        { key: 'web.layout.rez.alert.name', label: 'Validace jména', default: 'Zadejte platné jméno a příjmení (min. 2 písmena, bez číslic).' },
        { key: 'web.layout.rez.alert.street', label: 'Validace ulice', default: 'Zadejte ulici a číslo popisné (min. 3 znaky).' },
        { key: 'web.layout.rez.alert.city', label: 'Validace města', default: 'Zadejte město (min. 2 znaky).' },
        { key: 'web.layout.rez.alert.zip', label: 'Validace PSČ', default: 'Vyplňte prosím PSČ.' },
        { key: 'web.layout.rez.alert.email', label: 'Validace e-mailu', default: 'Zadejte platnou e-mailovou adresu.' },
        { key: 'web.layout.rez.alert.phone', label: 'Validace telefonu', default: 'Zadejte telefon v mezinárodním formátu (např. +420 777 000 000).' },
        { key: 'web.layout.rez.alert.terms', label: 'Validace VOP', default: 'Pro pokračování musíte souhlasit s obchodními podmínkami.' },
        { key: 'web.layout.rez.alert.dates', label: 'Validace termínu', default: 'Vyberte prosím termín v kalendáři.' },
        { key: 'web.layout.rez.alert.moto', label: 'Validace motorky', default: 'Vyberte prosím motorku.' },
        { key: 'web.layout.rez.alert.pickupTime', label: 'Validace času převzetí', default: 'Vyplňte prosím čas převzetí nebo přistavení motorky.' },
        { key: 'web.layout.rez.alert.minTime', label: 'Validace „Minimální čas"', default: 'Nejdříve možný čas převzetí je aktuální čas + 1 hodina.' },
        { key: 'web.layout.rez.alert.minTimeDelivery', label: 'Validace „Min. čas přistavení"', default: 'Při přistavení je nejdříve možný čas aktuální čas + 6 hodin.' },
        { key: 'web.layout.rez.alert.returnTime', label: 'Validace času vrácení', default: 'Vyplňte prosím čas vrácení motorky.' },
        { key: 'web.layout.rez.alert.bookingOverlap', label: 'Validace „Termín obsazen"', type: 'textarea', default: 'Tuto motorku právě rezervoval jiný zákazník ve stejném termínu. Zvolte prosím jiný termín nebo jinou motorku.' },
        { key: 'web.layout.rez.alert.bookingOverlapOwn', label: 'Validace „Vlastní rezervace"', default: 'V tomto termínu již máte jinou aktivní rezervaci.' },
        { key: 'web.layout.rez.alert.error', label: 'Šablona „Chyba"', default: 'Chyba: {msg}' },
        { key: 'web.layout.rez.alert.saveError', label: 'Šablona „Chyba ukládání"', default: 'Chyba při ukládání: {msg}' },
        { key: 'web.layout.rez.alert.selectSize', label: 'Validace „Vyberte velikost"', default: 'Nejdřív vyberte velikost.' },
      ]
    },
    {
      id: 'calendar', label: 'Kalendář dostupnosti motorky',
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
        { key: 'web.layout.rez.cal.prev', label: 'Aria-label „předchozí měsíc"', default: 'Předchozí měsíc' },
        { key: 'web.layout.rez.cal.next', label: 'Aria-label „další měsíc"', default: 'Další měsíc' },
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
      id: 'camera', label: 'Skener dokladů (mobil)',
      fields: [
        { key: 'web.layout.rez.cam.docs.id', label: 'Titulek — OP', default: 'Doklad totožnosti' },
        { key: 'web.layout.rez.cam.docs.license', label: 'Titulek — ŘP', default: 'Řidičský průkaz' },
        { key: 'web.layout.rez.cam.close', label: 'Aria-label — Zavřít', default: 'Zavřít' },
        { key: 'web.layout.rez.cam.hint', label: 'Hint pod rámečkem', type: 'textarea', default: 'Vložte doklad celý do rámečku. Držte telefon rovně, dobré osvětlení.' },
        { key: 'web.layout.rez.cam.shoot', label: 'CTA — Spustit sken', default: 'Spustit sken' },
        { key: 'web.layout.rez.cam.progress', label: 'Status — Snímám', default: 'Snímám…' },
      ]
    },
  ]
}
