/* Seznam rezervací (/upravit-rezervaci): „Nadcházející“ až do vydání motorky.
 *
 * Zadání majitele 2026-09-29: rezervace je všude „Nadcházející“, dokud
 * zákazník nepodepíše předávací protokol (samoobslužná i obslužná pobočka) —
 * stejně jako Velín a mobilní appka (Reservation.displayStatus). DB drží
 * vydání ve `status='active'`: živý strážce _gate_obsluzna_activation pustí
 * rezervaci na pobočce do `active` až po podpisu protokolu.
 *
 * Jádro (_displayStatus) je čistě datumové a navíc porovnává timestamptz jako
 * text (v den začátku „Nadcházející“, od druhého dne „Probíhá“ bez ohledu na
 * převzetí). Na jádrovém _displayStatus ale visí i záložky úprav (posun jen
 * u upcoming, prodloužení/zkrácení, guard isActive) — ty se NEMĚNÍ: pravidlo
 * vydání platí JEN během vykreslení seznamu (štítek, filtr, počty, řazení).
 * Svoz / přistavení (bez protokolu na pobočce) = kalendář. Nic se nenačítá
 * navíc — status, pickup_* i motorcycles.branches.type jsou v select jádra.
 */
(function () {
  var MG = window.MG;
  var ER = MG && MG._editRez;
  if (!ER || typeof ER._renderList !== 'function' || typeof ER._displayStatus !== 'function') return;

  var core = ER._displayStatus;

  function listStatus(b) {
    if (!b || ER._isMockMode) return core(b);
    if (b.status === 'cancelled') return 'cancelled';
    if (b.status === 'completed') return 'completed';
    var today = ER._toIsoDate(new Date());
    var s = ER._normIso(b.start_date);
    var e = ER._normIso(b.end_date);
    if (!today || !s || !e) return core(b);
    if (e < today) return 'completed';
    if (s > today) return 'upcoming';
    var br = b.motorcycles && b.motorcycles.branches;
    var type = br && br.type;
    var delivery = b.pickup_method === 'delivery' || String(b.pickup_address || '').trim() !== '';
    var branchHandover = (type === 'samoobslužná' || type === 'obslužná') && !delivery;
    return branchHandover && b.status !== 'active' ? 'upcoming' : 'active';
  }

  var render = ER._renderList;
  ER._renderList = function () {
    ER._displayStatus = listStatus;
    try {
      return render.apply(this, arguments);
    } finally {
      ER._displayStatus = core;
    }
  };
})();
