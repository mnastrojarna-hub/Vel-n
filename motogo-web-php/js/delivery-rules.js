/* ===== MotoGo24 — Přistavení na adresu / odvoz z adresy: KOMU se nenabízí (jedno pravidlo) =====
   Rozhodnutí majitele 2026-09-28: motorky ze SAMOOBSLUŽNÉ pobočky (branches.type = 'samoobslužná')
   se přebírají i vracejí jen na pobočce, dokud to nezapne flag feature_flags.self_service_delivery
   (chybějící řádek / chyba čtení = vypnuto = blokováno). Neznámý typ pobočky = obslužná (povoleno).
   Pravidlo volají: rezervační formulář a úprava rezervace (js/pages-rezervace-selfservice.js)
   a kalkulačka ceny (js/landing-calc-delivery.js) — nikde jinde se nepíše znovu.
   Bez závislostí; načítat PŘED oběma soubory. */
(function (w) {
  var MG = w.MG = w.MG || {}, SS = 'samoobslužná';
  MG.DELIVERY = {
    SS_TYPE: SS,
    FLAG_KEY: 'self_service_delivery',
    // true = přistavení na adresu ani odvoz z adresy se u pobočky tohoto typu nenabízí
    blocked: function (branchType, flagEnabled) { return branchType === SS && !flagEnabled; },
    // Název položky booking_extras ODESÍLANÝ na server (create_web_booking). Server pozná přistavení /
    // odvoz podle pevných prefixů (_booking_extras_delivery) — proto kanonický název dle jazyka stránky,
    // NEZÁVISLÝ na CMS překladu (rez.gear.item.delivery/.return slouží jen pro zobrazení).
    // side: 'delivery' | 'return'; lang: kód jazyka (výchozí <html lang>), neznámý = cs.
    EXTRA_NAMES: {
      delivery: { cs: 'Přistavení motorky', de: 'Motorradlieferung', en: 'Motorcycle delivery', es: 'Entrega de la moto', fr: 'Livraison de la moto', nl: 'Bezorging motor', pl: 'Dostawa motocykla', uk: 'Доставка мотоцикла' },
      'return': { cs: 'Vrácení motorky', de: 'Motorradabholung', en: 'Motorcycle return', es: 'Devolución de la moto', fr: 'Récupération de la moto', nl: 'Ophalen motor', pl: 'Zwrot motocykla', uk: 'Повернення мотоцикла' }
    },
    extraName: function (side, lang) {
      var m = MG.DELIVERY.EXTRA_NAMES[side === 'return' ? 'return' : 'delivery'];
      var l = String(lang || (w.document && w.document.documentElement.lang) || 'cs').slice(0, 2).toLowerCase();
      return m[l] || m.cs;
    }
  };
})(window);
