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
    blocked: function (branchType, flagEnabled) { return branchType === SS && !flagEnabled; }
  };
})(window);
