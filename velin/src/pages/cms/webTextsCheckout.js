// Texty webu: Košík + Pokladna + Děkovací stránka (e-shop checkout flow)
// Stránky používají `t()` overlay přes `_i18nCmsOverlay` (cms_variables klíče
// `web.layout.<key>`). PHP renderuje shell, JS dotazy + dynamický obsah.
// /potvrzeni je čistě JS-driven (MOTOGO_CONFIRM_I18N payload z PHP),
// /kosik a /objednavka mají statické labely v PHP s `tc()` (admin inline edit OK).

export const PAGE_KOSIK = {
  id: 'kosik', label: 'Košík', icon: '🛒', url: '/kosik',
  description: 'Stránka košíku e-shopu — labely a tlačítka. Obsah košíku se rendruje z localStorage v JS.',
  sections: [
    {
      id: 'main', label: 'Hlavní texty',
      fields: [
        { key: 'web.layout.cart.title', label: 'H1 nadpis / titulek záložky', default: 'Košík' },
        { key: 'web.layout.cart.empty', label: 'Hláška „Prázdný košík"', type: 'textarea', default: 'Tvůj košík je prázdný.' },
        { key: 'web.layout.cart.continueShopping', label: 'Tlačítko „Pokračovat v nákupu"', default: 'Pokračovat v nákupu' },
        { key: 'web.layout.cart.loading', label: 'Hláška „Načítám…"', default: 'Načítám košík…' },
      ]
    },
    {
      id: 'summary', label: 'Souhrn košíku',
      fields: [
        { key: 'web.layout.cart.summaryTitle', label: 'Nadpis „Souhrn"', default: 'Souhrn objednávky' },
        { key: 'web.layout.cart.summaryAria', label: 'ARIA label souhrnu', default: 'Souhrn objednávky' },
        { key: 'web.layout.cart.subtotal', label: 'Label „Mezisoučet"', default: 'Mezisoučet' },
        { key: 'web.layout.cart.shipping', label: 'Label „Doprava"', default: 'Doprava' },
        { key: 'web.layout.cart.total', label: 'Label „Celkem"', default: 'Celkem' },
        { key: 'web.layout.cart.totalNow', label: 'Label „K platbě"', default: 'K platbě' },
        { key: 'web.layout.cart.shippingNote', label: 'Poznámka k dopravě', type: 'textarea', default: 'Cenu dopravy spočítáme v dalším kroku.' },
        { key: 'web.layout.cart.checkout', label: 'Tlačítko „Pokračovat k platbě"', default: 'Pokračovat k platbě' },
      ]
    },
  ]
}

export const PAGE_OBJEDNAVKA = {
  id: 'objednavka', label: 'Pokladna (objednávka)', icon: '💳', url: '/objednavka',
  description: 'E-shop pokladna: kontakt → doprava → souhrn → platba (Stripe).',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky',
      fields: [
        { key: 'web.layout.checkout.title', label: 'H1 nadpis', default: 'Pokladna' },
        { key: 'web.layout.checkout.intro', label: 'Úvodní text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'contact', label: 'Sekce 1: Kontaktní údaje',
      fields: [
        { key: 'web.layout.checkout.contact.title', label: 'Nadpis sekce', default: 'Kontaktní údaje' },
        { key: 'web.layout.checkout.contact.sub', label: 'Podtitulek', type: 'textarea', default: '' },
        { key: 'web.layout.checkout.contact.name', label: 'Label „Jméno a příjmení"', default: 'Jméno a příjmení' },
        { key: 'web.layout.checkout.contact.email', label: 'Label „E-mail"', default: 'E-mail' },
        { key: 'web.layout.checkout.contact.phone', label: 'Label „Telefon"', default: 'Telefon' },
      ]
    },
    {
      id: 'shipping', label: 'Sekce 2: Doprava',
      fields: [
        { key: 'web.layout.checkout.shipping.title', label: 'Nadpis sekce', default: 'Doprava' },
        { key: 'web.layout.checkout.shipping.sub', label: 'Podtitulek', type: 'textarea', default: '' },
        { key: 'web.layout.checkout.shipping.free', label: 'Label „Zdarma"', default: 'Zdarma' },
        { key: 'web.layout.checkout.shipping.pickup', label: 'Karta „Vyzvednutí" — titulek', default: 'Osobní vyzvednutí v Pelhřimově' },
        { key: 'web.layout.checkout.shipping.pickupSub', label: 'Karta „Vyzvednutí" — podpis', type: 'textarea', default: '' },
        { key: 'web.layout.checkout.shipping.post', label: 'Karta „Pošta" — titulek', default: 'Česká pošta' },
        { key: 'web.layout.checkout.shipping.postSub', label: 'Karta „Pošta" — podpis', type: 'textarea', default: '' },
        { key: 'web.layout.checkout.shipping.postPrice', label: 'Karta „Pošta" — cena', default: '' },
        { key: 'web.layout.checkout.shipping.zasilkovna', label: 'Karta „Zásilkovna" — titulek', default: 'Zásilkovna' },
        { key: 'web.layout.checkout.shipping.zasilkovnaSub', label: 'Karta „Zásilkovna" — podpis', type: 'textarea', default: '' },
        { key: 'web.layout.checkout.shipping.zasilkovnaPrice', label: 'Karta „Zásilkovna" — cena', default: '' },
      ]
    },
    {
      id: 'address', label: 'Adresa doručení',
      fields: [
        { key: 'web.layout.checkout.address.street', label: 'Label „Ulice a č.p."', default: 'Ulice a č.p.' },
        { key: 'web.layout.checkout.address.zip', label: 'Label „PSČ"', default: 'PSČ' },
        { key: 'web.layout.checkout.address.city', label: 'Label „Město"', default: 'Město' },
        { key: 'web.layout.checkout.address.country', label: 'Label „Země"', default: 'Země' },
        { key: 'web.layout.checkout.address.country.cz', label: 'Země: Česko', default: 'Česko' },
        { key: 'web.layout.checkout.address.country.sk', label: 'Země: Slovensko', default: 'Slovensko' },
        { key: 'web.layout.checkout.address.country.de', label: 'Země: Německo', default: 'Německo' },
        { key: 'web.layout.checkout.address.country.at', label: 'Země: Rakousko', default: 'Rakousko' },
        { key: 'web.layout.checkout.address.country.pl', label: 'Země: Polsko', default: 'Polsko' },
      ]
    },
    {
      id: 'summary', label: 'Sekce 3: Souhrn + platba',
      fields: [
        { key: 'web.layout.checkout.summary.title', label: 'Nadpis sekce', default: 'Souhrn objednávky' },
        { key: 'web.layout.checkout.notes', label: 'Label „Poznámka"', default: 'Poznámka k objednávce (volitelně)' },
        { key: 'web.layout.checkout.notesPlaceholder', label: 'Placeholder „Poznámka"', default: 'Cokoli, co bychom měli vědět…' },
        { key: 'web.layout.checkout.backToCart', label: 'Tlačítko „Zpět do košíku"', default: 'Zpět do košíku' },
        { key: 'web.layout.checkout.pay', label: 'Tlačítko „Zaplatit"', default: 'Zaplatit a dokončit' },
      ]
    },
  ]
}

