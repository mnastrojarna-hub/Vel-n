/* MotoGo24 kiosk — stav tachometru při VRÁCENÍ motorky (overlay #odometer; rozhodnutí majitele 2026-09-29, kontrakt §30).
   app.js po odpovědi `odometer_required` z /api/pin zavolá open(code, res): číselník (MG.Keyboard 'pin', max 7 číslic),
   placeholder = poslední známý stav `res.odometer.hint` + jednotka. Potvrdit → /api/pin {code, odometer}; mimo rozsah
   (`odometer_invalid` + reason too_low | too_high | not_number) displej žádá opravu a kóje zůstává zavřená. Kód motorky
   drží JEN v paměti modulu — Zpět, Esc i nečinnost `timings.odometer_idle_s` (výchozí 120 s) ho zapomenou.
   Vanilla JS; závisí na MG.i18n (+ i18n-odometer.js, `ho.back`/`ho.autoClose*` z i18n-handover.js) a MG.Keyboard. */
'use strict';
window.MG = window.MG || {};

MG.Odometer = (function () {
  const $ = (id) => document.getElementById(id);
  const MAX_DIGITS = 7, POST_TIMEOUT_MS = 20000, DEFAULT_IDLE_S = 120;
  const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' };
  let deps = null;   // { post, showStatus, hideStatus, getState }
  const S = { code: '', odo: null, zone: null, digits: '', busy: false, msg: null, kb: null, timer: null, deadline: 0 };

  function setText(el, text) { if (el && el.textContent !== text) el.textContent = text; }
  const unitOf = (u) => MG.i18n.t(u === 'mh' ? 'od.mh' : 'od.km');
  const unit = () => unitOf(S.odo && S.odo.unit);
  function fmt(n) {
    try { return new Intl.NumberFormat(LOCALE[MG.i18n.lang] || 'cs-CZ', { maximumFractionDigits: 0 }).format(Number(n)); }
    catch (e) { return String(n); }
  }
  const findZone = (zone) => (zone == null ? null : ((deps.getState() || {}).zones || []).find((z) => z.zone === zone) || null);

  /* ── Nečinnost: odpočet z timings.odometer_idle_s (UI) — pak zavřít a zapomenout kód ── */
  function idleMs() {
    const t = ((deps.getState() || {}).timings || {}).odometer_idle_s;
    return (Number(t) > 0 ? Number(t) : DEFAULT_IDLE_S) * 1000;
  }
  function arm() { S.deadline = Date.now() + idleMs(); tick(); }
  function tick() {
    if (!S.code) return;
    const left = Math.ceil((S.deadline - Date.now()) / 1000);
    if (left <= 0 && !S.busy) { close(); return; }
    setText($('od-timer'), left > 60 ? MG.i18n.t('ho.autoCloseMin', { m: Math.ceil(left / 60) }) : MG.i18n.t('ho.autoClose', { s: Math.max(0, left) }));
  }

  /* ── Vykreslení ───────────────────────────────────────────────────────── */
  function msgText() {
    const o = S.odo || {};
    if (!S.msg) return '';
    const txt = S.msg === 'too_low' ? MG.i18n.t('od.tooLow', { min: fmt(o.min), u: unit() })
      : S.msg === 'too_high' ? MG.i18n.t('od.tooHigh', { max: fmt(o.max), u: unit() }) : MG.i18n.t('od.notNumber');
    return txt + '\n' + MG.i18n.t('od.help');
  }
  function paint() {
    const o = S.odo || {}, box = $('od-box');
    if (S.digits) { setText(box, fmt(S.digits) + ' ' + unit()); box.classList.remove('empty'); }
    else { setText(box, (o.hint != null ? fmt(o.hint) : '—') + ' ' + unit()); box.classList.add('empty'); }
    setText($('od-last'), o.hint != null ? MG.i18n.t('od.last', { n: fmt(o.hint), u: unit() }) : '');
    const msg = msgText();
    setText($('od-msg'), msg);
    $('od-msg').hidden = !msg;
    $('od-confirm').disabled = S.busy || !S.digits;
    $('od-back').disabled = S.busy;
    $('od-saving').hidden = !S.busy;
    if (S.kb) S.kb.setEnabled(!S.busy);
  }
  /** Texty závislé na jednotce a jazyce (km / motohodiny); statické popisky řeší data-i18n. */
  function rerender() {
    if (!S.code) return;
    const mh = !!(S.odo && S.odo.unit === 'mh');
    setText($('od-title'), MG.i18n.t(mh ? 'od.titleMh' : 'od.title'));
    setText($('od-intro'), MG.i18n.t(mh ? 'od.introMh' : 'od.intro'));
    const z = findZone(S.zone);
    setText($('od-zone'), z ? MG.i18n.zoneName(z) : S.zone != null ? MG.i18n.t('box', { n: S.zone }) : '');
    paint();
    tick();
  }

  /* ── Otevření / zavření ───────────────────────────────────────────────── */
  function open(code, res) {
    S.code = String(code || ''); S.odo = (res && res.odometer) || {}; S.zone = res ? res.zone : null;
    S.digits = ''; S.busy = false; S.msg = null;
    if (!S.kb) S.kb = MG.Keyboard.build($('od-keys'), { mode: 'pin', onChar, onBackspace, onEnter: confirm, onClear });
    $('odometer').hidden = false;
    clearInterval(S.timer);
    S.timer = setInterval(tick, 1000);
    arm();
    rerender();
  }
  function close() {
    S.code = ''; S.digits = ''; S.odo = null; S.zone = null; S.busy = false; S.msg = null;
    clearInterval(S.timer); S.timer = null;
    $('odometer').hidden = true;
  }

  /* ── Číselník ─────────────────────────────────────────────────────────── */
  function onChar(ch) {
    if (S.busy || !S.code || !/^[0-9]$/.test(ch) || S.digits.length >= MAX_DIGITS) return;
    S.digits = (S.digits === '0' ? '' : S.digits) + ch;
    S.msg = null; arm(); paint();
  }
  function onBackspace() { if (S.busy || !S.digits) return; S.digits = S.digits.slice(0, -1); arm(); paint(); }
  function onClear() { if (S.busy) return; S.digits = ''; arm(); paint(); }

  /* ── Potvrdit: kód motorky znovu + stav tachometru ────────────────────── */
  async function confirm() {
    if (S.busy || !S.code || !S.digits) return;
    S.busy = true; S.msg = null; paint();
    const res = await deps.post('/api/pin', { code: S.code, odometer: S.digits }, POST_TIMEOUT_MS);
    S.busy = false;
    if (!S.code) return;
    if (res.error === 'odometer_invalid' || res.error === 'odometer_required') {
      if (res.odometer) S.odo = res.odometer;
      S.digits = ''; S.msg = res.error === 'odometer_invalid' ? (res.reason || 'not_number') : null;
      arm(); rerender();
      return;
    }
    close();
    if (!res.ok) {
      const cz = MG.i18n.lang === MG.i18n.DEFAULT;
      deps.showStatus('error', MG.i18n.errorTitle(res.error), (cz && res.message) || MG.i18n.errorSubtitle(res.error, res.locked_until), true);
      return;
    }
    const z = findZone(res.zone);
    const name = z ? MG.i18n.zoneName(z) : MG.i18n.t('opened');
    const saved = res.odometer && res.odometer.km != null ? MG.i18n.t('od.saved', { km: fmt(res.odometer.km), u: unitOf(res.odometer.unit) }) : '';
    deps.showStatus('success', MG.i18n.successTitle('motorcycle', z), [MG.i18n.successSubtitle('motorcycle', name, z), saved].filter(Boolean).join('\n'), true);
  }

  function init(d) {
    deps = d;
    $('od-confirm').addEventListener('click', (e) => { e.preventDefault(); confirm(); });
    $('od-back').addEventListener('click', (e) => { e.preventDefault(); if (!S.busy) close(); });
    $('odometer').addEventListener('pointerdown', () => { if (S.code) arm(); }, { passive: true, capture: true });
  }

  /** Fyzická klávesnice, dokud je overlay vidět (app.js): číslice, Enter → potvrdit, Esc → zpět (zapomenout kód). */
  const keys = { onChar, onBackspace, onEnter: confirm, onClear, onEscape: () => { if (!S.busy) close(); } };

  return { init, open, close, rerender, keys, isVisible: () => !!S.code };
})();
