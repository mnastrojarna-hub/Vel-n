/* MotoGo24 kiosk — servisní panel (jen po servisním hesle) a setup/párování.
   Závisí na MG.Keyboard (keyboard.js) a MG.i18n + deps předaných z app.js. */
'use strict';
window.MG = window.MG || {};

/* ── Servisní panel ─────────────────────────────────────────────────────── */
MG.Panel = (function () {
  const $ = (id) => document.getElementById(id);
  let deps = null;            // { post, showStatus, getState, onClosed }
  let token = null;           // service_token (platí ~10 min)
  let open = false;
  let restartArmed = 0;       // čas prvního stisku Restart (dvoustupňové potvrzení)
  const cardCache = new Map(); // zone → { el, json }
  let devJson = '';

  function setText(el, text) { if (el && el.textContent !== text) el.textContent = text; }

  function msg(text, kind) {
    const el = $('service-msg');
    el.textContent = text || '';
    el.className = 'service-msg' + (kind ? ' ' + kind : '');
  }

  async function call(path, body, okText) {
    const res = await deps.post(path, Object.assign({ service_token: token }, body));
    if (res && res.status === 403) {
      close();
      deps.showStatus('error', 'Servisní relace vypršela', 'Zadejte prosím servisní heslo znovu.', true);
      return null;
    }
    if (!res || !res.ok) {
      const err = res && (res.message || MG.i18n.errorSubtitle(res.error) || res.error);
      msg(err || 'Akce se nezdařila.', 'err');
      return res;
    }
    msg(okText || 'Hotovo.', 'ok');
    return res;
  }

  function zoneCard(z) {
    const el = document.createElement('div');
    el.className = 'zcard';
    el.innerHTML =
      '<div class="zcard-head"><span class="zcard-num"></span><span class="zcard-name"></span></div>' +
      '<div class="zcard-info"><span>Stav: <b class="i-state"></b></span><span>Dveře: <b class="i-door"></b></span>' +
      '<span>Signál: <b class="i-sig"></b></span><span class="i-fault"></span></div>' +
      '<div class="zcard-btns"><button type="button" class="btn btn-primary b-open">Otevřít</button>' +
      '<button type="button" class="btn b-light">Světlo</button><button type="button" class="btn b-music">Hudba</button></div>';
    el.querySelector('.b-open').addEventListener('click', () => {
      msg('Otevírám ' + MG.i18n.zoneName(z) + '…');
      call('/api/service/open', { zone: z.zone, door_id: z.door_id || null }, 'Otevřeno: ' + MG.i18n.zoneName(z));
    });
    el.querySelector('.b-light').addEventListener('click', () => {
      const cur = latest(z.zone);
      const on = !(cur && cur.light);
      call('/api/service/light', { zone: z.zone, on }, 'Světlo ' + (on ? 'zapnuto' : 'vypnuto') + ': ' + MG.i18n.zoneName(z));
    });
    el.querySelector('.b-music').addEventListener('click', () => {
      const st = deps.getState() || {};
      const playing = st.audio && st.audio.playing_zone === z.zone;
      call('/api/service/music', { zone: z.zone, on: !playing }, (playing ? 'Hudba vypnuta' : 'Hudba hraje') + ': ' + MG.i18n.zoneName(z));
    });
    return el;
  }

  function latest(zone) {
    const st = deps.getState() || {};
    return (st.zones || []).find((z) => z.zone === zone) || null;
  }

  function updateCard(el, z, playingZone) {
    setText(el.querySelector('.zcard-num'), String(z.zone));
    setText(el.querySelector('.zcard-name'), MG.i18n.zoneName(z));
    setText(el.querySelector('.i-state'), MG.i18n.zoneState(z.state));
    setText(el.querySelector('.i-door'), MG.i18n.door(z.door_closed));
    setText(el.querySelector('.i-sig'), MG.i18n.signal(z.signal));
    setText(el.querySelector('.i-fault'), z.fault ? '⚠ ' + MG.i18n.fault(z.fault) : '');
    el.classList.toggle('fault', !!z.fault || z.state === 'FAULT');
    el.classList.toggle('open', z.state === 'DOOR_OPEN' || z.state === 'WAITING_FOR_OPEN');
    el.querySelector('.b-light').classList.toggle('on', !!z.light);
    el.querySelector('.b-music').classList.toggle('on', playingZone === z.zone || !!z.music);
    el.querySelector('.b-open').disabled = !!z.fault && z.fault === 'io_offline';
  }

  /** Překreslí panel podle snapshotu — jen změněné části (žádný flicker). */
  function render(st) {
    if (!open || !st) return;
    setText($('service-title'), 'Servisní režim — ' + (st.branch_name || 'pobočka'));
    const grid = $('service-zones');
    const playing = st.audio ? st.audio.playing_zone : null;
    const zones = st.zones || [];
    const seen = new Set();
    zones.forEach((z) => {
      seen.add(z.zone);
      const j = JSON.stringify([z, playing === z.zone]);
      let c = cardCache.get(z.zone);
      if (!c) { c = { el: zoneCard(z), json: '' }; cardCache.set(z.zone, c); grid.appendChild(c.el); }
      if (c.json !== j) { c.json = j; updateCard(c.el, z, playing); }
    });
    cardCache.forEach((c, zone) => { if (!seen.has(zone)) { c.el.remove(); cardCache.delete(zone); } });
    if (!zones.length) { if (!cardCache.size) grid.textContent = 'Pro tuto pobočku nejsou nastavené žádné zóny.'; }
    else if (grid.firstChild && grid.firstChild.nodeType === 3) grid.firstChild.remove();   // placeholder pryč, jakmile zóny dorazí

    const h = st.health || {};
    const lte = h.lte || {};
    const sys = h.sys || {};
    const dj = JSON.stringify([st.internet, st.branch_name, st.device_id, st.version, st.modules, lte, sys.cpu_temp, st.config_source, st.config_problems]);
    if (dj === devJson) return;
    devJson = dj;
    const online = st.internet === true;
    setText($('dev-online'), online ? '● Online' : '● Offline');
    $('dev-online').style.color = online ? '#74FB71' : '#fca5a5';
    setText($('dev-branch'), st.branch_name || '—');
    setText($('dev-id'), st.device_id || '—');
    setText($('dev-version'), st.version || '—');
    const mods = $('dev-modules');
    mods.textContent = '';
    Object.entries(st.modules || {}).forEach(([name, on]) => {
      const s = document.createElement('span');
      s.className = 'mod' + (on ? ' on' : '');
      s.textContent = name + ' ' + (on ? 'online' : 'offline');
      mods.appendChild(s);
    });
    if (!mods.textContent) mods.textContent = '—';
    const lteTxt = lte.state ? (lte.operator || lte.state) + (lte.rssi != null ? ' · RSSI ' + lte.rssi + ' dBm' : '') + (lte.rsrp != null ? ' · RSRP ' + lte.rsrp : '') : '—';
    setText($('dev-lte'), lteTxt);
    setText($('dev-temp'), sys.cpu_temp != null ? Number(sys.cpu_temp).toFixed(1) + ' °C' : '—');
    const probs = (st.config_problems || []).length;
    setText($('dev-config'), (st.config_source === 'remote' ? 'Velín' : 'lokální') + (probs ? ' · ' + probs + ' problémů' : ' · OK'));
  }

  function show(serviceToken) {
    token = serviceToken || null;
    open = true;
    restartArmed = 0;
    msg('');
    $('service').hidden = false;
    render(deps.getState());
  }

  function close() {
    if (!open) return;
    open = false;
    token = null;
    $('service').hidden = true;
    if (deps.onClosed) deps.onClosed();
  }

  function init(d) {
    deps = d;
    $('service-close').addEventListener('click', close);
    $('service-close2').addEventListener('click', close);
    $('service-all-off').addEventListener('click', () => call('/api/service/all_off', {}, 'Vše vypnuto.'));
    $('service-pair').addEventListener('click', () => MG.Setup.show({ cancelable: true, token }));
    $('service-diag').addEventListener('click', () => MG.Diag.open({ token }));
    $('service-restart').addEventListener('click', () => {
      const now = Date.now();
      if (now - restartArmed > 6000) { restartArmed = now; msg('Opravdu restartovat? Stiskněte znovu do 6 s.', 'err'); return; }
      restartArmed = 0;
      call('/api/service/restart', {}, 'Řídicí jednotka se restartuje…');
    });
  }

  return { init, show, close, render, isOpen: () => open };
})();

