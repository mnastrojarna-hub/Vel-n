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

  // Manuální vratka (rezervace bez Stripe platby — QR/převod/hotově): peníze
  // jdou převodem na účet do 14 dnů. Heuristika dle chybějícího payment intentu
  // (_loadBookings ho selectuje); autoritativní je odpověď process-refund
  // (manual:true) tam, kde ji voláme přímo (gear/swap).
  function manualRefundLikely(b) {
    return !!b && !b.stripe_payment_intent_id;
  }
  function manualNoteHtml() {
    return '<br><span class="muted" style="font-size:.9em">' + MG.t('editRez.refund.manualNote') + '</span>';
  }

  // ---- 1b) Zkrácení: hláška o manuální vratce (převod na účet do 14 dnů) ----
  // Jinak 1:1 replika jádra (server RPC shorten_booking_with_refund, serverové
  // refund_amount/refund_percent, mapa chybových kódů).
  ER._submitShorten = async function (newStart, newEnd, reason, cliAmount, cliPct) {
    var b = ER.selectedBooking;
    ER._setBusy(true);
    try {
      var res = await window.sb.rpc('shorten_booking_with_refund', {
        p_booking_id: b.id, p_new_start: newStart, p_new_end: newEnd, p_reason: reason || null
      });
      if (res.error || !res.data || res.data.success === false) {
        console.error('[editRez] shorten err', res.error, res.data);
        var key = {
          wrong_status: 'editRez.err.wrongStatus', not_paid: 'editRez.err.notPaid',
          active_start_locked: 'editRez.err.activeStartLocked', not_a_shortening: 'editRez.err.notShortening',
          invalid_range: 'editRez.err.invalidRange', no_change: 'editRez.err.invalidRange',
          no_diff: 'editRez.err.invalidRange', not_found: 'editRez.err.notFound',
          unauthenticated: 'editRez.login.error'
        }[res.data && res.data.error] || 'editRez.err.generic';
        ER._showError(MG.t(key));
        return;
      }
      var amount = res.data.refund_amount != null ? res.data.refund_amount : cliAmount;
      var pct = res.data.refund_percent != null ? res.data.refund_percent : cliPct;
      var text = (pct === 0 || amount <= 0)
        ? MG.t('editRez.shorten.successNoRefund')
        : MG.t('editRez.shorten.success', { amount: MG.formatPrice(amount), percent: pct });
      if (amount > 0 && manualRefundLikely(b)) text += manualNoteHtml();
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
      console.error('[editRez] shorten exception', e);
      ER._showError(MG.t('editRez.err.generic'));
    } finally {
      ER._setBusy(false);
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
      if (srvAmount > 0 && manualRefundLikely(b)) text += manualNoteHtml();
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

  // ---- 5) Late-pickup půlden (sleva 50 % na 1. den od 12:00) ----
  // a) Záložky Prodloužit i Zkrátit dostávají VLASTNÍ pole času vyzvednutí —
  //    změna termínu a času jde v JEDNOM kroku (jedna platba/vratka).
  // b) Náhled ceny prodloužení (a zkrácení se změnou času) počítá SERVER přes
  //    apply_booking_changes dry-run (varianta B slevy + late-pickup + storno),
  //    klientský odhad se skryje — zákazník vidí přesně to, co se strhne/vrátí.
  // c) Zkrácení bez změny času zůstává na shorten_booking_with_refund; klientský
  //    náhled se dorovná o late-pickup členy (zrcadlí serverový vzorec
  //    (orig − oldLate) − (new − newLate), tedy ztrátu slevy pod 2 dny).
  // d) _applyPendingAfterPayment po platbě dopíše pickup_time z payloadu a
  //    přepočte late_pickup_discount_amount (idempotentní s webhook-receiverem).
  var hm = function (x) { return String(x || '').slice(0, 5); };

  function isActive(b) { return b && 'active' === ER._displayStatus(b); }

  function injectTimeField(formEl, anchorEl, inputId, booking) {
    if (!formEl || !anchorEl || document.getElementById(inputId)) return null;
    var lbl = document.createElement('label');
    lbl.className = 'erez-loc-time';
    lbl.innerHTML = '<span class="erez-loc-time-label">⏰ ' + MG.t('editRez.loc.pickupTime') +
      '</span><input type="time" id="' + inputId + '" step="900" value="' + hm(booking.pickup_time) + '">';
    var hint = document.createElement('div');
    hint.className = 'muted';
    hint.style.cssText = 'font-size:.85rem;margin:.2rem 0 .6rem';
    hint.textContent = '🌗 ' + MG.t('editRez.timeHint12');
    formEl.insertBefore(lbl, anchorEl);
    formEl.insertBefore(hint, anchorEl);
    return document.getElementById(inputId);
  }

  function timeChangedIn(inputId, booking) {
    var tv = document.getElementById(inputId);
    return !!(tv && tv.value && hm(tv.value) !== hm(booking.pickup_time));
  }

  // Serverový dry-run náhled: přidá autoritativní blok do summary (s markerem,
  // aby ho MutationObserver nepovažoval za re-render jádra) a skryje klientský
  // řádek s odhadem. CTA se řídí odpovědí serveru.
  function renderServerPreview(sum, cta, data) {
    var bd = (data && data.breakdown) || {};
    var from = Number(bd.late_pickup_from || 0), to = Number(bd.late_pickup_to || 0);
    var net = Number(data.net_diff || 0), refund = Number(data.refund_amount || 0);
    var rows = '';
    if (to !== from) {
      var delta = to - from;
      rows += '<div class="erez-loc-calc-row"><span>🌗 ' + MG.t('editRez.detail.priceLatePickup') +
        '</span><strong>' + (delta > 0 ? '−' : '+') + MG.formatPrice(Math.abs(delta)) + '</strong></div>';
    }
    var cls = net > 0 ? 'erez-loc-diff-pay' : (net < 0 || refund > 0) ? 'erez-loc-diff-refund' : '';
    var label = net > 0 ? MG.t('editRez.loc.calc.surchargeStripe')
      : (net < 0 || refund > 0) ? MG.t('editRez.loc.calc.refund') : MG.t('editRez.loc.calc.noChange');
    var amount = net > 0 ? net : (refund || Math.abs(net));
    rows += '<div class="erez-loc-calc-row erez-loc-calc-total ' + cls + '"><span>' + label +
      '</span><strong>' + MG.formatPrice(amount) + '</strong></div>';
    if (net < 0 && Number(bd.storno_pct) < 100) {
      rows += '<div class="muted" style="font-size:.85rem;margin-top:.25rem">' +
        MG.t('editRez.shorten.refund', { amount: MG.formatPrice(refund), percent: Number(bd.storno_pct || 0) }) + '</div>';
    }
    writeServerBlock(sum, rows);
    var clientLine = sum.querySelector('.line');
    if (clientLine) clientLine.style.display = 'none';
    if (cta) cta.disabled = !(net !== 0 || refund > 0);
  }

  function writeServerBlock(sum, innerHtml) {
    Array.prototype.forEach.call(sum.querySelectorAll('[data-server-preview]'), function (n) { n.remove(); });
    var wrap = document.createElement('div');
    wrap.className = 'erez-loc-calc';
    wrap.setAttribute('data-server-preview', '1');
    wrap.innerHTML = innerHtml;
    sum.appendChild(wrap);
    return wrap;
  }

  // Observer na summary: jádro po každé změně kalendáře přepíše obsah svým
  // klientským odhadem → my na to navážeme ověření serverem. Vlastní zápisy
  // jsou označené data-server-preview a ignorují se.
  function hookSummary(sumId, onCoreRender) {
    var sum = document.getElementById(sumId);
    if (!sum) return;
    var timer = null;
    var sched = function () { clearTimeout(timer); timer = setTimeout(onCoreRender, 350); };
    new MutationObserver(function (muts) {
      var foreign = muts.some(function (m) {
        return Array.prototype.some.call(m.addedNodes, function (n) {
          return !(n.nodeType === 1 && n.hasAttribute && n.hasAttribute('data-server-preview'));
        });
      });
      if (foreign) sched();
    }).observe(sum, { childList: true });
    return sched;
  }

  function serverDryRun(booking, payload, sumId, ctaId, seqBox) {
    var sum = document.getElementById(sumId);
    var cta = document.getElementById(ctaId);
    if (!sum) return;
    var my = ++seqBox.n;
    writeServerBlock(sum, '<div class="muted">' + MG.t('editRez.loc.calc.verifying') + '</div>');
    if (cta) cta.disabled = true;
    window.sb.rpc('apply_booking_changes', Object.assign({ p_booking_id: booking.id, p_dry_run: true }, payload))
      .then(function (res) {
        if (my !== seqBox.n || !sum.isConnected) return;
        var data = res && res.data;
        if (res.error || !data || data.success === false) {
          var code = data && data.error;
          if (code === 'no_change') {
            writeServerBlock(sum, '<div class="muted">' + MG.t('editRez.extend.noChange') + '</div>');
          } else if (code === 'overlap') {
            writeServerBlock(sum, '<div class="error">' + MG.t('editRez.extend.unavailable') + '</div>');
          } else {
            console.warn('[editRez] dry-run failed', code, res.error);
            writeServerBlock(sum, '<div class="error">' + MG.t('editRez.err.generic') + '</div>');
          }
          if (cta) cta.disabled = true;
          return;
        }
        renderServerPreview(sum, cta, data);
      })
      .catch(function (e) {
        console.warn('[editRez] dry-run exception', e);
        if (my === seqBox.n && sum.isConnected) writeServerBlock(sum, '');
      });
  }

  // -- Prodloužit: pole času + serverový náhled --------------------------------
  var origRenderExtend = ER._renderTabExtend;
  ER._renderTabExtend = async function () {
    var r = await origRenderExtend.apply(this, arguments);
    try {
      var b = ER.selectedBooking;
      var form = document.getElementById('edit-rez-extend-form');
      var sum = document.getElementById('edit-rez-extend-summary');
      if (b && form && sum) {
        var seqBox = { n: 0 };
        if (!isActive(b)) {
          var tv = injectTimeField(form, sum, 'edit-rez-extend-time', b);
          tv && tv.addEventListener('change', function () { previewExtend(); });
        }
        var previewExtend = function () {
          var a = ER._normIso(b.start_date), d = ER._normIso(b.end_date);
          var s = form.newStart.value, e2 = form.newEnd.value;
          if (!s || !e2 || s > a || e2 < d) return; // jádro už ukázalo chybu
          var tCh = timeChangedIn('edit-rez-extend-time', b);
          if (s === a && e2 === d && !tCh) return; // beze změny — nech jádro
          var p = { p_new_start: s, p_new_end: e2 };
          if (tCh) p.p_new_pickup_time = hm(document.getElementById('edit-rez-extend-time').value) + ':00';
          serverDryRun(b, p, 'edit-rez-extend-summary', 'edit-rez-extend-cta', seqBox);
        };
        var sched = hookSummary('edit-rez-extend-summary', previewExtend);
        // první ověření po resume (jádro už mohlo summary vyplnit)
        sched && sched();
      }
    } catch (e) { console.warn('[editRez] extend late-pickup setup failed', e); }
    return r;
  };

  // Prodloužení: submit včetně času (jedna operace). Ostatní logika (serverová
  // cena, resume tvar) zůstává z bloku 1 výše.
  ER._submitExtend = async function (newStart, newEnd) {
    var b = ER.selectedBooking;
    if (!b) return;
    var origStart = ER._normIso(b.start_date);
    var origEnd = ER._normIso(b.end_date);
    var tCh = timeChangedIn('edit-rez-extend-time', b);
    if (!newStart || !newEnd || newStart > origStart || newEnd < origEnd ||
        (newStart === origStart && newEnd === origEnd && !tCh)) {
      ER._showError(MG.t('editRez.err.invalidRange'));
      return;
    }
    var cta = document.getElementById('edit-rez-extend-cta');
    var label = cta ? cta.textContent : '';
    if (cta) { cta.disabled = true; cta.textContent = MG.t('editRez.extend.creating'); }
    var origSave = ER._saveResume;
    if (origSave) {
      ER._saveResume = function () {
        return origSave.call(ER, 'extend', { newStart: newStart, newEnd: newEnd });
      };
    }
    try {
      var payload = { p_new_start: newStart, p_new_end: newEnd };
      if (tCh) payload.p_new_pickup_time = hm(document.getElementById('edit-rez-extend-time').value) + ':00';
      await ER._submitChange(payload);
    } finally {
      if (origSave) ER._saveResume = origSave;
      if (cta) { cta.disabled = false; cta.textContent = label; }
    }
  };

  // -- Zkrátit: pole času + korektní náhled ------------------------------------
  var origRenderShorten = ER._renderTabShorten;
  ER._renderTabShorten = function () {
    var r = origRenderShorten.apply(this, arguments);
    try {
      var b = ER.selectedBooking;
      var form = document.getElementById('edit-rez-shorten-form');
      var sum = document.getElementById('edit-rez-shorten-summary');
      if (b && form && sum) {
        var seqBox = { n: 0 };
        if (!isActive(b)) {
          var tv = injectTimeField(form, form.querySelector('label') || sum, 'edit-rez-shorten-time', b);
          tv && tv.addEventListener('change', function () { previewShorten(); });
        }
        var previewShorten = function () {
          var n = ER._normIso(b.start_date), o = ER._normIso(b.end_date);
          var rS = form.newStart.value, iE = form.newEnd.value;
          if (!rS || !iE || rS < n || iE > o) return;
          var tCh = timeChangedIn('edit-rez-shorten-time', b);
          if (tCh) {
            // kombinovaná (či časová) změna → autoritativní serverový náhled
            var p = { p_new_pickup_time: hm(document.getElementById('edit-rez-shorten-time').value) + ':00' };
            if (rS !== n) p.p_new_start = rS;
            if (iE !== o) p.p_new_end = iE;
            serverDryRun(b, p, 'edit-rez-shorten-summary', 'edit-rez-shorten-cta', seqBox);
            return;
          }
          if (rS === n && iE === o) return; // beze změny
          // čisté zkrácení → dorovnej klientský odhad o late-pickup členy
          // (zrcadlí shorten_booking_with_refund: (orig − oldLate) − (new − newLate))
          if (typeof MG._latePickupDiscount !== 'function') return;
          var moto = ER.selectedMoto || {};
          var fallback = ER._fallbackDailyRate(b);
          var orig = ER._priceForRange(moto, n, o, fallback);
          var neu = ER._priceForRange(moto, rS, iE, fallback);
          var oldLate = Number(b.late_pickup_discount_amount || 0);
          var newLate = MG._latePickupDiscount(moto, rS, iE, hm(b.pickup_time));
          var diff = Math.max(0, Math.round((orig - oldLate) - (neu - newLate)));
          if (diff <= 0) return;
          var mSide = iE < o ? iE : rS;
          var pct = ER._refundPercentFor(b, mSide);
          var refund = Math.round(diff * pct / 100);
          if (Number(form.dataset.refund || 0) === refund) return;
          form.dataset.refund = String(refund);
          form.dataset.pct = String(pct);
          var line = sum.querySelector('.line');
          if (line) {
            line.innerHTML = 0 === pct
              ? MG.t('editRez.shorten.refundZero')
              : MG.t('editRez.shorten.refund', { amount: MG.formatPrice(refund), percent: pct });
          }
          if (newLate !== oldLate) {
            writeServerBlock(sum, '<div class="erez-loc-calc-row"><span>🌗 ' +
              MG.t('editRez.detail.priceLatePickup') + '</span><strong>' +
              (newLate > oldLate ? '−' : '+') + MG.formatPrice(Math.abs(newLate - oldLate)) + '</strong></div>');
          }
        };
        hookSummary('edit-rez-shorten-summary', previewShorten);
      }
    } catch (e) { console.warn('[editRez] shorten late-pickup setup failed', e); }
    return r;
  };

  // Zkrácení SE ZMĚNOU času → serverová cesta apply_booking_changes (jedna
  // operace, vratka/doplatek dle jádra); beze změny času původní shorten RPC.
  var guardSubmitShorten = ER._submitShorten;
  ER._submitShorten = async function (newStart, newEnd, reason, cliAmount, cliPct) {
    var b = ER.selectedBooking;
    if (b && timeChangedIn('edit-rez-shorten-time', b)) {
      var payload = {
        p_new_pickup_time: hm(document.getElementById('edit-rez-shorten-time').value) + ':00'
      };
      var n = ER._normIso(b.start_date), o = ER._normIso(b.end_date);
      if (newStart && newStart !== n) payload.p_new_start = newStart;
      if (newEnd && newEnd !== o) payload.p_new_end = newEnd;
      if (reason) payload.p_reason = reason;
      return ER._submitChange(payload);
    }
    return guardSubmitShorten.call(this, newStart, newEnd, reason, cliAmount, cliPct);
  };

  // -- Po zaplaceném doplatku: dopiš čas + přepočti late slevu -----------------
  // Webhook-receiver je autoritativní (zapisuje total_price i late sloupec);
  // tohle je idempotentní klientská pojistka pro případ, že webhook selže.
  var origApplyPending = ER._applyPendingAfterPayment;
  ER._applyPendingAfterPayment = async function (id) {
    var payload = null;
    try {
      var raw = localStorage.getItem('editRez_pending_' + id);
      if (raw) payload = (JSON.parse(raw) || {}).payload || null;
    } catch (e) { /* noop */ }
    var ok = await origApplyPending.apply(this, arguments);
    if (ok && payload) {
      try {
        var d = {};
        if (payload.p_new_pickup_time) d.pickup_time = payload.p_new_pickup_time;
        var bRes = await window.sb.from('bookings')
          .select('moto_id,start_date,end_date,pickup_time').eq('id', id).maybeSingle();
        var cur = bRes && bRes.data;
        if (cur) {
          var pt = d.pickup_time || cur.pickup_time || null;
          var lr = await window.sb.rpc('_late_pickup_discount', {
            p_moto_id: payload.p_new_moto_id || cur.moto_id,
            p_start: payload.p_new_start || cur.start_date,
            p_end: payload.p_new_end || cur.end_date,
            p_pickup_time: pt
          });
          if (!lr.error && lr.data != null && isFinite(Number(lr.data))) {
            d.late_pickup_discount_amount = Number(lr.data);
          }
        }
        if (Object.keys(d).length) await window.sb.from('bookings').update(d).eq('id', id);
      } catch (e) { console.warn('[editRez] late-pickup post-apply warn', e); }
    }
    return ok;
  };
})();
