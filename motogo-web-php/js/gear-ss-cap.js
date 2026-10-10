// ===== MotoGo24 — Samoobslužná pobočka: rozsah velikostí výbavy =====
// Zadání majitele 2026-10-10: na SAMOOBSLUŽNÉ pobočce (branches.type =
// 'samoobslužná') se půjčuje dospělá výbava jen v rozsahu
//   helma S–3XL · bunda, kalhoty, rukavice nejvýš 4XL (spodní mez beze změny).
// Boty (čísla), kukla (UNI) a dětská motorka (license_required = 'N') beze změny.
// Filtruje se podle POŘADÍ (XXS < XS < S < M < L < XL < 2XL=XXL < 3XL=XXXL <
// 4XL=XXXXL < 5XL < 6XL), ne bílou listinou — hodnoty, které pořadí nezná
// (čísla, dětské popisky), projdou beze změny. Stejné pravidlo drží kiosk
// (motogo_box/gear_limits.py), edge submit-handover-protocol (gear.ts) a appka.
//
// Sdílené helpery (/rezervace i /upravit-rezervaci):
//   MG._ssCapGearSizes(type, list, isSelfService, isChild) → nové pole (vstup nemění)
//   MG._ssClampSize(type, size, offered, isSelfService, isChild) → velikost mimo
//     rozsah posune na NEJBLIŽŠÍ povolenou z `offered` (5XL → 4XL, helma XS → S);
//     nikdy nevrací prázdno (prázdná velikost = odebrání kusu → vratka, šatna).
//
// /rezervace (minifikované jádro js/pages-rezervace.js se NEUPRAVUJE — obaluje se):
//   MG._accessorySizes      → výsledek se u samoobsluhy filtruje (čipy, prořezání
//                             v _applyMotoGearAudience, předvyplnění z profilu),
//   MG._rerenderGearPanels  → před překreslením se z MG._rez.sizes odeberou
//                             velikosti mimo rozsah (karta pak chce novou volbu),
//   MG._rezApplySelfServiceTimes (volá se po změně motorky i pobočky) → při změně
//                             samoobsluha ano/ne se panely překreslí.
// Samoobsluha = typ pobočky motorky MG._rez.motoId || selectedMotoId, bez motorky
// libovolná motorka vybrané pobočky MG._rez.branchId (jako jádro). Načítá se
// v pages/rezervace.php (za selfservice.js) a pages/upravit-rezervaci.php (před gear.js).
(function () {
  var MG = window.MG;
  if (!MG) return;

  var SS_TYPE = 'samoobslužná';
  var RANK = { XXS: 0, XS: 1, S: 2, M: 3, L: 4, XL: 5, '2XL': 6, XXL: 6, '3XL': 7, XXXL: 7,
    '4XL': 8, XXXXL: 8, '5XL': 9, '6XL': 10 };
  // [min, max] dle RANK; null = bez meze
  var CAP = { helmet: [RANK.S, RANK['3XL']], jacket: [null, RANK['4XL']],
    pants: [null, RANK['4XL']], gloves: [null, RANK['4XL']] };

  function rank(size) {
    var k = String(size == null ? '' : size).trim().toUpperCase();
    return Object.prototype.hasOwnProperty.call(RANK, k) ? RANK[k] : null;
  }
  // Je velikost v rozsahu samoobsluhy? (neznámý typ / neznámá hodnota = ano)
  function inRange(type, size) {
    var c = CAP[type], r = rank(size);
    if (!c || r === null) return true;
    return !(c[0] !== null && r < c[0]) && !(c[1] !== null && r > c[1]);
  }

  MG._ssGearInRange = inRange;
  MG._ssCapGearSizes = function (type, list, isSelfService, isChild) {
    if (!Array.isArray(list)) return list;
    if (!isSelfService || isChild) return list.slice();
    return list.filter(function (s) { return inRange(type, s); });
  };
  MG._ssClampSize = function (type, size, offered, isSelfService, isChild) {
    if (!isSelfService || isChild || !size || inRange(type, size)) return size;
    var r = rank(size), best = null, bestD = Infinity;
    (offered || []).forEach(function (s) {
      var q = rank(s);
      if (q === null || !inRange(type, s)) return;
      var d = Math.abs(q - r);
      if (d < bestD) { bestD = d; best = s; }
    });
    return best === null ? size : best;
  };

  // ---------- /rezervace ----------
  function rezMoto() {
    var r = MG._rez || {}, id = r.motoId || r.selectedMotoId, list = r.motos || [], i;
    for (i = 0; i < list.length; i++) {
      var m = list[i];
      if (m && (id ? m.id === id : (r.branchId && m.branch_id === r.branchId))) return m;
    }
    return null;
  }
  function rezCapActive() {
    var m = rezMoto();
    // isChildMoto řídí, zda jádro vrací dětské řady → u nich se nic neomezuje
    return !!(m && m.branches && m.branches.type === SS_TYPE) && !(MG._rez && MG._rez.isChildMoto);
  }
  // Odebere z MG._rez.sizes velikosti mimo rozsah (jen u samoobsluhy). true = něco odebráno.
  function pruneRez() {
    var R = MG._rez, hit = false;
    if (!R || !R.sizes || !rezCapActive()) return false;
    ['rider', 'passenger'].forEach(function (g) {
      var o = R.sizes[g];
      if (!o) return;
      Object.keys(o).forEach(function (k) {
        if (o[k] && !inRange(k, o[k])) { delete o[k]; hit = true; }
      });
    });
    return hit;
  }

  var lastActive = null;
  function hookRez() {
    if (typeof MG._accessorySizes === 'function' && !MG._accessorySizes._mgSsCap) {
      var origSizes = MG._accessorySizes;
      MG._accessorySizes = function (type) {
        var list = origSizes.apply(this, arguments);
        return rezCapActive() ? MG._ssCapGearSizes(type, list, true, false) : list;
      };
      MG._accessorySizes._mgSsCap = true;
    }
    if (typeof MG._rerenderGearPanels === 'function' && !MG._rerenderGearPanels._mgSsCap) {
      var origRender = MG._rerenderGearPanels;
      MG._rerenderGearPanels = function () {
        pruneRez();
        return origRender.apply(this, arguments);
      };
      MG._rerenderGearPanels._mgSsCap = true;
    }
    if (typeof MG._rezApplySelfServiceTimes === 'function' && !MG._rezApplySelfServiceTimes._mgSsCap) {
      var origTimes = MG._rezApplySelfServiceTimes;
      MG._rezApplySelfServiceTimes = function () {
        var res = origTimes.apply(this, arguments);
        try {
          var active = rezCapActive();
          var changed = active !== lastActive;
          lastActive = active;
          if ((pruneRez() || changed) && typeof MG._rerenderGearPanels === 'function') MG._rerenderGearPanels();
        } catch (e) {
          console.warn('[REZ] self-service gear sizes failed:', e);
        }
        return res;
      };
      MG._rezApplySelfServiceTimes._mgSsCap = true;
      MG._rezApplySelfServiceTimes._mgSsHooked = origTimes._mgSsHooked; // selfservice.js nebalí znovu
    }
  }
  hookRez();
})();
