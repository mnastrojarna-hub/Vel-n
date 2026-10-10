/* MotoGo24 kiosk — předávací protokol na displeji (overlay #handover, kontrakt §4/§5 návrhu 2026-09-25).
   Zdroj pravdy = snapshot `st.handover.active` (jednotka: HandoverManager) — UI ho jen zobrazuje a posílá
   /api/protocol/submit | dismiss | touch. Odpočet výhradně z `active.expires_at`. Výsledek, který snapshot nenese
   (kóje otevřená po vzdáleném podpisu s then_open, timeout vlastního submitu), se odvozuje ze stavu zón (S.wait).
   Vanilla JS, bez závislostí; závisí na MG.i18n (+ i18n-handover.js), MG.Keyboard (mode 'pin') a MG.Signature. */
'use strict';
window.MG = window.MG || {};

MG.Handover = (function () {
  const $ = (id) => document.getElementById(id);
  const TOUCH_MS = 5000, SUBMIT_TIMEOUT_MS = 60000, CODE_LEN = 6, DONE_GUARD_MS = 15000, WAIT_MS = 4000;
  const GEAR_ICON = { helmet: '🪖', jacket: '🧥', pants: '👖', boots: '🥾', gloves: '🧤' };
  /** Výbava motorky (zadání majitele 2026-09-28): v KAŽDÉM protokolu z displeje; leží v motorce (kufr / tankvak).
      Od 2026-10-10 i doklady: zelená karta a technický průkaz.
      Od 2026-10-02 jen informativně (bez zaškrtávání) v kroku 2. Klíče = i18n `me.*` a edge `form.moto_equipment[]`. */
  const MOTO_GEAR = [
    { key: 'luggage', ico: '🧳', note: true },           // 2026-10-10: každá motorka má kufr (cestovní) nebo tankvak
    { key: 'phone_holder', ico: '📱' },               // 2026-10-10 (zadání majitele): držák k němuž je klíč níže
    { key: 'phone_holder_key', ico: '🔑' },
    { key: 'disc_lock', ico: '🔒' },
    { key: 'accident_form', ico: '📝' },
    { key: 'first_aid_kit', ico: '🩹' },
    { key: 'reflective_vest', ico: '🦺', qty: 2 },
    { key: 'green_card', ico: '📗' },                 // 2026-10-10 (zadání majitele): doklady k motorce, jen informativně
    { key: 'registration_certificate', ico: '📄' },
  ];
  const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' };
  let deps = null;    // { post, showStatus, getState }
  const S = { item: null, key: '', code: '', picks: {}, taken: {}, bk: {}, allSeen: false, gearSig: '', step: 2, saving: false, lastTouch: 0, msg: null, sig: null, kb: null,
    timer: null, doneKey: '', ownDone: { id: '', at: 0 }, wait: null };
  // S.picks[gid] = zvolená velikost, S.bk[gid] = položka je v rezervaci (objednaná) / navíc,
  // S.taken[gid] (2026-10-05): false = zákazník si položku NEBERE (chip ✕) → edge ji z rezervace
  // odebere (bookings.<field> = NULL). Klíč = identita položky (gid), NE index: jednotka `data.gear` během otevřeného protokolu
  // obnovuje ze sync (reconcile) a seznam se může změnit (Velín přidá/odebere položku) — S.gearSig to v sync() pozná.
  // S.msg = {key} (i18n) | {locked: locked_until} | {pickup: release_at} (výdej až od 12:00, §31) ; S.wait = {id, thenOpen, at} — položka zmizela, výsledek řekne stav zón
  // S.step: 1 = velikosti zapůjčené výbavy, 2 = výbava motorky (info) + podpis + kód (2026-10-02; bez zapůjčené výbavy rovnou 2)

  function setText(el, text) { if (el && el.textContent !== text) el.textContent = text; }
  const itemKey = (a) => a.booking_id + '|' + (a.shown_at || '');
  const GEAR_KEYS = ['helmet', 'jacket', 'pants', 'boots', 'gloves'];
  const gearOf = (a) => (Array.isArray(a && a.data && a.data.gear) ? a.data.gear : []);
  const gid = (g) => g.field || ((g.who || 'rider') + ':' + g.key);
  /** Výbava NAVÍC (2026-10-05, zadání majitele: „co si vezme navíc, musí být v protokolu“): zákazník s přístupem do šatny
      (protokol po zavření šatny = `kind`/`kind_origin` accessories, nárok na šatnu `needs_locker` — i když šatnu přeskočil
      kódem motorky —, nebo rezervace s objednanou výbavou) vidí VŠECHNY druhy výbavy —
      objednané předvybrané, ostatní nepřevzaté; vzal-li si něco navíc, vybere velikost a edge to do rezervace doplní
      (`form.gear_add`). Bez přístupu do šatny a bez objednané výbavy jen „vlastní výbava“. Dětská motorka = jen řidič. */
  /** Protokol vznikl zavřením šatny — i když ho zákazník „Zpět“/nečinností skryl a vrátil se kódem motorky (`kind_origin`). */
  const lockerUsed = (a) => !!(a && (a.kind === 'accessories' || a.kind_origin === 'accessories'));
  const showAll = (a) => gearOf(a).length > 0 || lockerUsed(a) || !!(a && a.needs_locker === true);
  function rowsOf(a) {
    if (!showAll(a) && !S.allSeen) return [];   // jednou nabídnutá výbava navíc nezmizí (Velín mezitím změnil nárok)
    const gear = gearOf(a), out = [];
    (a.is_child ? ['rider'] : ['rider', 'passenger']).forEach((who) => GEAR_KEYS.forEach((key) => {
      const b = gear.find((g) => (g.who || 'rider') === who && g.key === key);
      out.push(b ? Object.assign({}, b, { who, booked: true })
        : { key, who, field: (who === 'passenger' ? 'passenger_' : '') + key + '_size', size: '', booked: false });
    }));
    gear.forEach((g) => { if (!out.some((r) => r.booked && gid(r) === gid(g))) out.push(Object.assign({}, g, { booked: true })); });
    return out;
  }
  /** Objednaná položka: převzato, dokud nedá ✕; položka navíc: převzato, až když vybere velikost. */
  const isTaken = (r) => (r.booked ? S.taken[gid(r)] !== false : S.taken[gid(r)] === true);
  const gearSig = (a) => JSON.stringify([showAll(a), !!(a && a.is_child), gearOf(a).map((g) => [gid(g), g.size != null ? String(g.size) : ''])]);
  /** Stav voleb výbavy: objednaná položka = velikost z rezervace + převzato, navíc = bez velikosti, nepřevzato;
      `keep` = volby už známých položek zachovat (sync). */
  function initGear(a, keep) {
    if (!keep) { S.picks = {}; S.taken = {}; S.bk = {}; S.allSeen = false; }
    if (showAll(a)) S.allSeen = true;
    rowsOf(a).forEach((r) => {
      const id = gid(r);
      // volbu zachovat jen u položky, která zůstala stejného druhu (objednaná ↔ navíc) — Velín ji mezitím mohl
      // do rezervace přidat: pak platí velikost z rezervace a „převzato“ (nikdy ne „neberu“ = odebrání)
      if (keep && Object.prototype.hasOwnProperty.call(S.picks, id) && S.bk[id] === !!r.booked) return;
      S.picks[id] = r.size != null && r.size !== '' ? String(r.size) : '';
      S.taken[id] = !!r.booked;
      S.bk[id] = !!r.booked;
    });
    S.gearSig = gearSig(a);
  }
  const cz = () => MG.i18n.lang === MG.i18n.DEFAULT;

  /** Datum z ISO (date i timestamp) v jazyce displeje; nerozpoznané → původní text. */
  function fmtDate(v) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v || ''));
    if (!m) return v ? String(v) : '';
    try { return new Intl.DateTimeFormat(LOCALE[MG.i18n.lang] || 'cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }).format(new Date(+m[1], +m[2] - 1, +m[3])); }
    catch (e) { return m[3] + '. ' + m[2] + '. ' + m[1]; }
  }

  /* ── Dotyk → prodloužení relace (throttle) ────────────────────────────── */
  function touch() {
    const now = Date.now();
    if (!S.item || now - S.lastTouch < TOUCH_MS) return;
    S.lastTouch = now;
    deps.post('/api/protocol/touch', { booking_id: S.item.booking_id }, 5000);
  }

  /* ── Vykreslení ───────────────────────────────────────────────────────── */
  function renderMeta(a) {
    const d = a.data || {};
    setText($('ho-customer'), d.customer_name || '—');
    setText($('ho-moto'), [d.moto_model, d.moto_spz].filter(Boolean).join(' · ') || '—');
    const from = fmtDate(d.start_date), to = fmtDate(d.end_date);
    setText($('ho-period'), from && to && from !== to ? from + ' – ' + to : (from || to || '—'));
  }

  function chip(label, on, onTap) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'ho-chip' + (on ? ' on' : '');
    b.textContent = label;
    b.addEventListener('click', (e) => { e.preventDefault(); onTap(); });
    return b;
  }

  /** Řádky výbavy: skupina Řidič / Spolujezdec, ikona + název (i18n g.*), chipy velikostí z číselníku (+ aktuální) a na konci
      chip „✕ Neberu“ (přepínač: objednaná položka → řádek `off`, žádný chip velikosti `on`); klepnutí na velikost bere položku.
      Položka navíc (není v rezervaci) je ztlumená (`extra`), dokud zákazník nevybere velikost; ✕ ji pak zase vrátí. */
  function renderGear(a) {
    const box = $('ho-gear-list');
    box.textContent = '';
    const all = rowsOf(a);
    if (!all.length) {
      const p = document.createElement('div'); p.className = 'ho-nogear'; p.textContent = MG.i18n.t('ho.noGear'); box.appendChild(p);
      return;
    }
    ['rider', 'passenger'].forEach((who) => {
      const rows = all.filter((g) => (g.who || 'rider') === who);
      if (!rows.length) return;
      const h = document.createElement('div'); h.className = 'ho-group'; h.textContent = MG.i18n.t('ho.' + who); box.appendChild(h);
      rows.forEach((g) => {
        const id = gid(g), taken = isTaken(g);
        const row = document.createElement('div');
        row.className = 'ho-row' + (taken ? '' : g.booked ? ' off' : ' extra');
        row.innerHTML = '<span class="ho-row-ico"></span><span class="ho-row-name"></span><div class="ho-chips"></div>';
        row.querySelector('.ho-row-ico').textContent = GEAR_ICON[g.key] || '🎽';
        row.querySelector('.ho-row-name').textContent = MG.i18n.g('g', g.key) || g.key || '';
        const sizes = (a.sizes && Array.isArray(a.sizes[g.key]) ? a.sizes[g.key] : []).map(String);
        const cur = S.picks[id];
        if (cur && sizes.indexOf(cur) === -1) sizes.unshift(cur);
        const chips = row.querySelector('.ho-chips');
        if (!sizes.length) { const s = document.createElement('span'); s.className = 'ho-size-na'; s.textContent = '—'; chips.appendChild(s); }
        sizes.forEach((sz) => chips.appendChild(chip(sz, taken && sz === cur, () => {
          S.picks[id] = sz; S.taken[id] = true; touch(); renderGear(a);
          if (S.msg && S.msg.key === 'ho.pickTaken') setMsg(null);
        })));
        if (g.booked || taken) {      // položka navíc: ✕ jen pro vrácení volby (nevybraná = nepřevzato)
          const skip = chip('✕ ' + MG.i18n.t('ho.notTaking'), g.booked && !taken, () => { S.taken[id] = g.booked ? !taken : false; touch(); renderGear(a); });
          skip.classList.add('skip');
          chips.appendChild(skip);
        }
        box.appendChild(row);
      });
    });
  }

  /** Krok 2: „Výbava motorky“ — jen informace, co zákazník najde v motorce (kufr / tankvak), bez zaškrtávání. */
  function renderMotoGear() {
    const box = $('ho-moto-list');
    box.textContent = '';
    MOTO_GEAR.forEach((m) => {
      const row = document.createElement('div');
      row.className = 'ho-row ho-row-moto';
      row.innerHTML = '<span class="ho-row-ico"></span><span class="ho-row-name"></span>';
      row.querySelector('.ho-row-ico').textContent = m.ico;
      row.querySelector('.ho-row-name').textContent = (m.qty ? m.qty + '× ' : '') + (MG.i18n.g('me', m.key) || m.key);
      if (m.note) {        // vysvětlivka pod názvem (kufr × tankvak dle typu motorky)
        const n = document.createElement('small'); n.className = 'ho-row-note';
        n.textContent = MG.i18n.g('me', m.key + '_note') || '';
        row.querySelector('.ho-row-name').appendChild(n);
      }
      box.appendChild(row);
    });
  }
  /** Výbava motorky pro `form.moto_equipment[]` edge funkce — v motorce je vždy celá (informativní seznam). */
  function motoEquipment() {
    return MOTO_GEAR.map((m) => ({ key: m.key, qty: m.qty || 1, checked: true }));
  }
  const hasGear = (a) => rowsOf(a).length > 0;
  /** Přepnutí kroku: 1 = velikosti, 2 = výbava motorky + podpis (+ kód). Podpis zůstává, canvas se po zobrazení přepočítá. */
  function setStep(n) {
    S.step = n;
    const ho = $('handover'), two = hasGear(S.item);
    ho.classList.toggle('step-1', n === 1);
    ho.classList.toggle('step-2', n === 2);
    setText($('ho-step'), two ? MG.i18n.t('ho.step', { n, t: 2 }) : '');
    $('ho-own-gear').hidden = two;   // bez zapůjčené výbavy (rovnou krok 2): „vlastní výbava“ nad výbavou motorky
    if (n === 2 && S.sig) S.sig.resize();
    updateButtons();
  }
  function back() {
    if (S.saving || (S.item && S.item.saving)) return;
    if (S.step === 2 && hasGear(S.item)) {
      touch();
      if (S.msg && S.msg.key) setMsg(null);   // chyba podpisu/kódu z kroku 2 do kroku 1 nepatří (lockout / „až od 12:00“ platí dál)
      setStep(1);
    } else dismiss();
  }
  /** Rezervace BEZ objednané výbavy, která otevřela šatnu (zadání majitele 2026-10-05: „nesmí ho to pustit, aniž by vyškrtal
      nějaké velikosti“), musí vybrat aspoň jednu velikost — platí i po „Zpět“/nečinnosti a návratu kódem motorky
      (`kind_origin`). Kdo šatnu neotevřel (rovnou kód motorky), má výbavu navíc jen nabídnutou. */
  const needsPick = (a) => lockerUsed(a) && !gearOf(a).length && !rowsOf(a).some(isTaken);
  function next() {
    if (!S.item || S.step !== 1) return;
    touch();
    if (needsPick(S.item)) { setMsg('ho.pickTaken'); return; }
    if (S.msg && S.msg.key === 'ho.pickTaken') setMsg(null);
    setStep(2);
  }
  function onEnter() { if (S.step === 1) next(); else confirm(); }

  function paintCode() {
    const box = $('ho-code-box');
    // Číslice bez mezer, rozestup dělá CSS `letter-spacing` — „1 2 3 4 5 6“ se do pole nevešlo a kód se ořezával.
    if (!S.code) { box.textContent = '••••••'; box.classList.add('empty'); }
    else { box.textContent = S.code; box.classList.remove('empty'); }
  }
  /** Hláška v patičce: i18n klíč, nebo `{locked}` = PIN lockout jednotky (stejný text jako na hlavní obrazovce, minuty živě). */
  function paintMsg() {
    const m = S.msg, el = $('ho-msg');
    const pk = m && m.pickup !== undefined ? MG.i18n.pickup(m.pickup) : null;
    const text = !m ? '' : m.locked !== undefined
      ? MG.i18n.errorTitle('locked') + '\n' + MG.i18n.errorSubtitle('locked', m.locked)
      : pk ? pk.title + '\n' + pk.body : MG.i18n.t(m.key);
    setText(el, text);
    el.hidden = !text;
  }
  function setMsg(m) { S.msg = !m ? null : typeof m === 'string' ? { key: m } : m; paintMsg(); }
  /** Spinner „Ukládám…“: vlastní požadavek NEBO jednotka stále ukládá (`active.saving` — po timeoutu UI / jiná cesta). */
  function paintSaving() {
    const on = S.saving || !!(S.item && S.item.saving);
    $('ho-saving').hidden = !on;
    $('handover').classList.toggle('saving', on);
  }
  function updateButtons() {
    const a = S.item;
    const busy = S.saving || !!(a && a.saving);
    const noSig = !S.sig || S.sig.isEmpty();
    const noCode = !!(a && a.needs_code) && S.code.length !== CODE_LEN;
    $('ho-confirm').disabled = !a || busy || noSig || noCode || S.step !== 2;
    $('ho-confirm').hidden = S.step !== 2;
    $('ho-next').hidden = S.step !== 1;
    $('ho-back').disabled = busy;
    $('ho-sig-hint').hidden = !noSig;
    if (S.kb) S.kb.setEnabled(!busy);
  }
  function tickTimer() {
    const a = S.item;
    if (!a) return;
    const left = Math.ceil((Date.parse(a.expires_at || '') - Date.now()) / 1000);
    // 2026-09-29: protokol drží 10 min → nad minutu odpočet v minutách („Zavře se za 10 min“)
    const txt = !isFinite(left) || left < 0 ? '' : left > 60
      ? MG.i18n.t('ho.autoCloseMin', { m: Math.ceil(left / 60) }) : MG.i18n.t('ho.autoClose', { s: left });
    setText($('ho-timer'), txt);
    if (S.msg && (S.msg.locked !== undefined || S.msg.pickup !== undefined)) paintMsg();   // „za {m} min“ ubíhá
    if (isFinite(left) && left < -3) hide();   // jednotka overlay skryje sama (WS); pojistka při výpadku WS
  }
  function setSaving(on) { S.saving = on; paintSaving(); updateButtons(); }

  /* ── Otevření / skrytí ────────────────────────────────────────────────── */
  function open(a) {
    S.item = a; S.key = itemKey(a); S.code = ''; S.saving = false; S.lastTouch = Date.now();
    if (S.wait && S.wait.id === a.booking_id) S.wait = null;   // protokol téže rezervace znovu (podpis se neuložil) — čekaný výsledek je pasé
    initGear(a, false);
    setMsg(null);
    $('handover').hidden = false;
    $('handover').classList.toggle('no-code', !a.needs_code);
    $('ho-code-sec').hidden = !a.needs_code;
    renderMeta(a);
    renderGear(a);
    renderMotoGear();
    paintCode();
    if (!S.sig) S.sig = MG.Signature.create($('ho-sig'), { onStroke: () => { touch(); updateButtons(); } });
    S.sig.clear();
    if (!S.kb) S.kb = MG.Keyboard.build($('ho-keys'), { mode: 'pin', onChar: onCodeChar, onBackspace: onCodeBackspace, onEnter: confirm, onClear: onCodeClear });
    setStep(hasGear(a) ? 1 : 2);
    paintSaving();
    clearInterval(S.timer);
    S.timer = setInterval(tickTimer, 1000);
    tickTimer();
    updateButtons();
  }
  /** Stejná položka, nový snapshot: then_open mohl vypršet (needs_code), ukládání z jiné cesty, prodloužený odpočet;
      jednotka mohla obnovit `data.gear` ze sync (rezervace upravena ve Velíně) → doplnit nové položky a překreslit. */
  function sync(a) {
    const codeChanged = !!S.item.needs_code !== !!a.needs_code, gearChanged = gearSig(a) !== S.gearSig;
    const hadGear = hasGear(S.item);
    S.item = a;
    if (codeChanged) { $('handover').classList.toggle('no-code', !a.needs_code); $('ho-code-sec').hidden = !a.needs_code; S.sig.resize(); }
    if (gearChanged) {
      initGear(a, true); renderGear(a);
      // výbava se objevila (Velín ji doplnil) → zpět na kontrolu velikostí; jinak jen překreslit krok (banner „vlastní výbava“)
      if (hasGear(a) !== hadGear) setStep(hasGear(a) ? 1 : 2);
    }
    paintSaving();
    // po timeoutu vlastního submitu: položka je dál vidět a jednotka neukládá → požadavek k ní vůbec nedorazil
    if (S.wait && S.wait.id === a.booking_id && !S.saving && !a.saving) { S.wait = null; setMsg('ho.failed'); }
    tickTimer();
    updateButtons();
  }
  function hide() {
    if (!S.item) return;
    S.item = null; S.key = ''; S.code = ''; S.saving = false;
    clearInterval(S.timer); S.timer = null;
    $('handover').hidden = true;
    $('handover').classList.remove('saving');
    setMsg(null);
  }

  /** Toast DONE (stage 'done'): jednou na položku; po vlastním podpisu ho nahrazuje výsledek submitu. */
  function showDone(a) {
    const k = itemKey(a);
    if (k === S.doneKey) return;
    S.doneKey = k;
    if (a.booking_id === S.ownDone.id && Date.now() - S.ownDone.at < DONE_GUARD_MS) return;
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t('ho.done'), true);
  }

  /* ── Výsledek, který snapshot nenese (§1: vzdálený podpis s then_open = plnohodnotné otevření) ── */
  const openedZone = (st, id) => ((st && st.zones) || []).find((z) => z.booking_id === id && z.kind !== 'accessories'
    && (z.state === 'WAITING_FOR_OPEN' || z.state === 'DOOR_OPEN'));
  function announceOpened(z) {
    deps.showStatus('success', MG.i18n.successTitle('motorcycle', z),
      MG.i18n.t('ho.doneMoto') + '\n' + MG.i18n.successSubtitle('motorcycle', MG.i18n.zoneName(z), z), true);
  }
  /** Čekání na stav zón: kóje rezervace otevřená → „Otevřeno — Kóje N“; po WAIT_MS bez otevření → DONE
      (then_open: „kóji se nepodařilo otevřít — zadejte kód znovu“; jinak „teď zadejte kód motorky“). */
  function armWait(id, thenOpen) {
    S.wait = { id, thenOpen, at: Date.now() };
    setTimeout(() => resolveWait(deps.getState()), WAIT_MS + 300);
    resolveWait(deps.getState());
  }
  function resolveWait(st) {
    const w = S.wait;
    if (!w) return;
    const z = openedZone(st, w.id);
    if (!z && Date.now() - w.at < WAIT_MS) return;
    S.wait = null;
    if (z) { announceOpened(z); return; }
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t(w.thenOpen ? 'ho.doneNoOpen' : 'ho.done'), true);
  }
  /** Položka zmizela bez naší odpovědi: vlastní submit řeší confirm(); vypršelý odpočet = zákazník odešel (nic);
      jinak vzdálený podpis (appka/Velín) během overlaye s platným then_open → jednotka kóji otevřela → potvrdit ze zón. */
  function onGone(prev, ownSaving) {
    if (ownSaving || S.wait || prev.stage !== 'protocol' || !prev.then_open) return;
    if (!(Date.parse(prev.expires_at || '') - Date.now() > 1500)) return;
    armWait(prev.booking_id, true);
  }

  /** Volá app.js render() s každým snapshotem. */
  function onState(st) {
    const a = st && st.handover && st.handover.active;
    if (!a) { const prev = S.item, own = S.saving; hide(); if (prev) onGone(prev, own); }
    else if (a.stage === 'done') { hide(); showDone(a); }
    else if (itemKey(a) !== S.key) open(a);
    else sync(a);
    resolveWait(st);
  }

  /* ── Kód motorky (identita podepisujícího) ────────────────────────────── */
  function onCodeChar(ch) {
    if (S.saving || !S.item || S.step !== 2 || !S.item.needs_code || !/^[0-9]$/.test(ch) || S.code.length >= CODE_LEN) return;
    S.code += ch; paintCode(); touch(); updateButtons();
  }
  function onCodeBackspace() { if (S.saving || S.step !== 2 || !S.code) return; S.code = S.code.slice(0, -1); paintCode(); touch(); updateButtons(); }
  function onCodeClear() { if (S.saving || S.step !== 2) return; S.code = ''; paintCode(); touch(); updateButtons(); }

  /* ── Potvrdit a podepsat ──────────────────────────────────────────────── */
  async function confirm() {
    const a = S.item;
    if (!a || S.step !== 2 || $('ho-confirm').disabled) return;
    touch();
    if (needsPick(a)) { setStep(1); setMsg('ho.pickTaken'); return; }   // pojistka (krok 2 dosažen dřív, než se šatna projevila)
    const signature = S.sig.toPng();
    if (!signature) { setMsg('ho.sigTooLarge'); return; }
    const form = {
      mileage: a.data && a.data.mileage != null ? String(a.data.mileage) : '',
      // nepřevzatá položka (checked:false) nese PŮVODNÍ velikost z rezervace — edge ji NULLuje, velikost nepropisuje;
      // objednaná položka bez záznamu v S.taken (nikdy nezobrazená) = převzato (stejný výklad jako renderGear);
      // položka NAVÍC jde jen převzatá (`added: true`) — edge ji s `gear_add` doplní do rezervace (2026-10-05)
      accessories: rowsOf(a).filter((r) => r.booked || isTaken(r)).map((r) => {
        const id = gid(r), taken = isTaken(r);
        return Object.assign({ key: r.key, who: r.who || 'rider', field: r.field,
          size: taken ? (S.picks[id] || '') : (r.size != null ? String(r.size) : ''), checked: taken }, r.booked ? {} : { added: true });
      }),
      gear_add: true,
      moto_equipment: motoEquipment(),
    };
    const body = { booking_id: a.booking_id, form, signature };
    if (a.needs_code) body.code = S.code;
    setMsg(null);
    setSaving(true);
    const res = await deps.post('/api/protocol/submit', body, SUBMIT_TIMEOUT_MS);
    const same = !!(S.item && S.item.booking_id === a.booking_id);
    if (same) setSaving(false);
    if (!res.ok) {
      const e = res.error;
      if (e === 'not_pending') { hide(); return; }   // položka mezitím zmizela (podpis v appce) — displej řídí snapshot
      if (e === 'network' && !res.status) {
        // timeout / spojení: jednotka může dál ukládat a otevírat (resolve + edge až ~52 s) → výsledek řekne snapshot
        if (same && !S.item.saving) { setMsg('ho.failed'); return; }   // jednotka neukládá → požadavek nedorazil
        armWait(a.booking_id, !a.needs_code);
        return;
      }
      if (e === 'storage_failed') {   // podpis se neuložil ani neodeslal; jednotka položku zrušila → pokyn do #status (overlay zmizí)
        hide(); deps.showStatus('error', MG.i18n.errorTitle('protocol_failed'), MG.i18n.t('ho.retryCode'), true); return;
      }
      if (!same) return;
      if (e === 'locked') { S.code = ''; paintCode(); setMsg({ locked: res.locked_until || null }); updateButtons(); return; }
      // kód téže rezervace před 12:00 (sleva za pozdní vyzvednutí, §31) — kóje se ještě nevydá; podpis se neuložil
      if (e === 'pickup_too_early') { setMsg({ pickup: res.release_at || null }); return; }
      if (e === 'body_too_large' || res.status === 413) { setMsg('ho.sigTooLarge'); return; }
      setMsg(e === 'code_mismatch' ? 'ho.codeMismatch' : e === 'signature_too_large' ? 'ho.sigTooLarge'
        : e === 'in_progress' ? 'ho.inProgress' : 'ho.failed');
      if (e === 'code_mismatch') { S.code = ''; paintCode(); updateButtons(); }
      return;
    }
    S.ownDone = { id: a.booking_id, at: Date.now() };
    hide();
    const st = deps.getState() || {};
    if (res.opened) {
      const z = (st.zones || []).find((x) => x.zone === res.opened.zone);
      const name = z ? MG.i18n.zoneName(z) : MG.i18n.t('box', { n: res.opened.zone });
      deps.showStatus('success', MG.i18n.successTitle('motorcycle', z || { zone: res.opened.zone }),
        MG.i18n.t('ho.doneMoto') + '\n' + MG.i18n.successSubtitle('motorcycle', name, z || { zone: res.opened.zone }), true);
      return;
    }
    const noOpen = ['busy', 'door_open', 'lock_failed', 'zone_not_configured', 'io_offline', 'fault'].indexOf(res.error) !== -1;
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t(noOpen ? 'ho.doneNoOpen' : 'ho.done'), true);
  }

  async function dismiss() {
    const a = S.item;
    if (!a || S.saving || a.saving) return;
    hide();
    deps.post('/api/protocol/dismiss', { booking_id: a.booking_id }, 5000);
  }

  /** Změna jazyka: statické popisky řeší MG.i18n.applyStatic (data-i18n), tady dynamické části;
      delší/kratší texty mění výšku rámečku podpisu → přepočet bitmapy canvasu. */
  function rerender() {
    const a = S.item;
    if (!a) return;
    renderMeta(a); renderGear(a); renderMotoGear(); setStep(S.step); paintMsg(); tickTimer();
    if (S.sig) S.sig.resize();
  }

  function init(d) {
    deps = d;
    $('ho-confirm').addEventListener('click', (e) => { e.preventDefault(); confirm(); });
    $('ho-back').addEventListener('click', (e) => { e.preventDefault(); back(); });
    $('ho-next').addEventListener('click', (e) => { e.preventDefault(); next(); });
    $('ho-sig-clear').addEventListener('click', (e) => { e.preventDefault(); if (S.sig && !S.saving) S.sig.clear(); touch(); });
    $('handover').addEventListener('pointerdown', touch, { passive: true, capture: true });
  }

  /** Fyzická klávesnice, dokud je overlay vidět (app.js): číslice → kód motorky (krok 2), Enter → další krok / potvrdit, Esc → zpět. */
  const keys = { onChar: onCodeChar, onBackspace: onCodeBackspace, onEnter, onClear: onCodeClear, onEscape: back };

  return { init, onState, rerender, keys, isVisible: () => !!S.item, dismiss };
})();
