/* ===== MotoGo24 app v2.2 · shared/push-banner.js — paste VERBATIM inside renderVals(). Returns `pb` for shared/push-banner.html.
   Foreground push banner (core/push/notification_handler.dart, 16. 10.): door codes = prominent green banner, key, title + body up to 4 lines,
   8 s, action „Zobrazit“ (manualView) → Zprávy ?n=<id>; any other message = night banner, title + 2 lines, 5 s, same action. Title / body come
   from admin_messages (title_translations / message_translations, body ≤ 200 chars) — e.g. _door_codes_notify 'Přístupové kódy k pobočce'.
   pushVals({ S, set, say, prop, lang, top })  prop = board prop „Push (aplikace otevřená)“: 'Žádný' | 'Kódy dorazily' | 'Nová zpráva'
   → pb.show / pb.key … State key: pb_x (the prop value that was dismissed — changing the prop shows the banner again). */
function pushVals(o) {
  const S = o.S || {}, set = o.set || function () {}, say = o.say || function () {};
  const prop = String(o.prop || 'Žádný'), k = prop === 'Kódy dorazily' ? 'key' : (prop === 'Nová zpráva' ? 'msg' : '');
  const lg = String(o.lang || 'cs').slice(0, 2);
  const VIEW = { cs: 'Zobrazit', en: 'View', de: 'Anzeigen', es: 'Ver', fr: 'Afficher', nl: 'Bekijken', pl: 'Wyświetl', uk: 'Переглянути' }[lg] || 'Zobrazit';
  const X = { cs: 'Zavřít', en: 'Close', de: 'Schließen', es: 'Cerrar', fr: 'Fermer', nl: 'Sluiten', pl: 'Zamknij', uk: 'Закрити' }[lg] || 'Zavřít';
  const key = k === 'key';
  const close = () => set({ pb_x: prop });
  return {
    show: !!k && S.pb_x !== prop, key, msg: !key, cls: 'pb ' + (key ? 'key' : 'msg'),
    st: 'top:' + (typeof o.top === 'number' ? o.top : 52) + 'px;--pb-d:' + (key ? 8 : 5) + 's',
    t: key ? 'Přístupové kódy k pobočce' : '[Předmět zprávy od MotoGo24]',
    b: key ? '[Text zprávy s kódy: pobočka, kód motorky, kód šatny, platnost — max 4 řádky]' : '[Text zprávy — max 2 řádky]',
    l: VIEW, x: close, xL: X, live: key ? 'assertive' : 'polite',
    a: () => { close(); say(key ? 'Otevře se Zprávy · vlákno s kódy (/messages?n=[id])' : 'Otevře se Zprávy · vlákno (/messages?n=[id])'); }
  };
}
