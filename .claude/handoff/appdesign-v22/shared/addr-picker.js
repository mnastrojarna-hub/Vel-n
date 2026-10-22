/* ===== MotoGo24 app v2.2 · shared/addr-picker.js — paste VERBATIM inside renderVals(). Returns `ap` for shared/addr-picker.html.
   ONE address picker for Booking (přistavení / odvoz), Reservation (Úprava · Místo) and SOS (Náhradní motorka · adresa).
   Today's app: address_autocomplete_field.dart (Mapy.cz Suggest), booking_ui_helpers.dart (GPS · „Počítám km...“ · „~25 km · 2 000 Kč“),
   map_picker.dart (pin, „Hledám adresu...“, „Potvrdit adresu“). Copy is tykání (app keys selectPlaceOnMap / moveMapToPickup / enterAddress
   still vykají → port fix). Fee = 1 000 Kč + 40 Kč/km (PriceCalculator.deliveryBase / deliveryPerKm).
   apVals({ S, set, get, say, prop, lang, top, yOf, H, title, from, fromN, km, feeT, feeF, sos, onOk })
     prop  board prop „Výběr adresy“ (option labels below) · get() = current state for timers · top = px of the 844 viewport
           (or yOf + H: the viewport follows the tap on long boards) · km / feeT / feeF = demo distance, fee, formula (feeT null = no fee)
     sos   true = SOS: typing stays inline in the board (sheet never drawn); the picker adds the GPS lines (ap.ln) + the map
     onOk(addr) board hook after „Potvrdit adresu“
   → ap.open('type' | 'map') (event handler) · ap.sheet · ap.map · ap.ln · ap.addr (picked text or '')
   State keys: ap (object), apK (the prop value the state belongs to — a prop change in the editor reseeds). */
