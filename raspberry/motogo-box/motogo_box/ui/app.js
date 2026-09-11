/* MotoGo24 kiosk — hlavní logika: WS klient, zadávání kódu, overlay stavů, dlaždice zón.
   Vanilla JS (offline, bez CDN). Layout je plně responzivní (CSS), žádné škálování plátna. Texty a flow převzaté z Flutter kiosku (kiosk_screen.dart). */
'use strict';
window.MG = window.MG || {};

/* ── Aplikace ───────────────────────────────────────────────────────────── */
(function () {
  const $ = (id) => document.getElementById(id);
  const MAX_LEN = 24, AUTO_HIDE_MS = 6000, WS_RECONNECT_MS = 2000, POLL_MS = 5000, STALE_MS = 4500;
  const LANG_IDLE_MS = 120000;   // po 2 min bez dotyku zpět do výchozího jazyka (další zákazník)
  const S = { state: null, ws: null, wsOk: false, lastStateAt: 0, entry: '', busy: false, mode: 'num',
    pinTimer: null, pinDeadline: 0, hideTimer: null, noticeTs: null, kb: null, langTimer: null, version: null };
  const tiles = new Map();   // zone → { el, json }

  /* ── HTTP ─────────────────────────────────────────────────────────── */
  async function post(path, body, timeoutMs) {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), timeoutMs || 20000);
    try {
      const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}), signal: ctl.signal, cache: 'no-store' });
      let data = null;
      try { data = await r.json(); } catch (e) { data = null; }
      if (!data || typeof data !== 'object') data = { ok: false, error: r.ok ? 'bad_response' : 'network' };
      data.status = r.status;
      return data;
    } catch (e) {
      return { ok: false, error: 'network', status: 0 };
    } finally { clearTimeout(t); }
  }

  /* ── Stav ze serveru (WS + fallback) ──────────────────────────────── */
  function applyState(st) {
    if (!st || typeof st !== 'object') return;
    S.state = st;
    S.lastStateAt = Date.now();
    render();
  }

  function connectWs() {
    if (S.ws) return;
    let ws;
    try { ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'); }
    catch (e) { setTimeout(connectWs, WS_RECONNECT_MS); return; }
    S.ws = ws;
    ws.onopen = () => { S.wsOk = true; updateBanner(); };
    ws.onmessage = (ev) => {
      try {
        const m = JSON.parse(ev.data);
        if (m && m.type === 'state') applyState(m.state);
      } catch (e) { /* ignorovat nevalidní zprávu */ }
    };
    ws.onerror = () => { try { ws.close(); } catch (e) { /* noop */ } };
    ws.onclose = () => { S.ws = null; S.wsOk = false; updateBanner(); setTimeout(connectWs, WS_RECONNECT_MS); };
  }

  async function pollFallback() {
    if (S.wsOk) return;
    try {
      const r = await fetch('/api/state', { cache: 'no-store' });
      if (r.ok) applyState(await r.json());
    } catch (e) { /* server nedostupný — banner */ }
    updateBanner();
  }

  function updateBanner() {
    const down = !S.wsOk && Date.now() - S.lastStateAt > STALE_MS;
    $('banner').hidden = !down;
  }

  /* ── Vykreslení (jen změněné části) ───────────────────────────────── */
  function setText(el, text) { if (el.textContent !== text) el.textContent = text; }

  function render() {
    const st = S.state || {};
    setText($('branch-name'), st.branch_name || '');   // VÝHRADNĚ název z Velína — bez názvu prázdné
    const dot = $('online-dot');
    const cls = st.internet === true ? 'dot dot-on' : 'dot dot-off';
    if (dot.className !== cls) dot.className = cls;
    renderTiles(st.zones || []);
    renderAlert(st);
    if (st.paired === false && !MG.Setup.isVisible()) MG.Setup.show({ cancelable: false });
    else if (st.paired === true && MG.Setup.isVisible() && !MG.Setup.isCancelable()) MG.Setup.hide();   // spárováno jinou cestou (config.yaml, Velín)
    if (st.version) {                      // po update_software načíst nové UI (JS/CSS) — WS by se jen znovu připojil
      if (S.version && S.version !== st.version) { location.reload(); return; }
      S.version = st.version;
    }
    MG.Panel.render(st);
    MG.Diag.onState(st);
    if (st.notice && st.notice.ts && st.notice.ts !== S.noticeTs) {
      S.noticeTs = st.notice.ts;
      if (!S.busy) showStatus(st.notice.kind === 'error' ? 'error' : 'success', st.notice.title || 'Tady jsem 👋', st.notice.subtitle || '', true);
    }
  }

  function tileEl(z) {
    const el = document.createElement('div');
    el.className = 'tile';
    el.innerHTML = '<span class="tile-num"></span><div class="tile-txt"><div class="tile-name"></div>' +
      '<div class="tile-bottom"><span class="tile-state"></span><span class="tile-door"></span></div></div><span class="tile-sig"></span>';
    return el;
  }

  function isOvertime(z) {
    return z.overtime === true || (z.state === 'DOOR_OPEN' && (z.signal || '').toLowerCase() === 'green_pulse')
      || (z.last_event || '').indexOf('SESSION_OVERTIME') === 0;
  }

  function renderTiles(zones) {
    const box = $('zones');
    const cls = 'zones zones-n' + zones.length;   // mřížka dlaždic podle počtu zón (CSS)
    if (box.className !== cls) box.className = cls;
    const seen = new Set();
    let added = false;
    zones.forEach((z) => {
      seen.add(z.zone);
      const j = JSON.stringify(z);
      let t = tiles.get(z.zone);
      if (!t) { t = { el: tileEl(z), json: '' }; tiles.set(z.zone, t); box.appendChild(t.el); added = true; }
      if (t.json === j) return;
      t.json = j;
      const sig = (z.signal || 'off').toLowerCase();
      t.el.className = 'tile sig-' + sig + (z.fault || z.state === 'FAULT' ? ' fault' : '') + (isOvertime(z) ? ' overtime' : '');
      setText(t.el.querySelector('.tile-num'), String(z.box_number != null ? z.box_number : z.zone));
      setText(t.el.querySelector('.tile-name'), MG.i18n.zoneName(z));
      setText(t.el.querySelector('.tile-state'), z.fault ? MG.i18n.fault(z.fault) : MG.i18n.zoneState(z.state));
      setText(t.el.querySelector('.tile-door'), z.door_closed === true ? '🔒' : z.door_closed === false ? '🚪' : '❔');
    });
    tiles.forEach((t, zone) => { if (!seen.has(zone)) { t.el.remove(); tiles.delete(zone); } });
    if (added) box.append(...zones.map((z) => tiles.get(z.zone).el));   // pořadí dle čísla zóny i po doplnění
  }

  function renderAlert(st) {
    const el = $('zone-alert');
    let text = '', kind = '';
    if (st.ready === false && st.last_error) { text = MG.i18n.alert('unit') + st.last_error; kind = 'error'; }
    (st.zones || []).forEach((z) => {
      if (text) return;
      const name = MG.i18n.zoneName(z);
      if (isOvertime(z)) { text = '⚠ ' + MG.i18n.alert('overtime', { z: name }); kind = 'warn'; }
      else if (z.fault || z.state === 'FAULT') { text = '⚠ ' + MG.i18n.alert('fault', { z: name, f: MG.i18n.fault(z.fault) || MG.i18n.fault('fault') }); kind = 'error'; }
    });
    setText(el, text);
    const cls = 'zone-alert' + (kind ? ' ' + kind : '');
    if (el.className !== cls) el.className = cls;
  }

  /* ── Zadávání kódu ────────────────────────────────────────────────── */
  function masked() {
    const sec = (S.state && S.state.security) || {};
    return sec.mask_pin_on_screen !== false;
  }
  function pinTimeoutMs() {
    const t = S.state && S.state.timings && Number(S.state.timings.pin_entry_timeout_s);
    return (t > 0 ? t : 20) * 1000;
  }
  function paintEntry() {
    const box = $('code-box');
    if (!S.entry) { box.textContent = '— — — — — —'; box.classList.add('empty'); }
    else { box.textContent = masked() ? '●'.repeat(S.entry.length) : S.entry.toUpperCase(); box.classList.remove('empty'); }
  }
  function armPinTimeout() {
    clearTimeout(S.pinTimer);
    if (!S.entry) { $('code-timer').hidden = true; return; }
    S.pinDeadline = Date.now() + pinTimeoutMs();
    S.pinTimer = setTimeout(() => { S.entry = ''; paintEntry(); $('code-timer').hidden = true; }, pinTimeoutMs());
  }
  function tickTimer() {
    const el = $('code-timer');
    if (!S.entry || S.busy) { el.hidden = true; return; }
    const left = Math.max(0, Math.ceil((S.pinDeadline - Date.now()) / 1000));
    el.hidden = false;
    setText(el, left + ' s');
  }
  function onChar(ch) { if (S.busy || S.entry.length >= MAX_LEN) return; S.entry += ch; paintEntry(); armPinTimeout(); }
  function onBackspace() { if (S.busy || !S.entry) return; S.entry = S.entry.slice(0, -1); paintEntry(); armPinTimeout(); }
  function onClear() { if (S.busy) return; S.entry = ''; paintEntry(); armPinTimeout(); }
  function toggleMode() { S.mode = S.mode === 'num' ? 'qwerty' : 'num'; buildKeys(); }
  function buildKeys() {
    S.kb = MG.Keyboard.build($('keys'), { mode: S.mode, onChar, onBackspace, onEnter: submit, onClear, onToggle: toggleMode,
      clearLabel: MG.i18n.t('clear') });
    S.kb.setEnabled(!S.busy);
  }

  /* ── Jazyk: lišta v hlavičce, ?lang=xx, návrat k výchozímu po nečinnosti ── */
  function armLangIdle() {
    clearTimeout(S.langTimer);
    if (MG.i18n.lang !== MG.i18n.DEFAULT) S.langTimer = setTimeout(() => MG.i18n.setLang(MG.i18n.DEFAULT), LANG_IDLE_MS);
  }
  function onLangChange() {
    buildKeys();
    tiles.forEach((t) => { t.json = ''; });   // dlaždice + hlášky překreslit v novém jazyce
    render();
    armLangIdle();
  }

  async function submit() {
    const code = S.entry.trim();
    if (!code || S.busy) return;
    S.busy = true;
    S.kb.setEnabled(false);
    clearTimeout(S.pinTimer);
    showStatus('working', MG.i18n.t('verifying'), '', false);
    const res = await post('/api/pin', { code });
    S.entry = '';
    paintEntry();
    S.busy = false;
    S.kb.setEnabled(true);
    // Server posílá hlášky česky — v jiném jazyce se skládají lokálně z kódu chyby / druhu kódu.
    const cz = MG.i18n.lang === MG.i18n.DEFAULT;
    if (!res.ok) {
      showStatus('error', MG.i18n.errorTitle(res.error), (cz && res.message) || MG.i18n.errorSubtitle(res.error, res.locked_until), true);
      return;
    }
    if (res.kind === 'service') { hideStatus(); MG.Panel.show(res.service_token); return; }
    if (res.kind === 'diagnostics') { hideStatus(); MG.Diag.open({ started: true }); return; }
    const z = res.zone != null ? (S.state && (S.state.zones || []).find((x) => x.zone === res.zone)) : null;
    const name = z ? MG.i18n.zoneName(z) : (res.kind === 'accessories' ? MG.i18n.t('acc') : MG.i18n.t('opened'));
    showStatus('success', MG.i18n.t('opened'), (cz && res.message) || MG.i18n.successSubtitle(res.kind, name), true);
  }

  /* ── Overlay stavů ────────────────────────────────────────────────── */
  function showStatus(kind, title, subtitle, dismissable) {
    clearTimeout(S.hideTimer);
    const working = kind === 'working';
    $('status-spinner').hidden = !working;
    const icon = $('status-icon');
    icon.hidden = working;
    icon.className = 'status-icon ' + kind;
    icon.textContent = kind === 'success' ? '🔓' : kind === 'error' ? '!' : '';
    $('status-title').textContent = title || '';
    $('status-sub').textContent = subtitle || '';
    $('status-dismiss').hidden = !dismissable;
    $('status').hidden = false;
    if (dismissable) S.hideTimer = setTimeout(hideStatus, AUTO_HIDE_MS);
  }
  function hideStatus() { clearTimeout(S.hideTimer); $('status').hidden = true; }

  /* ── Init ─────────────────────────────────────────────────────────── */
  function init() {
    const q = new URLSearchParams(location.search).get('lang');
    MG.i18n.setLang(q || MG.i18n.DEFAULT, true);
    MG.i18n.renderBar($('lang-bar'));
    MG.i18n.onChange(onLangChange);
    document.addEventListener('pointerdown', armLangIdle, { passive: true });
    MG.Panel.init({ post, showStatus, getState: () => S.state });
    MG.Setup.init({ post, onPaired: () => { showStatus('success', 'Spárováno', 'Zařízení je připojeno k pobočce.', true); pollFallback(); } });
    MG.Diag.init({ post, getState: () => S.state });
    buildKeys();
    paintEntry();
    $('status').addEventListener('click', () => { if (!$('status-dismiss').hidden) hideStatus(); });
    // Fyzická klávesnice: diagnostika (zadání kódu) > setup > hlavní zadávání kódu.
    // Otevřený report diagnostiky (bez zadávání) klávesy POLYKÁ — Enter nesmí odeslat skrytý PIN.
    const SWALLOW = { onChar() {}, onBackspace() {}, onEnter() {}, onClear() {} };
    const target = () => (MG.Diag.wantsKeys() ? MG.Diag.keys : MG.Diag.isVisible() ? SWALLOW
      : MG.Setup.isVisible() ? MG.Setup.keys : null);
    MG.Keyboard.bindPhysical({
      isActive: () => !MG.Panel.isOpen() || MG.Setup.isVisible() || MG.Diag.isVisible(),
      onChar: (c) => { const t = target(); if (t) t.onChar(c); else if (/[0-9a-z]/.test(c)) onChar(c); },
      onBackspace: () => { const t = target(); if (t) t.onBackspace(); else onBackspace(); },
      onEnter: () => { const t = target(); if (t) t.onEnter(); else submit(); },
      onClear: () => { const t = target(); if (t) t.onClear(); else onClear(); },
      onEscape: () => {
        if (MG.Diag.isVisible()) MG.Diag.keys.onEscape();
        else if (MG.Setup.isVisible()) MG.Setup.keys.onEscape();
        else if (!$('status').hidden && !S.busy) hideStatus();
        else onClear();
      },
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    connectWs();
    pollFallback();
    setInterval(pollFallback, POLL_MS);
    setInterval(() => { updateBanner(); tickTimer(); }, 1000);
  }

  MG.app = { post, showStatus, hideStatus, getState: () => S.state };
  // Jen pro náhledy/screenshoty (harness): přepnutí klávesnice, jazyka, podstrčení stavu. Appka to nepoužívá.
  MG.__debug = { toggleKeyboard: toggleMode, setLang: (l) => MG.i18n.setLang(l), applyState, showStatus, hideStatus };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
