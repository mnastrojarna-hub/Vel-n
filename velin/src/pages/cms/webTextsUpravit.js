// Texty webu: Úprava rezervace (/upravit-rezervaci)
// Stránka je JS-driven. PHP renderuje shell + i18n payload z `lang/cs.php`
// přes `t('editRez.*')` které prochází `_i18nCmsOverlay` (klíče tvaru
// `web.layout.editRez.*` v cms_variables). Když admin ve Velíně uloží text,
// `MG_I18N` ho dostane na další reload stránky.

const range = n => Array.from({ length: n });

export const PAGE_UPRAVIT_REZERVACE = {
  id: 'upravit-rezervaci', label: 'Úprava rezervace', icon: '✏️', url: '/upravit-rezervaci',
  description: 'Klientský portál pro úpravu / prodloužení / zkrácení / storno rezervace. Texty se rendrují přes JS z i18n overlay.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky',
      fields: [
        { key: 'web.layout.editRez.h1', label: 'H1 nadpis', default: 'Úprava rezervace' },
        { key: 'web.layout.editRez.intro', label: 'Úvodní text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.loading', label: 'Hláška „Načítám…"', default: 'Načítám…' },
      ]
    },
    {
      id: 'login', label: 'Přihlášení',
      fields: [
        { key: 'web.layout.editRez.login.title', label: 'Nadpis přihlášení', default: 'Přihlaš se ke svému účtu' },
        { key: 'web.layout.editRez.login.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.login.email', label: 'Label „E-mail"', default: 'E-mail' },
        { key: 'web.layout.editRez.login.password', label: 'Label „Heslo"', default: 'Heslo' },
        { key: 'web.layout.editRez.login.submit', label: 'Tlačítko „Přihlásit"', default: 'Přihlásit se' },
        { key: 'web.layout.editRez.login.submitting', label: 'Tlačítko „Přihlašuji…"', default: 'Přihlašuji…' },
        { key: 'web.layout.editRez.login.forgot', label: 'Odkaz „Zapomněl jsem heslo"', default: 'Zapomněl(a) jsem heslo' },
        { key: 'web.layout.editRez.login.tip', label: 'Tip pod formulářem', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.login.error', label: 'Chyba při přihlášení', default: '' },
      ]
    },
    {
      id: 'forgot', label: 'Zapomenuté heslo',
      fields: [
        { key: 'web.layout.editRez.forgot.title', label: 'Nadpis', default: 'Reset hesla' },
        { key: 'web.layout.editRez.forgot.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.forgot.bookingId', label: 'Label „ID rezervace"', default: 'ID rezervace' },
        { key: 'web.layout.editRez.forgot.email', label: 'Label „E-mail"', default: 'E-mail' },
        { key: 'web.layout.editRez.forgot.submit', label: 'Tlačítko „Odeslat"', default: 'Odeslat reset link' },
        { key: 'web.layout.editRez.forgot.submitting', label: 'Tlačítko „Odesílám…"', default: 'Odesílám…' },
        { key: 'web.layout.editRez.forgot.success', label: 'Hláška úspěchu', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.forgot.error', label: 'Hláška chyby', default: '' },
        { key: 'web.layout.editRez.forgot.back', label: 'Tlačítko „Zpět na přihlášení"', default: 'Zpět na přihlášení' },
      ]
    },
    {
      id: 'reset', label: 'Reset hesla (po kliknutí na link z e-mailu)',
      fields: [
        { key: 'web.layout.editRez.reset.title', label: 'Nadpis', default: 'Nastav nové heslo' },
        { key: 'web.layout.editRez.reset.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.reset.otpHelp', label: 'Pomocný text k OTP', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.reset.otpCode', label: 'Label „Ověřovací kód"', default: 'Ověřovací kód z e-mailu' },
        { key: 'web.layout.editRez.reset.password', label: 'Label „Nové heslo"', default: 'Nové heslo' },
        { key: 'web.layout.editRez.reset.password2', label: 'Label „Heslo znovu"', default: 'Heslo znovu' },
        { key: 'web.layout.editRez.reset.submit', label: 'Tlačítko „Uložit"', default: 'Uložit nové heslo' },
        { key: 'web.layout.editRez.reset.submitting', label: 'Tlačítko „Ukládám…"', default: 'Ukládám…' },
        { key: 'web.layout.editRez.reset.success', label: 'Hláška úspěchu', default: 'Heslo úspěšně změněno' },
        { key: 'web.layout.editRez.reset.error', label: 'Hláška chyby', default: '' },
        { key: 'web.layout.editRez.reset.tooShort', label: 'Validace „Krátké heslo"', default: 'Heslo musí mít minimálně 8 znaků' },
        { key: 'web.layout.editRez.reset.mismatch', label: 'Validace „Hesla se neshodují"', default: 'Hesla se neshodují' },
        { key: 'web.layout.editRez.reset.otpInvalid', label: 'Validace „Špatný kód"', default: 'Neplatný ověřovací kód' },
      ]
    },
    {
      id: 'list', label: 'Seznam rezervací / objednávek',
      fields: [
        { key: 'web.layout.editRez.list.title', label: 'Nadpis „Vaše rezervace"', default: 'Vaše rezervace' },
        { key: 'web.layout.editRez.list.shopTitle', label: 'Nadpis „E-shop objednávky"', default: 'E-shop objednávky' },
        { key: 'web.layout.editRez.list.vouchersTitle', label: 'Nadpis „Dárkové poukazy"', default: 'Dárkové poukazy' },
        { key: 'web.layout.editRez.list.empty', label: 'Hláška „Žádné rezervace"', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.list.openNew', label: 'Tlačítko „Nová rezervace"', default: 'Vytvořit novou rezervaci' },
        { key: 'web.layout.editRez.list.choose', label: 'Tlačítko „Vybrat"', default: 'Vybrat' },
        { key: 'web.layout.editRez.list.payCta', label: 'Tlačítko „Zaplatit"', default: 'Zaplatit' },
        { key: 'web.layout.editRez.logout', label: 'Tlačítko „Odhlásit"', default: 'Odhlásit se' },
      ]
    },
    {
      id: 'tabs', label: 'Záložky detailu rezervace',
      fields: [
        { key: 'web.layout.editRez.tab.detail', label: 'Záložka „Detail"', default: 'Detail' },
        { key: 'web.layout.editRez.tab.extend', label: 'Záložka „Prodloužit"', default: 'Prodloužit' },
        { key: 'web.layout.editRez.tab.shorten', label: 'Záložka „Zkrátit"', default: 'Zkrátit' },
        { key: 'web.layout.editRez.tab.cancel', label: 'Záložka „Zrušit"', default: 'Zrušit' },
        { key: 'web.layout.editRez.tab.moto', label: 'Záložka „Změnit motorku"', default: 'Změnit motorku' },
        { key: 'web.layout.editRez.tab.location', label: 'Záložka „Změnit místo"', default: 'Změnit místo' },
        { key: 'web.layout.editRez.tab.docs', label: 'Záložka „Dokumenty"', default: 'Dokumenty' },
      ]
    },
    {
      id: 'detail', label: 'Detail rezervace — popisky',
      fields: [
        { key: 'web.layout.editRez.detail.title', label: 'Nadpis „Detail rezervace"', default: 'Detail rezervace' },
        { key: 'web.layout.editRez.detail.bookingId', label: 'Label „ID rezervace"', default: 'ID rezervace' },
        { key: 'web.layout.editRez.detail.bookingNum', label: 'Label „Číslo rezervace"', default: 'Číslo rezervace' },
        { key: 'web.layout.editRez.detail.moto', label: 'Label „Motorka"', default: 'Motorka' },
        { key: 'web.layout.editRez.detail.dates', label: 'Label „Termín"', default: 'Termín' },
        { key: 'web.layout.editRez.detail.pickup', label: 'Label „Vyzvednutí"', default: 'Vyzvednutí' },
        { key: 'web.layout.editRez.detail.return', label: 'Label „Vrácení"', default: 'Vrácení' },
        { key: 'web.layout.editRez.detail.totalPaid', label: 'Label „Zaplaceno celkem"', default: 'Zaplaceno celkem' },
        { key: 'web.layout.editRez.detail.daysCount', label: 'Label „Počet dní"', default: 'Počet dní' },
        { key: 'web.layout.editRez.detail.gearTitle', label: 'Nadpis „Výbava"', default: 'Výbava' },
        { key: 'web.layout.editRez.detail.priceTotal', label: 'Label „Celková cena"', default: 'Celková cena' },
        { key: 'web.layout.editRez.detail.historyTitle', label: 'Nadpis „Historie změn"', default: 'Historie změn' },
      ]
    },
    {
      id: 'extend', label: 'Prodloužení rezervace',
      fields: [
        { key: 'web.layout.editRez.extend.title', label: 'Nadpis', default: 'Prodloužit rezervaci' },
        { key: 'web.layout.editRez.extend.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.extend.helpUpcoming', label: 'Pomocný text (nadcházející)', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.extend.helpActive', label: 'Pomocný text (probíhající)', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.extend.newStart', label: 'Label „Nový začátek"', default: 'Nový začátek' },
        { key: 'web.layout.editRez.extend.newEnd', label: 'Label „Nový konec"', default: 'Nový konec' },
        { key: 'web.layout.editRez.extend.priceDiff', label: 'Label „Doplatek"', default: 'Doplatek' },
        { key: 'web.layout.editRez.extend.cta', label: 'Tlačítko „Prodloužit"', default: 'Prodloužit a zaplatit' },
        { key: 'web.layout.editRez.extend.creating', label: 'Tlačítko „Zpracovávám…"', default: 'Zpracovávám…' },
        { key: 'web.layout.editRez.extend.unavailable', label: 'Hláška „Není dostupné"', default: 'V tomto termínu motorka není dostupná' },
        { key: 'web.layout.editRez.extend.noChange', label: 'Hláška „Žádná změna"', default: 'Termín se nezměnil' },
      ]
    },
    {
      id: 'shorten', label: 'Zkrácení rezervace',
      fields: [
        { key: 'web.layout.editRez.shorten.title', label: 'Nadpis', default: 'Zkrátit rezervaci' },
        { key: 'web.layout.editRez.shorten.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.shorten.refund', label: 'Label „Vrácená částka"', default: 'Vrátíme ti' },
        { key: 'web.layout.editRez.shorten.refundZero', label: 'Hláška „Bez refundu"', default: 'Bez nároku na refund (storno podmínky)' },
        { key: 'web.layout.editRez.shorten.cta', label: 'Tlačítko „Zkrátit"', default: 'Potvrdit zkrácení' },
        { key: 'web.layout.editRez.shorten.confirming', label: 'Tlačítko „Potvrzuji…"', default: 'Potvrzuji…' },
        { key: 'web.layout.editRez.shorten.success', label: 'Hláška úspěchu', default: 'Rezervace byla zkrácena' },
        { key: 'web.layout.editRez.shorten.reasonLabel', label: 'Label „Důvod (volitelné)"', default: 'Důvod zkrácení (volitelné)' },
      ]
    },
    {
      id: 'cancel', label: 'Storno rezervace',
      fields: [
        { key: 'web.layout.editRez.cancel.title', label: 'Nadpis', default: 'Zrušit rezervaci' },
        { key: 'web.layout.editRez.cancel.warn', label: 'Varování', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.cancel.refundLabel', label: 'Label „Vrácená částka"', default: 'Vrátíme ti' },
        { key: 'web.layout.editRez.cancel.reasonLabel', label: 'Label „Důvod"', default: 'Důvod zrušení' },
        { key: 'web.layout.editRez.cancel.reasonPlaceholder', label: 'Placeholder „Důvod"', default: 'Volitelný komentář…' },
        { key: 'web.layout.editRez.cancel.cta', label: 'Tlačítko „Zrušit rezervaci"', default: 'Zrušit rezervaci' },
        { key: 'web.layout.editRez.cancel.confirming', label: 'Tlačítko „Ruším…"', default: 'Ruším…' },
        { key: 'web.layout.editRez.cancel.success', label: 'Hláška úspěchu', default: 'Rezervace byla zrušena' },
        { key: 'web.layout.editRez.cancel.confirmTitle', label: 'Potvrzovací dialog — nadpis', default: 'Opravdu zrušit?' },
        { key: 'web.layout.editRez.cancel.confirmYes', label: 'Tlačítko „Ano"', default: 'Ano, zrušit' },
        { key: 'web.layout.editRez.cancel.confirmNo', label: 'Tlačítko „Ne"', default: 'Zpět' },
      ]
    },
    {
      id: 'storno', label: 'Storno podmínky (popis)',
      fields: [
        { key: 'web.layout.editRez.storno.title', label: 'Nadpis', default: 'Storno podmínky' },
        { key: 'web.layout.editRez.storno.tier1', label: 'Tier 1 — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.storno.tier2', label: 'Tier 2 — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.storno.tier3', label: 'Tier 3 — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.storno.note', label: 'Poznámka', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'moto_change', label: 'Změna motorky',
      fields: [
        { key: 'web.layout.editRez.moto.title', label: 'Nadpis', default: 'Změnit motorku' },
        { key: 'web.layout.editRez.moto.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.moto.intro', label: 'Úvod', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.moto.loading', label: 'Načítání', default: 'Načítám dostupné motorky…' },
        { key: 'web.layout.editRez.moto.unavailable', label: 'Hláška „Nedostupné"', default: '' },
        { key: 'web.layout.editRez.moto.noOptions', label: 'Hláška „Žádné varianty"', default: 'Žádná jiná motorka v tomto termínu není dostupná' },
        { key: 'web.layout.editRez.moto.confirm', label: 'Tlačítko „Vybrat tuto"', default: 'Vybrat tuto motorku' },
        { key: 'web.layout.editRez.moto.selectThis', label: 'Tlačítko „Tuto si vyberu"', default: 'Tuto si vyberu' },
        { key: 'web.layout.editRez.moto.licenseInsufficient', label: 'Hláška „Nemáte ŘP"', default: 'Pro tuto motorku potřebuješ vyšší řidičské oprávnění' },
        { key: 'web.layout.editRez.moto.notAvailable', label: 'Hláška „Není dostupná"', default: 'Motorka v tomto termínu není dostupná' },
      ]
    },
    {
      id: 'location', label: 'Změna místa vyzvednutí / vrácení',
      fields: [
        { key: 'web.layout.editRez.loc.title', label: 'Nadpis', default: 'Změnit místo vyzvednutí / vrácení' },
        { key: 'web.layout.editRez.loc.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.loc.pickup', label: 'Label „Vyzvednutí"', default: 'Vyzvednutí' },
        { key: 'web.layout.editRez.loc.return', label: 'Label „Vrácení"', default: 'Vrácení' },
        { key: 'web.layout.editRez.loc.atRental', label: 'Možnost „V půjčovně"', default: 'V půjčovně Pelhřimov' },
        { key: 'web.layout.editRez.loc.delivery', label: 'Možnost „Přistavení"', default: 'Přistavení na místo' },
        { key: 'web.layout.editRez.loc.deliveryReturn', label: 'Možnost „Vrácení jinde"', default: 'Vrácení na jiném místě' },
        { key: 'web.layout.editRez.loc.addrPlaceholder', label: 'Placeholder adresy', default: 'Adresa…' },
        { key: 'web.layout.editRez.loc.mapBtn', label: 'Tlačítko „Vybrat na mapě"', default: 'Vybrat na mapě' },
        { key: 'web.layout.editRez.loc.cta', label: 'Tlačítko „Potvrdit změnu"', default: 'Potvrdit změnu' },
        { key: 'web.layout.editRez.loc.confirm', label: 'Tlačítko „Uložit"', default: 'Uložit' },
        { key: 'web.layout.editRez.loc.routing', label: 'Hláška „Počítám trasu…"', default: 'Počítám trasu…' },
        { key: 'web.layout.editRez.loc.geocodeFail', label: 'Hláška „Adresa nenalezena"', default: 'Adresu se nepodařilo najít' },
        { key: 'web.layout.editRez.loc.noPriceChange', label: 'Hláška „Beze změny ceny"', default: 'Změna místa nemění cenu' },
      ]
    },
    {
      id: 'docs', label: 'Dokumenty (sekce)',
      fields: [
        { key: 'web.layout.editRez.doc.title', label: 'Nadpis', default: 'Dokumenty' },
        { key: 'web.layout.editRez.doc.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.doc.empty', label: 'Hláška „Žádné dokumenty"', default: 'Zatím žádné dokumenty' },
        { key: 'web.layout.editRez.doc.download', label: 'Tlačítko „Stáhnout"', default: 'Stáhnout' },
        { key: 'web.layout.editRez.doc.notAvailable', label: 'Hláška „Není k dispozici"', default: 'Dokument zatím není k dispozici' },
        { key: 'web.layout.editRez.doc.close', label: 'Tlačítko „Zavřít"', default: 'Zavřít' },
      ]
    },
    {
      id: 'pending', label: 'Nezaplacená rezervace (varování)',
      fields: [
        { key: 'web.layout.editRez.pending.title', label: 'Nadpis', default: 'Rezervace čeká na platbu' },
        { key: 'web.layout.editRez.pending.text', label: 'Text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.pending.payNow', label: 'Tlačítko „Zaplatit"', default: 'Zaplatit teď' },
        { key: 'web.layout.editRez.pending.cancelNow', label: 'Tlačítko „Zrušit"', default: 'Zrušit rezervaci' },
      ]
    },
    {
      id: 'consents', label: 'Souhlasy (GDPR / VOP / marketing)',
      fields: [
        { key: 'web.layout.editRez.consents.cardTitle', label: 'Nadpis sekce', default: 'Souhlasy' },
        { key: 'web.layout.editRez.consents.help', label: 'Pomocný text', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.consents.required', label: 'Štítek „Povinné"', default: 'Povinné' },
        { key: 'web.layout.editRez.consents.optional', label: 'Štítek „Volitelné"', default: 'Volitelné' },
        { key: 'web.layout.editRez.consents.toggleYes', label: 'Toggle „Souhlasím"', default: 'Souhlasím' },
        { key: 'web.layout.editRez.consents.toggleNo', label: 'Toggle „Nesouhlasím"', default: 'Nesouhlasím' },
        { key: 'web.layout.editRez.consents.label.gdpr', label: 'GDPR — název', default: 'GDPR' },
        { key: 'web.layout.editRez.consents.desc.gdpr', label: 'GDPR — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.consents.label.vop', label: 'VOP — název', default: 'VOP' },
        { key: 'web.layout.editRez.consents.desc.vop', label: 'VOP — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.consents.label.contract', label: 'Smlouva — název', default: 'Nájemní smlouva' },
        { key: 'web.layout.editRez.consents.desc.contract', label: 'Smlouva — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.consents.label.marketing', label: 'Marketing — název', default: 'Marketing' },
        { key: 'web.layout.editRez.consents.desc.marketing', label: 'Marketing — popis', type: 'textarea', default: '' },
        { key: 'web.layout.editRez.consents.label.email', label: 'E-mail — název', default: 'E-mail' },
        { key: 'web.layout.editRez.consents.label.sms', label: 'SMS — název', default: 'SMS' },
        { key: 'web.layout.editRez.consents.label.whatsapp', label: 'WhatsApp — název', default: 'WhatsApp' },
        { key: 'web.layout.editRez.consents.label.push', label: 'Push — název', default: 'Push notifikace' },
      ]
    },
    {
      id: 'errors', label: 'Chybové hlášky',
      fields: [
        { key: 'web.layout.editRez.err.generic', label: 'Obecná chyba', default: 'Něco se pokazilo. Zkuste to prosím znovu.' },
        { key: 'web.layout.editRez.err.notFound', label: 'Rezervace nenalezena', default: 'Rezervace nebyla nalezena' },
        { key: 'web.layout.editRez.err.wrongStatus', label: 'Nesprávný stav', default: 'Tuto rezervaci nelze upravit ve stavu, ve kterém je' },
        { key: 'web.layout.editRez.err.notPaid', label: 'Není zaplaceno', default: 'Rezervace ještě není zaplacena' },
        { key: 'web.layout.editRez.err.cantEdit', label: 'Nelze upravit', default: 'Tuto rezervaci nelze upravit' },
        { key: 'web.layout.editRez.err.serverDown', label: 'Server nedostupný', default: 'Server je momentálně nedostupný' },
        { key: 'web.layout.editRez.err.emailNotConfirmed', label: 'E-mail nepotvrzen', default: 'E-mail ještě nebyl potvrzen' },
      ]
    },
  ]
}
