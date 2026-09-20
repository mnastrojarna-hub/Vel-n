/* MotoGo24 kiosk — servisní terminál na displeji (CONTRACT §27, POST /api/service/shell).
   Otevírá se z diagnostiky (po zadání diagnostického kódu → `shell_token`) nebo ze servisního panelu
   (`service_token`). Připravená tlačítka jsou vždy. Volné psaní má rovnou servisní heslo — i když je
   pobočka OFFLINE, kvůli čemuž terminál vznikl; s pouhým diagnostickým kódem ho musí povolit Velín
   (`shell_unlock`) a do té doby je pole s klávesnicí skryté a jednotka volný text stejně odmítne. */
'use strict';
window.MG = window.MG || {};

MG.Shell = (function () {
  const $ = (id) => document.getElementById(id);
  let deps = null;                 // { post }
  let visible = false, auth = null, busy = false, kb = null;
  let cmd = '', freeS = 0, menu = [], tick = null;
  let service = false;        // přihlášeno servisním heslem → volné psaní i offline (§27)

  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = String(text); return e; };

  function msg(text, bad) {
    const m = $('shell-msg');
    m.textContent = text || '';
    m.style.color = bad ? '#dc2626' : '';
  }
  function out(text) { $('shell-out').textContent = text == null ? '' : String(text); }

  /** „volné psaní: 28 min" / „volné psaní zamčené" — odpočet běží i bez dalšího dotazu na jednotku. */
  function renderState() {
    const s = $('shell-state');
    if (service) {
      s.textContent = 'volné psaní: servisní heslo';
      s.className = 'diag-state ok';
    } else if (freeS > 0) {
      s.textContent = 'volné psaní: zbývá ' + Math.ceil(freeS / 60) + ' min';
      s.className = 'diag-state ok';
    } else {
      s.textContent = 'volné psaní zamčené (servisní heslo, nebo povolí Velín)';
      s.className = 'diag-state';
    }
    $('shell-input').hidden = !service && freeS <= 0;
  }

  function renderMenu() {
    const box = $('shell-menu');
    box.textContent = '';
    const groups = [];
    menu.forEach((p) => {
      let g = groups.find((x) => x.name === p.group);
      if (!g) { g = { name: p.group, items: [] }; groups.push(g); }
      g.items.push(p);
    });
    groups.forEach((g) => {
      const wrap = el('div', 'shell-group');
      wrap.appendChild(el('div', 'shell-group-name', g.name));
      const rowEl = el('div', 'shell-btns');
      g.items.forEach((p) => {
        const b = el('button', 'btn ' + (p.danger ? 'btn-amber' : 'btn-ghost'), p.label);
        b.type = 'button';
        b.addEventListener('click', () => runPreset(p));
        rowEl.appendChild(b);
      });
      wrap.appendChild(rowEl);
      box.appendChild(wrap);
    });
  }

  async function call(body) {
    if (busy) return null;
    busy = true;
    msg('Spouštím…');
    const res = await deps.post('/api/service/shell', Object.assign({}, auth, body || {}), 40000);
    busy = false;
    if (res && typeof res.service === 'boolean') service = res.service;
    if (res && typeof res.free_s === 'number') freeS = res.free_s;
    if (res) renderState();
    return res;
  }

  const ERRORS = {
    locked: 'Volné psaní vyžaduje servisní heslo — zadejte ho místo diagnostického kódu, nebo ho povolte ve Velíně (Samoobsluha → Terminál na displeji).',
    invalid_arg: 'Neplatná hodnota — povolená jsou písmena, číslice a . : - _',
    unknown_preset: 'Neznámý příkaz.',
    empty: 'Napište příkaz.',
    forbidden: 'Platnost servisního přístupu vypršela — zadejte kód znovu.',
  };

  function show(res, label) {
    if (!res) { msg('Jednotka neodpovídá.', true); return; }
    if (res.error && !res.output) {
      msg(ERRORS[res.error] || ('Chyba: ' + res.error), true);
      return;
    }
    msg((label || '') + (res.rc === 0 ? ' — hotovo' : ' — návratový kód ' + res.rc), res.rc !== 0);
    out(res.command + '\n\n' + (res.output || '(bez výstupu)'));
    $('shell-out').scrollTop = 0;
  }

  async function runPreset(p) {
    let arg = null;
    if (p.arg) {
      arg = window.prompt ? window.prompt(p.arg) : null;      // dotykový displej: hodnotu lze psát i klávesnicí níž
      if (arg == null || !String(arg).trim()) { msg('Zrušeno.'); return; }
    }
    show(await call({ preset: p.id, arg: arg ? String(arg).trim() : undefined }), p.label);
  }

  async function submit() {
    const text = cmd.trim();
    if (!text) { msg('Napište příkaz.', true); return; }
    const res = await call({ command: text });
    show(res, text);
    if (res && !res.error) { cmd = ''; renderCmd(); }
  }

  function renderCmd() { $('shell-cmd').textContent = cmd; }
  function onChar(ch) { if (cmd.length < 200) { cmd += ch; renderCmd(); } }
  function onBackspace() { cmd = cmd.slice(0, -1); renderCmd(); }
  function onClear() { cmd = ''; renderCmd(); }

  /** opts: { token? (service_token ze servisního panelu), shellToken? (z diagnostického kódu) } */
  async function open(opts) {
    opts = opts || {};
    // Servisní token (servisní heslo) má přednost — nese s sebou právo na volné psaní i offline.
    auth = opts.token ? { service_token: opts.token } : { shell_token: opts.shellToken || '' };
    service = false;
    visible = true;
    $('shell').hidden = false;
    cmd = ''; renderCmd(); out(''); msg('');
    const res = await call({});
    if (res && Array.isArray(res.menu)) { menu = res.menu; renderMenu(); }
    else if (res && res.error) msg(ERRORS[res.error] || ('Chyba: ' + res.error), true);
    else msg('');
    if (tick) clearInterval(tick);
    tick = setInterval(() => { if (!service && freeS > 0) { freeS = Math.max(0, freeS - 10); renderState(); } }, 10000);
  }

  function close() {
    visible = false;
    $('shell').hidden = true;
    if (tick) { clearInterval(tick); tick = null; }
  }

  function init(d) {
    deps = d;
    kb = MG.Keyboard.build($('shell-keys'), { mode: 'shell', onChar, onBackspace, onEnter: submit, onClear, enterLabel: 'SPUSTIT' });
    $('shell-close').addEventListener('click', close);
    $('shell-close2').addEventListener('click', close);
    $('shell-clear').addEventListener('click', () => out(''));
  }

  return { init, open, close, isVisible: () => visible, wantsKeys: () => visible && (service || freeS > 0),
    keys: { onChar, onBackspace, onEnter: submit, onClear, onEscape: close } };
})();