function apVals(o) {
  const S = o.S || {}, set = o.set || function () {}, say = o.say || function () {}, get = o.get || function () { return S; };
  const lg = ['cs', 'en', 'de', 'fr', 'uk'].indexOf(String(o.lang || 'cs').slice(0, 2)) >= 0 ? String(o.lang).slice(0, 2) : 'cs';
  const T = {
    cs: ['Adresa', 'Ulice a číslo domu, obec', 'Použít moji polohu', 'Vybrat na mapě', 'Zjišťuji polohu…', 'Polohu se nepodařilo zjistit', 'poloha v telefonu je vypnutá. Zapni polohu (GPS) v nastavení telefonu.', 'appka nemá přístup k poloze. Povol ho v Nastavení telefonu → MotoGo24 → Oprávnění.', 'Adresu můžeš zadat i ručně nebo vybrat na mapě.', 'Otevřít nastavení', 'GPS nedostupné — zadej adresu ručně nebo z mapy', 'Počítám km…', 'po silnici z ', 'Potvrdit adresu', 'Nejdřív vyber adresu', 'Vyber místo na mapě', 'Posuň mapu na místo přistavení', 'Hledám adresu…', 'Zpět', 'Zavřít', 'Moje poloha', 'Smazat', 'Posunout mapu (ukázka)', 'Návrhy adres', 'Adresa uložená', 'Otevře se nastavení telefonu'],
    en: ['Address', 'Street and number, town', 'Use my location', 'Pick on the map', 'Getting your location…', 'We couldn’t get your location', 'location is turned off on your phone. Turn on location (GPS) in your phone settings.', 'the app has no access to your location. Allow it in phone Settings → MotoGo24 → Permissions.', 'You can also type the address or pick it on the map.', 'Open settings', 'GPS unavailable — enter the address manually or from the map', 'Calculating km…', 'by road from ', 'Confirm address', 'Choose an address first', 'Pick a place on the map', 'Move the map to the delivery spot', 'Searching address…', 'Back', 'Close', 'My location', 'Clear', 'Move the map (demo)', 'Address suggestions', 'Address saved', 'Phone settings will open'],
    de: ['Adresse', 'Straße und Hausnummer, Ort', 'Meinen Standort verwenden', 'Auf der Karte wählen', 'Standort wird ermittelt…', 'Dein Standort konnte nicht ermittelt werden', 'der Standort ist auf deinem Handy ausgeschaltet. Schalte den Standort (GPS) in den Handy-Einstellungen ein.', 'die App hat keinen Zugriff auf deinen Standort. Erlaube es in den Handy-Einstellungen → MotoGo24 → Berechtigungen.', 'Du kannst die Adresse auch von Hand eingeben oder auf der Karte wählen.', 'Einstellungen öffnen', 'GPS nicht verfügbar — gib die Adresse von Hand oder über die Karte ein', 'Berechne km…', 'auf der Straße ab ', 'Adresse bestätigen', 'Wähle zuerst eine Adresse', 'Wähle einen Ort auf der Karte', 'Schiebe die Karte zum Zustellort', 'Adresse wird gesucht…', 'Zurück', 'Schließen', 'Mein Standort', 'Löschen', 'Karte verschieben (Demo)', 'Adressvorschläge', 'Adresse gespeichert', 'Die Handy-Einstellungen öffnen sich'],
    fr: ['Adresse', 'Rue et numéro, ville', 'Utiliser ma position', 'Choisir sur la carte', 'Localisation en cours…', 'Impossible de déterminer ta position', 'la localisation est désactivée sur ton téléphone. Active-la (GPS) dans les réglages du téléphone.', 'l’appli n’a pas accès à ta position. Autorise-la dans Réglages du téléphone → MotoGo24 → Autorisations.', 'Tu peux aussi saisir l’adresse ou la choisir sur la carte.', 'Ouvrir les réglages', 'GPS indisponible — saisis l’adresse à la main ou depuis la carte', 'Calcul des km…', 'par la route depuis ', 'Confirmer l’adresse', 'Choisis d’abord une adresse', 'Choisis un lieu sur la carte', 'Déplace la carte vers le lieu de livraison', 'Recherche de l’adresse…', 'Retour', 'Fermer', 'Ma position', 'Effacer', 'Déplacer la carte (démo)', 'Suggestions d’adresse', 'Adresse enregistrée', 'Les réglages du téléphone vont s’ouvrir'],
    uk: ['Адреса', 'Вулиця і номер, населений пункт', 'Використати мою геолокацію', 'Вибрати на карті', 'Визначаю місцезнаходження…', 'Не вдалося визначити твоє місцезнаходження', 'геолокацію в телефоні вимкнено. Увімкни геолокацію (GPS) у налаштуваннях телефону.', 'застосунок не має доступу до геолокації. Дозволь його в Налаштуваннях телефону → MotoGo24 → Дозволи.', 'Адресу можна ввести вручну або вибрати на карті.', 'Відкрити налаштування', 'GPS недоступний — введи адресу вручну або з карти', 'Обчислюю км…', 'дорогою від ', 'Підтвердити адресу', 'Спершу вибери адресу', 'Вибери місце на карті', 'Посунь карту на місце доставки', 'Шукаю адресу…', 'Назад', 'Закрити', 'Моє місцезнаходження', 'Очистити', 'Посунути карту (демо)', 'Підказки адрес', 'Адресу збережено', 'Відкриються налаштування телефону']
  }[lg];
  const IC = { warn: 'M12 8v5M12 16.5v.5M10.3 3.9 2.6 17.3A2 2 0 0 0 4.3 20.3h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
    road: 'M4 19a2 2 0 1 0 4 0a2 2 0 1 0-4 0M16 5a2 2 0 1 0 4 0a2 2 0 1 0-4 0M8 19h8.5a3.5 3.5 0 0 0 0-7h-9a3.5 3.5 0 0 1 0-7H16' };
  const ADDR = '[Ulice a č. p.], [PSČ] [Obec]', GPSA = '[poloha z GPS · ulice a č. p.], [Obec]', MAPA = '[ulice a č. p. pod špendlíkem], [Obec]';
  const prop = String(o.prop || 'Zavřeno');
  const SEED = { 'Psaní s návrhy': { ph: 'type', q: 'Pelhř' }, 'Zjišťuji polohu': { gps: 'busy' }, 'Poloha vypnutá': { gps: 'off' },
    'Poloha zamítnutá': { gps: 'perm' }, 'GPS bez signálu': { gps: 'nofix' }, 'Mapa · hledám adresu': { ph: 'map', srch: true },
    'Mapa · adresa nalezena': { ph: 'map' }, 'Počítám km': { q: ADDR, pick: true, km: 'busy' }, 'Adresa s km a cenou': { q: ADDR, pick: true, km: 'ok' } };
  const base = { on: false, ph: 'type', q: '', pick: false, gps: '', srch: false, km: '', mv: false, y: null };
  const seed = SEED[prop] ? Object.assign({}, base, { on: !(o.sos && !SEED[prop].ph), ph: 'type' }, SEED[prop]) : base;
  const A = S.apK === prop && S.ap ? S.ap : seed;
  const put = (p) => set({ ap: Object.assign({}, A, p), apK: prop });
  const later = (ms, p) => setTimeout(() => {
    try { const s0 = get() || {}; const a0 = s0.apK === prop && s0.ap ? s0.ap : A; set({ ap: Object.assign({}, a0, p), apK: prop }); } catch (err) { return; }
  }, ms);
  const hasFee = o.feeT !== null && o.feeT !== undefined;
  const picked = (q) => { put({ q, pick: true, gps: '', ph: 'type', srch: false, km: hasFee ? 'busy' : 'ok' }); if (hasFee) later(800, { km: 'ok' }); };
  const open = (ph) => (e) => {
    const y = o.yOf && e ? o.yOf(e) : A.y;
    put({ on: true, ph, srch: ph === 'map', y }); if (ph === 'map') later(900, { srch: false });
  };
  const H = o.H || 844, top = typeof o.top === 'number' ? o.top : (typeof A.y === 'number' ? Math.max(0, Math.min(H - 844, A.y - 420)) : 0);
  const q = String(A.q || ''), hasQ = q.length > 0, gb = A.gps === 'busy';
  const gpsA = () => { if (gb) return; put({ gps: 'busy' }); setTimeout(() => { try { const s0 = get() || {}; const a0 = s0.apK === prop && s0.ap ? s0.ap : A; if (a0.gps !== 'busy') return; } catch (err) { return; } later(0, { gps: '', q: GPSA, pick: true, km: hasFee ? 'busy' : 'ok' }); if (hasFee) later(800, { km: 'ok' }); if (o.sos && o.onOk) o.onOk(GPSA); }, 900); };
  const fail = A.gps === 'off' || A.gps === 'perm';
  const ln = gb ? { show: true, cls: 'ap-ln', spin: true, t: T[4], s: '' }
    : fail ? { show: true, cls: 'ap-ln w', ic: IC.warn, t: T[5] + ' – ' + T[A.gps === 'off' ? 6 : 7], s: T[8], set: true }
    : A.gps === 'nofix' ? { show: true, cls: 'ap-ln w', ic: IC.warn, t: T[10], s: '' }
    : A.pick && hasFee && A.km === 'busy' ? { show: true, cls: 'ap-ln', spin: true, t: T[11], s: '' }
    : A.pick && hasFee && A.km === 'ok' ? { show: true, cls: 'ap-ln ok', ic: IC.road, t: '~' + o.km + ' km ' + T[12] + (lg === 'cs' ? o.from : (o.fromN || o.from)) + ' · ' + o.feeT, s: o.feeF || '' }
    : { show: false, cls: 'ap-ln', t: '', s: '' };
  Object.assign(ln, { spin: !!ln.spin, hasIc: !!ln.ic && !ln.spin, ic: ln.ic || '', hasS: !!ln.s, set: !!ln.set, setL: T[9], setA: () => say(T[25] + ' → MotoGo24') });
  const okA = () => { if (!A.pick) { say(T[14]); return; } if (A.km === 'busy') return; put({ on: false }); if (o.onOk) o.onOk(q); say(T[24]); };
  const mOk = () => { if (A.srch) return; if (o.sos) { put({ on: false, ph: 'type', q: MAPA, pick: true, km: 'ok' }); if (o.onOk) o.onOk(MAPA); say(T[24]); return; } picked(MAPA); };
  const move = () => { put({ srch: true, mv: !A.mv }); later(900, { srch: false }); };
  return {
    open, sheet: !!A.on && A.ph === 'type' && !o.sos, map: !!A.on && A.ph === 'map', st: 'top:' + top + 'px',
    t: o.title || T[0], x: () => put({ on: false, gps: gb ? '' : A.gps }), xL: T[19],
    ph: T[1], q, hasQ, clrL: T[21], addr: A.pick ? q : '',
    inp: (e) => put({ q: String((e && e.target && e.target.value) || '').slice(0, 120), pick: false, km: '', gps: '' }),
    clr: () => put({ q: '', pick: false, km: '' }),
    sug: { show: hasQ && !A.pick && !gb, l: T[23], rows: [['[Ulice a č. p.]', '[PSČ] [Obec] · adresa'], ['[Ulice a č. p.]', '[PSČ] [Obec] · adresa'], ['[Obec]', 'obec · okres [okres]']]
      .map((r, i) => ({ a: r[0], b: r[1], st: 'animation-delay:' + (i * 50) + 'ms', pick: () => picked(r[0] === '[Obec]' ? '[Obec]' : ADDR) })) },
    gpsL: T[2], gpsA, gpsBusy: gb ? 'true' : 'false', mapL: T[3], mapA: open('map'), ln,
    ok: { l: T[13], a: okA, dis: A.pick && A.km !== 'busy' ? 'false' : 'true', hasWhy: !A.pick, why: T[14] },
    m: { t: T[15], hint: T[16], srch: !!A.srch, found: !A.srch, addr: A.srch ? T[17] : MAPA, tiles: 'ap-tiles' + (A.mv ? ' mv' : ''), pin: 'ap-pin' + (A.srch ? ' up' : ''),
      back: () => put(o.sos ? { on: false, ph: 'type' } : { ph: 'type', srch: false }), backL: T[18], move, moveL: T[22], me: move, meL: T[20],
      ok: mOk, okL: T[13], okDis: A.srch ? 'true' : 'false' }
  };
}
