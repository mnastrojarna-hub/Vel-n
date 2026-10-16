/* ===== MotoGo24 app v2 · shared/nav.js — paste VERBATIM inside renderVals() (after rank-theme.js). Returns the `nav` object for nav.html.
   navVals({ S, set, active, lang, rk, unread, needs, say, width, scale })
     S/set   board state + setter (uses keys nav_i, nav_n, nav_up — no constructor entry needed)
     active  index of this board's tab: 0 Domů · 1 Motorky · 2 Rezervace · 3 Trasy · 4 Profil
     lang    'cs'|'en'|'de'|'es'|'fr'|'nl'|'pl'|'uk' (board prop "jazyk"); rk = rankTheme(level)
     unread  PROFIL badge text ('' = none; mockups draw '[n]'), needs = REZERVACE needs-action dot, say(msg) = board toast
             (labels, nav aria and the tab aria suffixes AX are localized for all 8 langs; demo toasts stay Czech = notes for the owner)
     width   phone width in dp (board = 390); scale = OS text scale (default 1; Flutter: textScaler.scale(11) / 11), capped at 1.15.
     Labels: Title case 11/800, NEVER ellipsis/wrap/FittedBox. No-overlap ladder (= TextPainter logic in v2_nav_bar.dart), first rung
     that keeps every label gap ≥ 6 px and both edge gaps ≥ 4 px wins: ① user scale, a short form (fr Balades, pl Wynajmy,
     uk Траси) only for a label in a failing spot → ② whole row clamped to scale 1.0 (11 px), short forms again only where needed
     → ③ whole row 10 px. Clamped rows (②③) keep the long-press large-label bubble; Semantics always the full word.
     Widths = Montserrat 800 @ 11 px (Playwright, research/nav.md); the 8 langs × 320–430 dp × scale 1.0/1.15 grid passes. */
