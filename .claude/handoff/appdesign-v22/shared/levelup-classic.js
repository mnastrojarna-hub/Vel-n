/* ===== level-up · FAITHFUL replica of today's celebration (loyalty_levelup_overlay.dart 2026-10-15) = shared/levelup-classic.js,
   pasted VERBATIM and identical in every board (DESIGN_V21 §6.7). Nothing here redesigns it; owner: "pozor lvl up video neměň".
   levelUpVals({ P, S, set, reduced, blocked, bike, brand, boardH, lang })
     P.rank = level before the jump · P.levelUpDemo "Vypnuto" | "+1 rank (jízda dokončena)" | "+2 ranky (výhra měsíce)"
     blocked = only what blocks TODAY: onboarding overlays + the payment screen (the board passes it; everything else does not defer, L5)
   Behaviour (as today): the NEXT tap anywhere opens it (global Listener → maybeRefreshLoyalty → watcher) at the tapped viewport;
   the theme (logo ring, chip, CTA) already shows the new level behind it; "Pokračovat" closes; only then is it "celebrated"
   (prefs mg_loyalty_last_level/_color_<uid> + RPC loyalty_advance_celebrated) → after that the Home note + deník entry.
   Prices follow the status the screen shows: the touch that refreshes it (trigger 1) switches look AND price to the new level at once,
   while the celebration opens over it (the discount never waits for "Pokračovat"; before that touch the cached status = old level).
   State keys: lu_key, lu_show, lu_done, lu_land, lu_cong, lu_y. */
