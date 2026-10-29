/* MotoGo24 kiosk — výpůjčka výbavy bez motorky (1.3.0, CONTRACT §33; jednotka handover_gear.py). Tři části:
   (1) varianta protokolu #handover pro `active.gear_only`: bez motorky a výbavy motorky, jen objednané položky (výbava navíc se
       nenabízí — každá položka je placená), aspoň jedna převzatá, identita = „Kód šatny“ (handover.js volá rows/form/apply/key);
   (2) dotaz „Vracíš všechnu výbavu?“ (#gear-return) ze snapshotu `st.handover.gear.return` → POST /api/gear/return {answer};
   (3) modální hláška šatny při vrácení („vrať výbavu a zavři dveře“) a pruh zámku přejímky výbavy (app.js renderWardrobe).
   Vanilla JS; texty `hg.*` v ui/i18n-gear.js, `gr.*` v ui/i18n-gear-return.js, styl ui/style-gear.css. */
'use strict';
window.MG = window.MG || {};

MG.HandoverGear = (function () {
  const $ = (id) => document.getElementById(id);
  const POST_MS = 10000;
  const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' };
  let deps = null;    // { post, showStatus, getState } (handover.js init)
  const S = { ask: null, key: '', answered: '', timer: null, sending: false, state: null };

  function setText(el, text) { if (el && el.textContent !== text) el.textContent = text; }
  /** Statický text s přepínatelným klíčem: data-i18n se mění, aby ho MG.i18n.applyStatic překládal i po změně jazyka. */
  function swap(el, k) {
    if (!el) return;
    if (el.getAttribute('data-i18n') !== k) el.setAttribute('data-i18n', k);
    setText(el, MG.i18n.t(k));
  }

  /* ── (1) protokol bez motorky ─────────────────────────────────────────── */
  const isGear = (a) => !!(a && a.gear_only);
  /** Klíč textu pro položku: výbava bez motorky → `gear`, jinak původní klíč `moto`. */
  const key = (a, moto, gear) => (isGear(a) ? gear : moto);
  function apply(a) {
    const on = isGear(a), ho = $('handover');
    if (!ho) return;
    ho.classList.toggle('gear-only', on);
    swap(document.querySelector('#ho-code-sec .ho-label'), on ? 'hg.code' : 'ho.code');
    swap(document.querySelector('#ho-code-sec .ho-code-hint'), on ? 'hg.codeHint' : 'ho.codeHint');
    swap(document.querySelector('#handover .ho-intro'), on ? 'hg.intro' : 'ho.intro');
    const moto = $('ho-moto');
    swap(moto && moto.parentElement.querySelector('.k'), on ? 'hg.subject' : 'ho.moto');
  }
  /** Řádky výbavy: jen objednané položky (sloupce řidiče) — bez spolujezdce a bez výbavy navíc. */
  function rows(a) {
    const gear = Array.isArray(a && a.data && a.data.gear) ? a.data.gear : [];
    return gear.map((g) => Object.assign({}, g, { who: 'rider', booked: true }));
  }
  /** Formulář pro edge: bez výbavy motorky, km a výbavy navíc. */
  function form(f) { delete f.moto_equipment; delete f.mileage; f.gear_add = false; return f; }

  /* ── (2) dotaz na vrácení výbavy ──────────────────────────────────────── */
  const askOf = (st) => { const g = st && st.handover && st.handover.gear; return (g && g.return) || null; };
  function fmtDate(v) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v || ''));
    if (!m) return v ? String(v) : '';
    try { return new Intl.DateTimeFormat(LOCALE[MG.i18n.lang] || 'cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }).format(new Date(+m[1], +m[2] - 1, +m[3])); }
    catch (e) { return m[3] + '. ' + m[2] + '. ' + m[1]; }
  }
  function who(r) {
    const d = r.data || {}, from = fmtDate(d.start_date), to = fmtDate(d.end_date);
    const period = from && to && from !== to ? from + ' – ' + to : (from || to);
    return [d.customer_name, period].filter(Boolean).join(' · ');
  }
  function tick() {
    const r = S.ask;
    if (!r) return;
    const left = Math.ceil((Date.parse(r.expires_at || '') - Date.now()) / 1000);
    setText($('gr-timer'), !isFinite(left) || left < 0 ? '' : left > 60
      ? MG.i18n.t('ho.autoCloseMin', { m: Math.ceil(left / 60) }) : MG.i18n.t('ho.autoClose', { s: left }));
    if (isFinite(left) && left < -3) hide();      // jednotka dotaz zruší sama (WS); pojistka při výpadku WS
  }
  function paint() {
    const r = S.ask;
    if (!r) return;
    setText($('gr-who'), who(r));
    const m = Number(r.grace_min);
    setText($('gr-yes-sub'), m > 0 ? MG.i18n.t('gr.yesSub', { m }) : MG.i18n.t('gr.yesSubNow'));
    tick();
  }
  function setBusy(on) {
    $('gr-yes').disabled = on; $('gr-no').disabled = on;
    $('gr-saving').hidden = !on;
  }
  function setMsg(k) { const el = $('gr-msg'); setText(el, k ? MG.i18n.t(k) : ''); el.hidden = !k; }
  function show(r, k) {
    S.ask = r; S.key = k;
    setMsg(null); setBusy(false);
    $('gear-return').hidden = false;
    paint();
    clearInterval(S.timer);
    S.timer = setInterval(tick, 1000);
  }
  function hide() {
    if (!S.ask) return;
    S.ask = null; S.key = '';
    clearInterval(S.timer); S.timer = null;
    $('gear-return').hidden = true;
    setBusy(false);
  }
  async function answer(yes) {
    const r = S.ask;
    if (!r || S.sending) return;
    S.sending = true; setMsg(null); setBusy(true);
    const res = await deps.post('/api/gear/return', { booking_id: r.booking_id, answer: yes ? 'yes' : 'no' }, POST_MS);
    S.sending = false; setBusy(false);
    if (!res.ok && res.error !== 'not_pending') { setMsg('gr.failed'); return; }
    S.answered = S.key;                      // snapshot může dotaz nést ještě chvíli — znovu ho neukazovat
    hide();
    if (!res.ok) {                           // dotaz mezitím vypršel / šatna znovu otevřena — „Ano“ nesmí zmizet potichu
      if (yes) deps.showStatus('error', MG.i18n.t('gr.expiredTitle'), MG.i18n.t('gr.expired'), true);
      return;
    }
    if (res.confirmed) deps.showStatus('success', MG.i18n.t('gr.doneTitle'), MG.i18n.t('gr.done'), true);
    else deps.showStatus('success', MG.i18n.t('gr.keepTitle'), MG.i18n.t('gr.keep'), true);
  }
  /** Volá handover.js onState s každým snapshotem. */
  function onState(st) {
    S.state = st;
    const r = askOf(st);
    if (!r) { if (!S.sending) hide(); return; }
    const k = r.booking_id + '|' + (r.expires_at || '');
    if (k === S.answered) return;
    if (k !== S.key) show(r, k);
    else { S.ask = r; paint(); }
  }

  /* ── (3) hláška šatny a pruh zámku (app.js renderWardrobe) ────────────── */
  /** Titulek modální hlášky šatny: návštěva VRÁCENÍ výbavy → „vrať výbavu a zavři dveře“ (+ podtitulek), jinak null. */
  function wardrobe(st, wz) {
    const g = st && st.handover && st.handover.gear;
    const ret = !!(wz && g && g.visits && g.visits[wz.booking_id] === 'return');
    swap(document.querySelector('#wardrobe .wd-sub'), ret ? 'gr.closeSub' : 'ho.closeSub');
    if (!ret) return null;
    const n = MG.i18n.doorNo(wz);
    return n != null ? MG.i18n.t('gr.closeNo', { n }) : MG.i18n.t('gr.close');
  }
  function lockBar(lock) { swap(document.querySelector('#handover-lock .flow-title'), lock && lock.gear_only ? 'hg.lockTitle' : 'ho.lockTitle'); }
  /** Podtitulek chyby `handover_in_progress` při zámku výbavy (jiný jazyk než čeština; česky posílá text jednotka). */
  function errorSubtitle(res) {
    const l = S.state && S.state.handover && S.state.handover.lock;
    return res && res.error === 'handover_in_progress' && l && l.gear_only ? MG.i18n.t('hg.inProgress') : '';
  }

  function rerender() { if (S.ask) paint(); }
  function init(d) {
    deps = d;
    if (!$('gear-return')) return;
    MG.i18n.renderBar($('gr-lang'));
    $('gr-yes').addEventListener('click', (e) => { e.preventDefault(); answer(true); });
    $('gr-no').addEventListener('click', (e) => { e.preventDefault(); answer(false); });
  }
  /** Fyzická klávesnice během dotazu: vše spolknout (Enter nesmí odeslat skrytý PIN ani odpovědět za zákazníka). */
  const keys = { onChar() {}, onBackspace() {}, onEnter() {}, onClear() {}, onEscape() {} };

  return { init, onState, rerender, apply, rows, form, key, isGear, wardrobe, lockBar, errorSubtitle, keys,
    isVisible: () => !!S.ask };
})();
