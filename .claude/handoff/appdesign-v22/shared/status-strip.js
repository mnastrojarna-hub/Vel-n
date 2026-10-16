/* ===== MotoGo24 app v2.1 · shared/status-strip.js — paste VERBATIM inside renderVals(). Returns `gs` for status-strip.html.
   The app shell's global FABs (app_shell.dart, 2026-10-16) as ONE status strip under every tab screen (spec §3 C2, §11 rows 4–8):
   priority SOS > payment > documents > route > cart; the most urgent item shows, "+n" opens the full list. Nothing from today is lost:
     SOS dokončit (pending replacement) · Dokončit rezervaci · mm:ss + red ✕ (→ "Zrušit rezervaci?" Zpět / Zrušit rezervaci, cancelError) ·
     NAHRÁT DOKLADY · Pokračovat v trase · name + ✕ · Košík ({count}) · {total} (eshop flag).
   stripVals({ S, set, say, lang, item, hidden, onCancel })
     item     board prop "globální stav" (Czech option label, see GS_OPTS); hidden = a sheet / dialog / focused flow is open
     onCancel optional board hook after a confirmed cancel (Main: ticket S2 → S0)
   → gs.show / gs.lift (px the AI FAB rises: 60) / gs.needs (REZERVACE badge: payment or documents) / gs.cf (confirm dialog) / gs.askCancel()
   State keys: gs_x (dismissed map), gs_all (list open), gs_cf (dialog open), gs_err (cancel failed once). Shipped keys: sosCompleteFab,
   completeBookingFab, docsBlockingBtn, routeFabContinue, cartFab, cancelReservationQ, back, cancelReservationBtn, cancelError (rest = návrh). */