function levelUpVals(o) {
  const P = o.P || {}, S = o.S || {}, set = o.set || function () {};
  const rm = !!o.reduced, H = o.boardH || 2400;
  const lg = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'].indexOf(String(o.lang || 'cs').slice(0, 2)) >= 0 ? String(o.lang || 'cs').slice(0, 2) : 'cs';
  const base = Math.max(1, Math.min(20, parseInt(P.rank, 10) || 3));
  const mode = String(P.levelUpDemo || '');
  const delta = mode.indexOf('+2') === 0 ? 2 : (mode.indexOf('+1') === 0 ? 1 : 0);
  const key = base + '|' + mode;
  const fresh = S.lu_key !== key;
  const to = Math.min(20, base + delta);
  const gained = to - base;
  const done = !fresh && !!S.lu_done;
  const show = !fresh && !!S.lu_show;
  const pending = gained > 0 && !done;
  const T = rankTheme(to), B = rankTheme(base);
  const turbo = gained >= 2, legend = to >= 20;
  // shipped strings (translations_ext_10_loyalty.dart, uk: translations_uk_ext_b.dart; rank names: translations_ext_35_loyalty_ranks.dart)
  const TX = {
    cs: ['NOVÝ RANK', 'MIMOŘÁDNÝ POSTUP', 'Tvoje sleva {pct} % platí napořád', 'Základní výhoda navždy — jen pro tebe v aplikaci. Díky, že jezdíš s MotoGo24.', 'TVŮJ STROJ', 'Pokračovat'],
    en: ['NEW RANK', 'EXCEPTIONAL JUMP', 'Your {pct} % discount is yours for good', 'A permanent benefit — exclusively yours in the app. Thanks for riding with MotoGo24.', 'YOUR RIDE', 'Continue'],
    de: ['NEUER RANG', 'AUSSERGEWÖHNLICHER AUFSTIEG', 'Dein Rabatt von {pct} % gilt für immer', 'Ein dauerhafter Vorteil — exklusiv für dich in der App. Danke, dass du mit MotoGo24 fährst.', 'DEINE MASCHINE', 'Weiter'],
    es: ['NUEVO RANGO', 'ASCENSO EXCEPCIONAL', 'Tu descuento del {pct} % es para siempre', 'Una ventaja permanente — exclusiva para ti en la app. Gracias por rodar con MotoGo24.', 'TU MOTO', 'Continuar'],
    fr: ['NOUVEAU RANG', 'ASCENSION EXCEPTIONNELLE', 'Ta remise de {pct} % est acquise pour toujours', 'Un avantage permanent — rien que pour toi dans l’app. Merci de rouler avec MotoGo24.', 'TA MOTO', 'Continuer'],
    nl: ['NIEUWE RANG', 'UITZONDERLIJKE SPRONG', 'Jouw korting van {pct} % geldt voor altijd', 'Een blijvend voordeel — exclusief voor jou in de app. Bedankt dat je met MotoGo24 rijdt.', 'JOUW MOTOR', 'Doorgaan'],
    pl: ['NOWA RANGA', 'WYJĄTKOWY AWANS', 'Twój rabat {pct} % obowiązuje na zawsze', 'Stała korzyść — wyłącznie dla Ciebie w aplikacji. Dzięki, że jeździsz z MotoGo24.', 'TWOJA MASZYNA', 'Kontynuuj'],
    uk: ['НОВИЙ РІВЕНЬ', 'НАДЗВИЧАЙНИЙ ПРОГРЕС', 'Ваша знижка {pct} % діє назавжди', 'Базова перевага назавжди — лише для вас у застосунку. Дякуємо, що їздите з MotoGo24.', 'ВАШ МОТОЦИКЛ', 'Продовжити']
  }[lg];
  const RN = {
    cs: ['Startér', 'Jezdec', 'Motorkář', 'Stálý jezdec', 'Věrný zákazník', 'Bronzový jezdec', 'Stříbrný jezdec', 'Zlatý jezdec', 'Platinový jezdec', 'Diamantový jezdec', 'Prémiový zákazník', 'Mistr silnic', 'Šampion', 'Veterán MotoGo', 'Elitní jezdec', 'Ambasador', 'VIP', 'VIP Gold', 'VIP Platinum', 'Legenda MotoGo'],
    en: ['Starter', 'Rider', 'Biker', 'Regular Rider', 'Loyal Customer', 'Bronze Rider', 'Silver Rider', 'Gold Rider', 'Platinum Rider', 'Diamond Rider', 'Premium Customer', 'Road Master', 'Champion', 'MotoGo Veteran', 'Elite Rider', 'Ambassador', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo Legend'],
    de: ['Starter', 'Fahrer', 'Biker', 'Stammfahrer', 'Treuer Kunde', 'Bronze-Fahrer', 'Silber-Fahrer', 'Gold-Fahrer', 'Platin-Fahrer', 'Diamant-Fahrer', 'Premium-Kunde', 'Meister der Straße', 'Champion', 'MotoGo-Veteran', 'Elite-Fahrer', 'Botschafter', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo-Legende'],
    es: ['Principiante', 'Piloto', 'Motero', 'Piloto habitual', 'Cliente fiel', 'Piloto de bronce', 'Piloto de plata', 'Piloto de oro', 'Piloto de platino', 'Piloto de diamante', 'Cliente prémium', 'Maestro de la carretera', 'Campeón', 'Veterano MotoGo', 'Piloto élite', 'Embajador', 'VIP', 'VIP Gold', 'VIP Platinum', 'Leyenda MotoGo'],
    fr: ['Débutant', 'Pilote', 'Motard', 'Pilote régulier', 'Client fidèle', 'Pilote bronze', 'Pilote argent', 'Pilote or', 'Pilote platine', 'Pilote diamant', 'Client premium', 'Maître de la route', 'Champion', 'Vétéran MotoGo', 'Pilote d’élite', 'Ambassadeur', 'VIP', 'VIP Gold', 'VIP Platinum', 'Légende MotoGo'],
    nl: ['Starter', 'Rijder', 'Motorrijder', 'Vaste rijder', 'Trouwe klant', 'Bronzen rijder', 'Zilveren rijder', 'Gouden rijder', 'Platina rijder', 'Diamanten rijder', 'Premium klant', 'Meester van de weg', 'Kampioen', 'MotoGo-veteraan', 'Eliterijder', 'Ambassadeur', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo-legende'],
    pl: ['Starter', 'Jeździec', 'Motocyklista', 'Stały jeździec', 'Wierny klient', 'Brązowy jeździec', 'Srebrny jeździec', 'Złoty jeździec', 'Platynowy jeździec', 'Diamentowy jeździec', 'Klient premium', 'Mistrz szos', 'Czempion', 'Weteran MotoGo', 'Elitarny jeździec', 'Ambasador', 'VIP', 'VIP Gold', 'VIP Platinum', 'Legenda MotoGo'],
    uk: ['Новачок', 'Райдер', 'Мотоцикліст', 'Постійний райдер', 'Вірний клієнт', 'Бронзовий райдер', 'Срібний райдер', 'Золотий райдер', 'Платиновий райдер', 'Діамантовий райдер', 'Преміум-клієнт', 'Майстер доріг', 'Чемпіон', 'Ветеран MotoGo', 'Елітний райдер', 'Амбасадор', 'VIP', 'VIP Gold', 'VIP Platinum', 'Легенда MotoGo']
  }[lg];
  // colours exactly as the overlay: accent = DB color_hex (rk.hex) · "+N" second stop = 25 % towards black · on-colour by luminance > .5 (L2)
  const hx = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const lum = (h) => { const c = hx(h).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const dk = (h) => '#' + hx(h).map((v) => Math.round(v * 0.75).toString(16).padStart(2, '0')).join('').toUpperCase();
  const onC = lum(T.hex) > 0.5 ? '#0F1A14' : '#FFFFFF';
  // burst = _BurstPainter: 46 particles (turbo 90), angle i/n·2π + sin(i·12.9898)·.35, speed .55–1, travel × shortestSide(390) × .8,
  // y × .9, radius 2.9 × (.6 … 1.4) → ×.4 at the end, every 3rd = secondary (white; Legenda orange) else the rank colour (Legenda gold)
  const n = turbo ? 90 : 46;
  const c1 = legend ? '#FFD700' : T.hex, c2 = legend ? '#FF8C00' : '#FFFFFF';
  const parts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * 2 * Math.PI + Math.sin(i * 12.9898) * 0.35;
    const sp = 0.55 + ((Math.sin(i * 78.233) + 1) / 2) * 0.45;
    const tr = sp * 390 * 0.8;
    const r = 2.9 * (0.6 + ((Math.sin(i * 39.425) + 1) / 2) * 0.8);
    parts.push({ st: '--x:' + Math.round(Math.cos(a) * tr) + 'px;--y:' + Math.round(Math.sin(a) * tr * 0.9) + 'px;--d:' + (2 * r).toFixed(1) + 'px;--c:' + (i % 3 === 0 ? c2 : c1) });
  }
  const y = Math.max(0, Math.min(H - 844, Math.round((S.lu_y || 422) - 422)));
  const openIt = (e) => {
    if (!pending || show || o.blocked) return;
    let ty = 422;
    try {
      const el = e && e.currentTarget;
      if (el && el.getBoundingClientRect && typeof e.clientY === 'number') {
        const rc = el.getBoundingClientRect(), z = rc.height / (el.offsetHeight || rc.height || 1);
        ty = (e.clientY - rc.top) / (z || 1);
      }
    } catch (err) { ty = 422; }
    set({ lu_key: key, lu_show: true, lu_done: false, lu_y: ty });
  };
  const bikeTitle = (o.brand || 'Husqvarna') + ' ' + (o.bike || 'Husqvarna 701 SM');   // RPC title = brand + model → doubled today (L1), drawn as rendered
  return {
    level: (done || show) ? to : base, priceLevel: (done || show) ? to : base, pending, show, done,
    cls: 'luc' + (turbo ? ' tb' : '') + (legend ? ' lg' : '') + (rm ? ' rm' : ''),
    st: 'top:' + y + 'px;--o:' + B.hex + ';--n:' + T.hex + ';--n2:' + dk(T.hex) + ';--on:' + onC,
    aria: TX[0] + ': ' + RN[to - 1] + ', ' + TX[2].replace('{pct}', T.pct),
    img: 'https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public/media/motos/b850929a-37da-4b87-86a8-9b2fba7b3316/mq22a7zapb2x-1000003421.jpg',
    parts, turbo, plus: '+' + gained,
    kicker: turbo ? TX[1] : TX[0], name: RN[to - 1], pctLine: TX[2].replace('{pct}', T.pct), note: TX[3],
    bikeLine: TX[4] + ' · ' + bikeTitle, cont: TX[5],
    ann: 'Ukázka: v appce ~67 s s hudbou a videi motorky (tady 5 s a pak stojí)' + (rm ? ' · omezené animace appka dnes nezná (L4), tady statický stav' : ''),
    go: () => set({ lu_show: false, lu_done: true, lu_land: (S.lu_land || 0) + 1, lu_cong: true }),
    tap: (e) => openIt(e),
    check: () => openIt(null),
    landCls: done && S.lu_land ? (S.lu_land % 2 ? 'rk-lA' : 'rk-lB') : '',
    congrats: done && S.lu_cong ? 'Gratulujeme, jsi ' + T.name + ' · sleva ' + T.pct + ' % platí hned' : '',
    entry: done ? { title: 'Nový rank: ' + T.name + ' (' + T.pct + ' %)', sub: (turbo ? 'Výhra měsíce · +2 ranky' : 'Za jízdu na Husqvarna 701 SM') + ' · dnes' } : null,
    from: B.name
  };
}