/* ── Setup / párování zařízení ──────────────────────────────────────────── */
MG.Setup = (function () {
  const $ = (id) => document.getElementById(id);
  let deps = null;          // { post, onPaired }
  let visible = false;
  let cancelable = false;
  let token = null;
  let active = 'id';
  const values = { id: '', token: '' };
  let kb = null;
  let busy = false;

  function field(name) { return name === 'id' ? $('setup-id') : $('setup-token'); }

  function paint() {
    ['id', 'token'].forEach((n) => {
      const el = field(n);
      el.textContent = values[n];
      el.classList.toggle('active', n === active);
    });
  }

  function setError(text) {
    const el = $('setup-error');
    el.hidden = !text;
    el.textContent = text || '';
  }

  function onChar(ch) { if (busy || values[active].length >= 64) return; values[active] += ch; paint(); }
  function onBackspace() { if (busy) return; values[active] = values[active].slice(0, -1); paint(); }
  function onClear() { if (busy) return; values[active] = ''; paint(); }
  function onEnter() { if (active === 'id') { active = 'token'; paint(); } else save(); }

  async function save() {
    if (busy) return;
    const id = values.id.trim(), tok = values.token.trim();
    if (!id || !tok) { setError('Vyplňte ID zařízení i token.'); return; }
    busy = true;
    setError('');
    $('setup-save').disabled = true;
    $('setup-save').textContent = 'Ověřuji…';
    // Párování = ověření přes Supabase + resync + přestavba HW (může trvat přes 20 s po LTE) → delší timeout.
    const res = await deps.post('/api/service/pair', { device_id: id, device_token: tok, service_token: token }, 90000);
    busy = false;
    $('setup-save').disabled = false;
    $('setup-save').textContent = 'Spárovat a spustit';
    if (res && res.ok) { hide(); if (deps.onPaired) deps.onPaired(); return; }
    const err = res ? res.error : 'network';
    setError(res && res.status === 403 ? 'Servisní relace vypršela — zadejte servisní heslo znovu.'
      : err === 'network' ? 'Chyba spojení. Zkontrolujte internet a zkuste znovu.'
      : err === 'unauthorized' ? 'Neplatné ID zařízení nebo token.'
      : err === 'missing_inputs' ? 'Vyplňte ID zařízení i token.'
      : (err || 'Spárování se nezdařilo.'));
  }

  function show(opts) {
    opts = opts || {};
    cancelable = !!opts.cancelable;
    token = opts.token || null;
    values.id = ''; values.token = '';
    active = 'id';
    setError('');
    $('setup-cancel').hidden = !cancelable;
    $('setup').hidden = false;
    visible = true;
    paint();
  }

  function hide() { visible = false; $('setup').hidden = true; }

  function init(d) {
    deps = d;
    kb = MG.Keyboard.build($('setup-keys'), { mode: 'text', onChar, onBackspace, onEnter, onClear, enterLabel: 'DALŠÍ / OK' });
    field('id').addEventListener('click', () => { active = 'id'; paint(); });
    field('token').addEventListener('click', () => { active = 'token'; paint(); });
    $('setup-save').addEventListener('click', save);
    $('setup-cancel').addEventListener('click', () => { if (cancelable) hide(); });
    $('setup-diag').addEventListener('click', () => MG.Diag.open({ askCode: true }));
    paint();
  }

  return { init, show, hide, isVisible: () => visible, isCancelable: () => cancelable,
    keys: { onChar, onBackspace, onEnter, onClear, onEscape: () => { if (cancelable) hide(); } } };
})();