function navVals(o) {
  const S = o.S || {}, set = o.set || function () {}, say = o.say || function () {};
  const LB = {
    cs: ['Domů', 'Motorky', 'Rezervace', 'Trasy', 'Profil'],
    en: ['Home', 'Bikes', 'Bookings', 'Routes', 'Profile'],
    de: ['Home', 'Bikes', 'Buchungen', 'Routen', 'Profil'],
    es: ['Inicio', 'Motos', 'Reservas', 'Rutas', 'Perfil'],
    fr: ['Accueil', 'Motos', 'Locations', 'Itinéraires', 'Profil'],
    nl: ['Home', 'Motoren', 'Boekingen', 'Routes', 'Profiel'],
    pl: ['Start', 'Motory', 'Rezerwacje', 'Trasy', 'Profil'],
    uk: ['Головна', 'Мото', 'Оренда', 'Маршрути', 'Профіль']
  };
  const W = {
    cs: [35.5, 48.8, 60.5, 31.1, 31.6], en: [34.8, 32.2, 55.5, 40.9, 38.7], de: [34.8, 32.2, 68.2, 42.5, 31.6], es: [32.2, 35.9, 52.8, 33.4, 31.5],
    fr: [43.4, 35.9, 56.9, 59.6, 31.6], nl: [34.8, 49.4, 64, 40.9, 38.7], pl: [28.7, 41.6, 67.8, 31.1, 31.6], uk: [48.7, 30.9, 46.5, 64.5, 51.3]
  };
  const SHORT = { fr: { 3: ['Balades', 46.6] }, pl: { 2: ['Wynajmy', 56.2] }, uk: { 3: ['Траси', 35.9] } };
  const ARIA = { cs: 'Hlavní navigace', en: 'Main navigation', de: 'Hauptnavigation', es: 'Navegación principal', fr: 'Navigation principale', nl: 'Hoofdnavigatie', pl: 'Nawigacja główna', uk: 'Головна навігація' };
  const AX = {                                     // tab aria suffixes: [PROFIL unread badge, REZERVACE needs-action dot]
    cs: ['nepřečtené zprávy', 'vyžaduje akci'], en: ['unread messages', 'action needed'], de: ['ungelesene Nachrichten', 'Aktion erforderlich'],
    es: ['mensajes sin leer', 'requiere acción'], fr: ['messages non lus', 'action requise'], nl: ['ongelezen berichten', 'actie vereist'],
    pl: ['nieprzeczytane wiadomości', 'wymaga działania'], uk: ['непрочитані повідомлення', 'потрібна дія']
  };
  const lang = LB[String(o.lang || 'cs').slice(0, 2)] ? String(o.lang || 'cs').slice(0, 2) : 'cs';
  const width = o.width || 390, col = width / 5, GAP = 6, EDGE = 4;
  const full = LB[lang], sh = SHORT[lang] || {};
  const gaps = (w) => {                            // [min label gap, min edge gap] — labels are centred in equal columns
    let g = 99;
    for (let i = 0; i < 4; i++) g = Math.min(g, col - (w[i] + w[i + 1]) / 2);
    return [g, Math.min(col - w[0], col - w[4]) / 2];
  };
  const fit = (px) => {                            // one rung: widths scale linearly with the font size
    const k = px / 11, lbl = full.slice(), w = W[lang].map((x) => x * k);
    for (let pass = 0; pass < 5; pass++) {
      const cand = [];                             // labels in a failing spot; wider one of a pair first
      for (let i = 0; i < 4; i++) if (col - (w[i] + w[i + 1]) / 2 < GAP) cand.push(...(w[i] >= w[i + 1] ? [i, i + 1] : [i + 1, i]));
      if ((col - w[0]) / 2 < EDGE) cand.push(0);
      if ((col - w[4]) / 2 < EDGE) cand.push(4);
      const j = cand.find((x) => sh[x] && lbl[x] !== sh[x][0]);
      if (j === undefined) break;
      lbl[j] = sh[j][0]; w[j] = sh[j][1] * k;
    }
    const g = gaps(w);
    return { lbl, w, px, gap: g[0], edge: g[1], ok: g[0] >= GAP && g[1] >= EDGE };
  };
  const sc = Math.min(1.15, o.scale > 0 ? +o.scale : 1), px0 = 11 * sc;
  const ladder = [px0, Math.min(px0, 11), Math.min(px0, 10)];
  let F = null, rung = 0;
  for (; rung < ladder.length; rung++) { F = fit(ladder[rung]); if (F.ok) break; }
  if (rung === ladder.length) rung--;              // < 320 dp: smallest rung (golden tests cover 320–430 dp, they must never reach this)
  const lbl = F.lbl, lpx = Math.round(F.px * 100) / 100;
  const lblSt = 'font-size:' + lpx + 'px;line-height:' + Math.round(lpx * 14 / 11) + 'px';
  const I = {
    home: 'M3 11l9-7 9 7M5 10v10h14V10M10 20v-6h4v6',
    moto: 'M2 16.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M15 16.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M5.5 16.5L9 10h5.5l4 6.5M14 10l-1.5-3.5H16',
    cal: 'M4 5h16v16H4zM4 10h16M8 3v4M16 3v4M9 15.5l2 2 4-4',
    route: 'M4 19a2 2 0 1 0 4 0a2 2 0 1 0-4 0M16 5a2 2 0 1 0 4 0a2 2 0 1 0-4 0M8 19h8.5a3.5 3.5 0 0 0 0-7h-9a3.5 3.5 0 0 1 0-7H16'
  };
  const icons = [I.home, I.moto, I.cal, I.route, ''];
  const base = Math.max(0, Math.min(4, o.active | 0));
  const cur = (S.nav_i === undefined || S.nav_i === null) ? base : S.nav_i;
  const n = S.nav_n || 0;
  const unread = o.unread === undefined || o.unread === null ? '' : String(o.unread);
  const tabs = full.map((name, i) => ({
    l: lbl[i], ls: lblSt, i: icons[i], isIcon: i !== 4, isProfile: i === 4,
    cls: 'nv-t' + (i === cur ? ' on' + (n ? (n % 2 ? ' pA' : ' pB') : '') : '') + (i === cur && S.nav_up ? (S.nav_up % 2 ? ' upA' : ' upB') : ''),
    cur: i === cur ? 'page' : 'false',
    aria: name + (i === 4 && unread ? ', ' + AX[lang][0] + ' ' + unread : '') + (i === 2 && o.needs ? ', ' + AX[lang][1] : ''),
    hasDot: i === 2 && !!o.needs, hasCount: i === 4 && !!unread, count: unread,
    a: () => {
      if (i === cur) { set({ nav_up: (S.nav_up || 0) + 1 }); say('Klepnutí na aktivní kartu = zpět nahoru'); return; }
      set({ nav_i: i, nav_n: n + 1, nav_up: 0 });
      say('Ukázka přepnutí na kartu „' + name + '“ — obsah této plochy zůstává');
    }
  }));
  return {
    aria: ARIA[lang], tabs, lang, labels: lbl, lblSt,
    fit: { rung: rung + 1, px: lpx, scale: Math.round(lpx / 11 * 100) / 100, clamped: lpx < Math.round(px0 * 100) / 100, short: lbl.some((l, i) => l !== full[i]), gap: Math.round(F.gap * 10) / 10, edge: Math.round(F.edge * 10) / 10, ok: F.ok },
    pillCls: 'nv-pill' + (n ? (n % 2 ? ' mA' : ' mB') : ''),
    pillSt: 'left:' + (Math.round(cur * col + (col - 52) / 2)) + 'px',
    arcSt: o.rk ? o.rk.arcSt : 'stroke-dasharray:50 100'
  };
}