function stripVals(o) {
  const S = o.S || {}, set = o.set || function () {}, say = o.say || function () {};
  const lg = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'].indexOf(String(o.lang || 'cs').slice(0, 2)) >= 0 ? String(o.lang || 'cs').slice(0, 2) : 'cs';
  // [sosCompleteFab, sos sub, completeBookingFab, left {t}, docs (docsBlockingBtn, sentence case), docs sub, routeFabContinue, route sub,
  //  cartFab, cart sub, region label, more label, close list, end route, cancelReservationQ, cancel body, back, cancelReservationBtn, cancelError, cancelled]
  const T = {
    cs: ['SOS dokončit', 'Vyber náhradní motorku', 'Dokončit rezervaci', 'Zbývá {t}', 'Nahrát doklady', 'Kódy k pobočce uvolníme po nahrání', 'Pokračovat v trase', 'Navigace · bod 3/7', 'Košík ({count}) · {total} Kč', 'Dokončit objednávku', 'Rozdělané věci', 'Další: {n}', 'Zavřít seznam', 'Ukončit trasu', 'Zrušit rezervaci?', 'Nedokončená rezervace se zruší a termín se uvolní.', 'Zpět', 'Zrušit rezervaci', 'Chyba storna', 'Rezervace zrušena'],
    en: ['SOS complete', 'Choose a replacement bike', 'Complete booking', '{t} left', 'Upload documents', 'We release your branch codes once they’re uploaded', 'Continue route', 'Navigation · stop 3/7', 'Cart ({count}) · {total} CZK', 'Finish your order', 'Things in progress', 'More: {n}', 'Close list', 'End route', 'Cancel booking?', 'The unfinished booking is cancelled and the dates are released.', 'Back', 'Cancel reservation', 'Cancellation error', 'Booking cancelled'],
    de: ['SOS abschließen', 'Ersatzmotorrad wählen', 'Buchung abschließen', 'Noch {t}', 'Dokumente hochladen', 'Die Filial-Codes geben wir nach dem Hochladen frei', 'Route fortsetzen', 'Navigation · Stopp 3/7', 'Warenkorb ({count}) · {total} CZK', 'Bestellung abschließen', 'Offene Vorgänge', 'Weitere: {n}', 'Liste schließen', 'Route beenden', 'Buchung stornieren?', 'Die unvollständige Buchung wird storniert und der Termin freigegeben.', 'Zurück', 'Reservierung stornieren', 'Stornierungsfehler', 'Buchung storniert'],
    es: ['SOS completar', 'Elige la moto de sustitución', 'Completar reserva', 'Quedan {t}', 'Subir documentos', 'Liberamos los códigos de la sucursal al subirlos', 'Continuar la ruta', 'Navegación · parada 3/7', 'Carrito ({count}) · {total} CZK', 'Terminar el pedido', 'Pendientes', 'Más: {n}', 'Cerrar lista', 'Terminar ruta', '¿Cancelar reserva?', 'La reserva sin terminar se cancela y las fechas quedan libres.', 'Atrás', 'Cancelar reserva', 'Error de cancelación', 'Reserva cancelada'],
    fr: ['SOS terminer', 'Choisis la moto de remplacement', 'Terminer la réservation', 'Encore {t}', 'Télécharger les documents', 'Codes de l’agence débloqués après l’envoi', 'Reprendre l\'itinéraire', 'Navigation · étape 3/7', 'Panier ({count}) · {total} CZK', 'Finaliser la commande', 'En cours', 'Plus : {n}', 'Fermer la liste', 'Terminer l’itinéraire', 'Annuler la réservation ?', 'La réservation inachevée est annulée et les dates sont libérées.', 'Retour', 'Annuler la réservation', 'Erreur d\'annulation', 'Réservation annulée'],
    nl: ['SOS voltooien', 'Kies een vervangende motor', 'Boeking voltooien', 'Nog {t}', 'Documenten uploaden', 'De filiaalcodes geven we vrij na het uploaden', 'Route hervatten', 'Navigatie · stop 3/7', 'Winkelwagen ({count}) · {total} CZK', 'Bestelling afronden', 'Lopende zaken', 'Meer: {n}', 'Lijst sluiten', 'Route beëindigen', 'Boeking annuleren?', 'De onvoltooide boeking wordt geannuleerd en de data komen vrij.', 'Terug', 'Reservering annuleren', 'Annuleringsfout', 'Boeking geannuleerd'],
    pl: ['SOS dokończ', 'Wybierz motocykl zastępczy', 'Dokończ rezerwację', 'Zostało {t}', 'Wgraj dokumenty', 'Kody do oddziału odblokujemy po wgraniu', 'Kontynuuj trasę', 'Nawigacja · punkt 3/7', 'Koszyk ({count}) · {total} CZK', 'Dokończ zamówienie', 'W toku', 'Więcej: {n}', 'Zamknij listę', 'Zakończ trasę', 'Anulować rezerwację?', 'Niedokończona rezerwacja zostanie anulowana, a termin zwolniony.', 'Wstecz', 'Anuluj rezerwację', 'Błąd anulowania', 'Rezerwacja anulowana'],
    uk: ['SOS завершити', 'Обери мотоцикл на заміну', 'Завершити бронювання', 'Залишилось {t}', 'Завантажити документи', 'Коди до філії відкриємо після завантаження', 'Продовжити маршрут', 'Навігація · точка 3/7', 'Кошик ({count}) · {total} CZK', 'Завершити замовлення', 'Незавершене', 'Ще: {n}', 'Закрити список', 'Завершити маршрут', 'Скасувати бронювання?', 'Незавершене бронювання буде скасовано, а дати звільняться.', 'Назад', 'Скасувати бронювання', 'Помилка скасування', 'Бронювання скасовано']
  }[lg];
  const IC = { sos: 'M12 8v5M12 16.5v.5M10.3 3.9 2.6 17.3A2 2 0 0 0 4.3 20.3h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z', pay: 'M3 6h18v12H3zM3 10h18M7 15h4',
    docs: 'M7 3h7l5 5v13H7zM14 3v5h5M12 18v-6M9.5 14.5 12 12l2.5 2.5', route: 'M4 19a2 2 0 1 0 4 0a2 2 0 1 0-4 0M16 5a2 2 0 1 0 4 0a2 2 0 1 0-4 0M8 19h8.5a3.5 3.5 0 0 0 0-7h-9a3.5 3.5 0 0 1 0-7H16',
    cart: 'M3 4h2.5l2.4 11.2a1.5 1.5 0 0 0 1.5 1.2h8.4a1.5 1.5 0 0 0 1.5-1.1L21 8H6.3M9.5 20.5h.01M17.5 20.5h.01' };
  const item = String(o.item || '');
  const want = item.indexOf('Více') === 0 ? ['pay', 'docs', 'route'] : (item.indexOf('SOS') === 0 ? ['sos'] : (item.indexOf('Rozdělaná platba') === 0 ? ['pay'] : (item.indexOf('Chybí doklady') === 0 ? ['docs']
    : (item.indexOf('Rozjetá trasa') === 0 ? ['route'] : (item.indexOf('Košík') === 0 ? ['cart'] : [])))));
  const failCancel = item.indexOf('storno selže') >= 0 && !S.gs_err;
  const gone = S.gs_x || {};
  const ORDER = ['sos', 'pay', 'docs', 'route', 'cart'];
  const items = ORDER.filter((k) => want.indexOf(k) >= 0 && !gone[k]);
  const close = () => set({ gs_all: false });
  const askCancel = () => set({ gs_cf: true, gs_all: false });
  const def = {
    sos: { t: T[0], s: T[1], icCls: 'gs-i sos', a: () => say('Otevře se SOS · výběr náhradní motorky (/sos/replacement)'), x: null },
    pay: { t: T[2], s: T[3].replace('{t}', '14:52') + ' · Husqvarna 701 SM · 12 027 Kč', icCls: 'gs-i pay', a: () => say('Platba (/payment) → board 5 · Rezervace expres, Režim platby „Dokončit nedokončenou“ · časovač běží dál'), x: askCancel, xL: T[17] },
    docs: { t: T[4], s: T[5], icCls: 'gs-i docs', a: () => say('Otevře se skener dokladů (OP / pas + ŘP)'), x: null },
    route: { t: T[6] + ' · Vodní krásy', s: T[7], icCls: 'gs-i route', a: () => say('Pokračuju v navigaci „Vodní krásy: Věstonická nádrž“ (board 9 · Trasa a navigace)'),
      x: () => { set({ gs_x: Object.assign({}, gone, { route: true }), gs_all: false }); say(T[13] + ' · ukázka'); }, xL: T[13] },
    cart: { t: T[8].replace('{count}', '2').replace('{total}', '[částka]'), s: T[9], icCls: 'gs-i cart', a: () => say('Otevře se košík e-shopu (/shop/cart) · jen při zapnutém e-shopu'), x: null }
  };
  const row = (k, i) => { const d = def[k]; return { k, t: d.t, s: d.s, icCls: d.icCls, ic: IC[k], a: d.a, aria: d.t + ' – ' + d.s, hasX: !!d.x, x: d.x || (() => {}), xL: d.xL || '', st: 'animation-delay:' + (i * 60) + 'ms' }; };
  const top = items.length ? row(items[0], 0) : null;
  const show = !!top && !o.hidden;
  const yes = () => {
    if (failCancel) { set({ gs_cf: false, gs_err: true }); say(T[18]); return; }
    set({ gs_cf: false, gs_x: Object.assign({}, gone, { pay: true }) }); say(T[19]);
    if (o.onCancel) o.onCancel();
  };
  return {
    show, cls: 'gs' + (items.length > 1 ? ' multi' : ''), region: T[10],
    t: top ? top.t : '', s: top ? top.s : '', icCls: top ? top.icCls : 'gs-i', ic: top ? top.ic : '', a: top ? top.a : () => {}, aria: top ? top.aria : '',
    hasX: !!(top && top.hasX), x: top ? top.x : () => {}, xL: top ? top.xL : '',
    hasMore: items.length > 1, more: '+' + Math.max(0, items.length - 1), moreL: T[11].replace('{n}', Math.max(0, items.length - 1)), moreOn: S.gs_all ? 'true' : 'false',
    moreA: () => set({ gs_all: !S.gs_all }),
    all: { show: show && !!S.gs_all && items.length > 1, rows: items.map(row), close, closeL: T[12] },
    lift: show ? 60 : 0, needs: items.indexOf('pay') >= 0 || items.indexOf('docs') >= 0,
    askCancel,
    cf: { show: !!S.gs_cf, t: T[14], p: T[15], noL: T[16], yesL: T[17], no: () => set({ gs_cf: false }), yes }
  };
}
