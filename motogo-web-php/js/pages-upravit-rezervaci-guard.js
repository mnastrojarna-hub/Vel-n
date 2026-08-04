// ===== MotoGo24 — Upravit rezervaci: serverová autorita ceny + opravy jádra =====
// Jádro js/pages-upravit-rezervaci.js je MINIFIKOVANÉ a NEUPRAVUJE se — opravy
// se dělají zvenčí přetížením metod MG._editRez (stejná technika jako swap/gear).
// Tento soubor se načítá POSLEDNÍ (po resume.js), viz pages/upravit-rezervaci.php.
//
// Co opravuje (viz analýza úpravových flow 2026-08-04):
//   1) _submitExtend — doplatek prodloužení počítal KLIENT (_priceForRange) a šel
//      na Stripe bez serverové validace překryvu/zámků a bez slev (varianta B,
//      late-pickup). Nově deleguje na _submitChange({p_new_start,p_new_end}) =
//      stejná cesta jako záložka Místo: apply_booking_changes ověří rozsah,
//      overlap i zámky a vrátí serverové net_diff/new_total; doplatek jde na
//      Stripe se serverovými částkami (+ metadata.chg pojistka webhooku).
//      Vedlejší zisk: 100% sleva/voucher už neplatí ceníkový rozdíl.
//   2) _submitCancel — jádro testovalo jen transportní chybu (res.error), takže
//      RPC odmítnutí {error:'…'} prošlo jako úspěch (falešná zelená obrazovka),
//      a zobrazená vratka byla klientský odhad místo serverového čísla.
//   3) _finishDocs — doplnění dokladů z /upravit-rezervaci nenastavovalo
//      docs_completed_at (signál pro reserved mail) — volal ho jen rezervační
//      formulář. Wrap doplní set_web_booking_docs_completed best-effort.
//   4) Hygiena editRez_pending_* — payload nedokončeného checkoutu zůstával
//      v localStorage navždy; nově TTL úklid + smazání při návratu přes
//      cancel_url (?edit_booking=<id>).
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  // ---- 1) Prodloužení: cena a validace ze serveru (apply_booking_changes) ----
  ER._submitExtend = async function (newStart, newEnd) {
    var b = ER.selectedBooking;
    if (!b) return;
    var origStart = ER._normIso(b.start_date);
    var origEnd = ER._normIso(b.end_date);
    // Prodloužení = start stejný nebo dřívější A konec stejný nebo pozdější,
    // a alespoň jedna strana se mění. Ostatní chyby (overlap, zámek startu
    // u active, wrong_status…) vrací server přes _submitChange.
    if (!newStart || !newEnd || newStart > origStart || newEnd < origEnd ||
        (newStart === origStart && newEnd === origEnd)) {
      ER._showError(MG.t('editRez.err.invalidRange'));
      return;
    }
    var cta = document.getElementById('edit-rez-extend-cta');
    var label = cta ? cta.textContent : '';
    if (cta) { cta.disabled = true; cta.textContent = MG.t('editRez.extend.creating'); }
    // _submitChange ukládá resume jako payload {p_new_start,…}; extend tab ale
    // po návratu čte {newStart,newEnd} — po dobu volání podstrčíme správný tvar.
    var origSave = ER._saveResume;
    if (origSave) {
      ER._saveResume = function () {
        return origSave.call(ER, 'extend', { newStart: newStart, newEnd: newEnd });
      };
    }
    try {
      await ER._submitChange({ p_new_start: newStart, p_new_end: newEnd });
    } finally {
      if (origSave) ER._saveResume = origSave;
      if (cta) { cta.disabled = false; cta.textContent = label; }
    }
  };

  // ---- 2) Storno: číst tělo odpovědi RPC + serverovou částku vratky ----
  // cancel_booking_tracked vrací {success:true, refund_amount, refund_percent}
  // nebo {error:'…'} (bez success). Serverová vratka může být nižší než
  // klientský odhad (strop dle skutečně zaplaceného) — zobrazujeme ji přednostně.
  ER._submitCancel = async function (reason, pct, amount) {
    if (ER.busy) return;
    var b = ER.selectedBooking;
    ER._setBusy(true);
    try {
      var res = await window.sb.rpc('cancel_booking_tracked', { p_booking_id: b.id, p_reason: reason || null });
      var body = res.data || null;
      if (res.error || !body || body.success !== true) {
        var msg = (body && body.error) || (res.error && (res.error.message || res.error.code)) || '';
        console.error('[editRez] cancel failed', { error: res.error, data: body });
        ER._showError(msg || MG.t('editRez.err.generic'));
        return;
      }
      var srvAmount = (body.refund_amount != null) ? body.refund_amount : amount;
      var srvPct = (body.refund_percent != null) ? body.refund_percent : pct;
      var text = MG.t('editRez.cancel.success', { amount: MG.formatPrice(srvAmount), percent: srvPct });
      var content = document.getElementById('edit-rez-tab-content');
      if (content) {
        content.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + text + '</p>' +
          '<button type="button" class="btn btngreen-small" id="edit-rez-back-list">' + MG.t('editRez.list.title') + '</button></div>';
      }
      var back = document.getElementById('edit-rez-back-list');
      if (back) back.addEventListener('click', async function () {
        ER.selectedBooking = null;
        await ER._loadBookings();
        ER._goto('list');
      });
    } catch (e) {
      console.error('[editRez] cancel exception', e);
      ER._showError(MG.t('editRez.err.generic'));
    } finally {
      ER._setBusy(false);
    }
  };

  // ---- 3) Doklady: „Hotovo" nastaví docs_completed_at (signál reserved mailu) ----
  // RPC je EXCEPTION-safe, guard booking_source='web' (app rezervace = no-op).
  var origFinish = ER._finishDocs;
  if (origFinish) {
    ER._finishDocs = async function () {
      var r = await origFinish.apply(this, arguments);
      try {
        var b = ER.selectedBooking;
        if (b && window.sb) {
          await window.sb.rpc('set_web_booking_docs_completed', { p_booking_id: b.id });
        }
      } catch (e) { /* best-effort — nesmí rozbít UI dokladů */ }
      return r;
    };
  }

  // ---- 4) Hygiena editRez_pending_* ----
  var PENDING_TTL_MS = 24 * 60 * 60 * 1000;
  try {
    for (var i = localStorage.length - 1; i >= 0; i--) {
      var k = localStorage.key(i);
      if (!k || (k.indexOf('editRez_pending_') !== 0 && k.indexOf('editRez_swap_pending_') !== 0)) continue;
      var stale = true;
      try {
        var v = JSON.parse(localStorage.getItem(k));
        stale = !v || !v.ts || (Date.now() - v.ts) > PENDING_TTL_MS;
      } catch (e) { /* neparsovatelné = smazat */ }
      if (stale) localStorage.removeItem(k);
    }
  } catch (e) { /* noop */ }
  // Návrat „Zpět" z platební brány (cancel_url = ?edit_booking=<id>) — platba
  // neproběhla, payload nesmí přežít do příštího ?paid_booking návratu.
  try {
    var backId = new URLSearchParams(window.location.search).get('edit_booking');
    if (backId) {
      localStorage.removeItem('editRez_pending_' + backId);
      localStorage.removeItem('editRez_swap_pending_' + backId);
    }
  } catch (e) { /* noop */ }
})();