export const PAGE_POTVRZENI = {
  id: 'potvrzeni', label: 'Děkovací stránka', icon: '✅', url: '/potvrzeni',
  description: 'Stránka po platbě: úspěch / pending / chyba. JS-driven, texty přes _i18nCmsOverlay.',
  sections: [
    {
      id: 'verify', label: 'Stav „Ověřuji platbu"',
      fields: [
        { key: 'web.layout.confirm.verifying', label: 'Hláška „Ověřuji platbu…"', default: 'Ověřujeme platbu, prosím vyčkej…' },
      ]
    },
    {
      id: 'success_titles', label: 'Úspěch — titulky podle typu',
      fields: [
        { key: 'web.layout.confirm.success.bookingTitle', label: 'Titulek po rezervaci motorky', default: 'Rezervace potvrzena' },
        { key: 'web.layout.confirm.success.orderTitle', label: 'Titulek po e-shop objednávce', default: 'Objednávka přijata' },
        { key: 'web.layout.confirm.success.voucherTitle', label: 'Titulek po koupi poukazu', default: 'Voucher zakoupen' },
        { key: 'web.layout.confirm.success.thanks', label: 'Poděkování (zákazník v DB)', type: 'textarea', default: 'Děkujeme {name}! Tvoje platba prošla v pořádku.' },
        { key: 'web.layout.confirm.success.thanksAnon', label: 'Poděkování (anonymní)', type: 'textarea', default: 'Děkujeme! Tvoje platba prošla v pořádku.' },
      ]
    },
    {
      id: 'success_summary', label: 'Souhrn po platbě',
      fields: [
        { key: 'web.layout.confirm.success.summaryTitle', label: 'Nadpis souhrnu', default: 'Souhrn' },
        { key: 'web.layout.confirm.success.period', label: 'Label „Termín"', default: 'Termín' },
        { key: 'web.layout.confirm.success.total', label: 'Label „Celkem"', default: 'Celkem' },
        { key: 'web.layout.confirm.success.paid', label: 'Label „Zaplaceno"', default: 'Zaplaceno' },
        { key: 'web.layout.confirm.success.email', label: 'Label „E-mail"', default: 'E-mail' },
        { key: 'web.layout.confirm.success.bookingNumber', label: 'Label „Číslo rezervace"', default: 'Číslo rezervace' },
        { key: 'web.layout.confirm.success.orderNumber', label: 'Label „Číslo objednávky"', default: 'Číslo objednávky' },
        { key: 'web.layout.confirm.success.voucherCode', label: 'Label „Kód voucheru"', default: 'Kód voucheru' },
        { key: 'web.layout.confirm.success.validUntil', label: 'Label „Platnost do"', default: 'Platnost do' },
      ]
    },
    {
      id: 'success_email', label: 'Hlášky o e-mailu',
      fields: [
        { key: 'web.layout.confirm.success.emailSentBooking', label: 'E-mail odeslán (rezervace)', type: 'textarea', default: 'Potvrzení a předvyplněnou nájemní smlouvu jsme ti poslali e-mailem.' },
        { key: 'web.layout.confirm.success.emailSentOrder', label: 'E-mail odeslán (objednávka)', type: 'textarea', default: 'Souhrn objednávky a daňový doklad ti dorazí e-mailem.' },
        { key: 'web.layout.confirm.success.emailSentVoucher', label: 'E-mail odeslán (voucher)', type: 'textarea', default: 'Voucher ti dorazí na e-mail v PDF.' },
      ]
    },
    {
      id: 'success_next', label: 'Co dál',
      fields: [
        { key: 'web.layout.confirm.success.nextTitle', label: 'Nadpis „Co bude dál"', default: 'Co bude dál' },
        { key: 'web.layout.confirm.success.nextBookingDocs', label: 'Krok rezervace — doklady', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextBookingCodes', label: 'Krok rezervace — kódy', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextBookingPickup', label: 'Krok rezervace — vyzvednutí', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextOrderShip', label: 'Krok objednávky — odeslání', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextVoucherEmail', label: 'Krok voucheru — e-mail', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextVoucherPrint', label: 'Krok voucheru — tisk', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.nextContact', label: 'Krok — kontakt', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.success.seeYouSoon', label: 'Závěrečná věta', default: 'Brzy nashledanou!' },
        { key: 'web.layout.confirm.success.backHome', label: 'Tlačítko „Zpět na úvod"', default: 'Zpět na úvod' },
        { key: 'web.layout.confirm.success.continueShopping', label: 'Tlačítko „Pokračovat v nákupu"', default: 'Pokračovat v nákupu' },
      ]
    },
    {
      id: 'pending', label: 'Stav „Pending" (platba ještě neprošla)',
      fields: [
        { key: 'web.layout.confirm.pending.title', label: 'Nadpis', default: 'Platba ještě nebyla potvrzena' },
        { key: 'web.layout.confirm.pending.text1', label: 'Text 1', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.pending.text2', label: 'Text 2', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.pending.nextTitle', label: 'Nadpis „Co s tím"', default: 'Co s tím' },
        { key: 'web.layout.confirm.pending.nextStep1', label: 'Krok 1', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.pending.nextStep2', label: 'Krok 2', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.pending.nextStep3', label: 'Krok 3', type: 'textarea', default: '' },
        { key: 'web.layout.confirm.pending.failIntro', label: 'Úvod „Možné důvody"', type: 'textarea', default: 'Platba se nemusela podařit z těchto důvodů:' },
        { key: 'web.layout.confirm.pending.reason1', label: 'Důvod 1', default: '' },
        { key: 'web.layout.confirm.pending.reason2', label: 'Důvod 2', default: '' },
        { key: 'web.layout.confirm.pending.reason3', label: 'Důvod 3', default: '' },
        { key: 'web.layout.confirm.pending.reason4', label: 'Důvod 4', default: '' },
        { key: 'web.layout.confirm.pending.reason5', label: 'Důvod 5', default: '' },
        { key: 'web.layout.confirm.pending.reason6', label: 'Důvod 6', default: '' },
        { key: 'web.layout.confirm.pending.retry', label: 'Tlačítko „Zkusit platbu znovu"', default: 'Zkusit platbu znovu' },
      ]
    },
    {
      id: 'error', label: 'Stav „Chyba"',
      fields: [
        { key: 'web.layout.confirm.error.title', label: 'Nadpis', default: 'Něco se pokazilo' },
        { key: 'web.layout.confirm.error.contactPrefix', label: 'Prefix u kontaktu', default: 'Pokud potřebuješ pomoc, ozvi se:' },
        { key: 'web.layout.confirm.error.contactPhone', label: 'Telefonní číslo', default: '+420 774 256 271' },
        { key: 'web.layout.confirm.error.tryAgain', label: 'Tlačítko „Zkusit znovu"', default: 'Zkusit znovu' },
        { key: 'web.layout.confirm.error.missingId', label: 'Hláška „Chybí ID"', type: 'textarea', default: 'Chybí parametr identifikace platby. Zkus se vrátit na úvod a začít znovu.' },
      ]
    },
    {
      id: 'titles', label: 'Titulky stránky (záložka)',
      fields: [
        { key: 'web.layout.confirm.titleBooking', label: 'Title (rezervace)', default: 'Potvrzení rezervace | MotoGo24' },
        { key: 'web.layout.confirm.titleOrder', label: 'Title (objednávka)', default: 'Potvrzení objednávky | MotoGo24' },
      ]
    },
  ]
}
