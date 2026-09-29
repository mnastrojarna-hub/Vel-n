/* Seznam rezervací (/upravit-rezervaci): „Nadcházející“ až do vydání motorky.
 *
 * Zadání majitele 2026-09-29: rezervace je všude „Nadcházející“, dokud
 * zákazník nepodepíše předávací protokol — stejně jako Velín (reserved =
 * „Nadcházející“) a mobilní appka (Reservation.displayStatus). DB drží vydání
 * ve `status='active'`: živý strážce _gate_obsluzna_activation pustí rezervaci
 * na pobočce do `active` až po podpisu protokolu (samoobslužná i obslužná,
 * na obslužné i u přistavení); vydaná večer před začátkem je už aktivní.
 *
 * Jádro (_displayStatus) je čistě datumové a navíc porovnává timestamptz jako
 * text (v den začátku „Nadcházející“, od druhého dne „Probíhá“ bez ohledu na
 * převzetí). Na jádrovém _displayStatus ale visí i záložky úprav (posun jen
 * u upcoming, prodloužení/zkrácení, guard isActive) — ty se NEMĚNÍ: pravidlo
 * vydání platí JEN během vykreslení seznamu (štítek, filtr, počty, řazení).
 * Nic se nenačítá navíc — status i data jsou v select jádra.
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
    var e = ER._normIso(b.end_date);
    if (!today || !e) return core(b);
    if (e < today) return 'completed';
    return b.status === 'active' ? 'active' : 'upcoming';
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
