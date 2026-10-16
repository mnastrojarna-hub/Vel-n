/* ===== MotoGo24 app v2.1 · shared/ai-fab.js — paste VERBATIM inside renderVals(). Returns the `ai` object for ai-fab.html.
   aiFabVals({ S, set, say, screen, mode, bottom, lang, nick, sos, coach, bike, fail })
     screen  'home'|'katalog'|'detail'|'booking'|'reservation' → context chips (like the real chat's quick prompts)
     mode    'full' (56 px, tabs) | 'mini' (44 px, above sticky bars) | 'peek' (half off-edge while scrolling) | 'hidden'
     bottom  px from the board bottom = lowest obstruction + 12 (110 above nav · 148 above Detail sticky · summary+12 on Booking)
     sos     true only while sosAllowed (= hasActiveRentalProvider) → red SOS chip first + the agent's SOS card after a reply
     coach   show the one-time bubble (Main only) · fail = demo of a failed reply (board "stavDat" = "Chyba sítě") → error bubble + retry
   Mirrors features/messages/ai_agent_screen.dart (2026-10-16): photo button → sheet aiTakePhoto / aiPickGallery, max 3 per message
   (aiPhotoLimit toast), thumbnails with ✕ above the input, typing = aiThinking, suggest_sos && sosAllowed → card reportSosIncident /
   clickToReportProblem → /sos, aiCommError / aiProcessError bubbles (+ "Zkusit znovu", DESIGN_V21 §7.0 error state).
   Localized (8 langs): every control label, the greeting, header, chips, SOS chip, app keys (shipped strings, emoji dropped — §7.0
   "no emoji in chrome"; the dots/icon carry it). Demo replies are board notes ("Ukázka: …", Czech) — never invented answers.
   State keys: ai_open, ai_msgs, ai_typing, ai_val, ai_coach, ai_seen, ai_ph, ai_src, ai_fails (no constructor entry needed). */
function aiFabVals(o) {
  const S = o.S || {}, set = o.set || function () {}, say = o.say || function () {};
  const LBL = { cs: 'AI Servisní agent', en: 'AI Service agent', de: 'KI-Serviceagent', es: 'Agente de servicio IA', fr: 'Agent de service IA', nl: 'AI-serviceagent', pl: 'Agent serwisowy AI', uk: 'AI Сервісний агент' };
  const lang = LBL[String(o.lang || 'cs').slice(0, 2)] ? String(o.lang || 'cs').slice(0, 2) : 'cs';
  const COACH = {                                  // one-time bubble: [text, close-button label]
    cs: ['Zeptej se kdykoli. Jsme tu pro tebe.', 'Zavřít nápovědu'], en: ['Ask any time. We’re here for you.', 'Close tip'],
    de: ['Frag jederzeit. Wir sind für dich da.', 'Hinweis schließen'], es: ['Pregunta cuando quieras. Estamos aquí para ti.', 'Cerrar consejo'],
    fr: ['Pose ta question quand tu veux. On est là pour toi.', 'Fermer l’astuce'], nl: ['Vraag het wanneer je wilt. We zijn er voor je.', 'Tip sluiten'],
    pl: ['Pytaj o każdej porze. Jesteśmy tu dla ciebie.', 'Zamknij podpowiedź'], uk: ['Питай будь-коли. Ми тут для тебе.', 'Закрити підказку']
  };
  // [scrim (unused: aria-hidden), close, typing (aiThinking), input label, placeholder, send, sub line, attach, remove photo {n}, cancel, retry]
  const UI = {
    cs: ['Zavřít AI asistenta', 'Zavřít', 'Přemýšlím…', 'Dotaz pro AI asistenta', 'Napiš dotaz…', 'Odeslat', 'Odpovídá hned · 24/7', 'Přiložit fotku', 'Odebrat fotku {n}', 'Zrušit', 'Zkusit znovu'],
    en: ['Close AI assistant', 'Close', 'Thinking…', 'Question for the AI assistant', 'Type your question…', 'Send', 'Replies right away · 24/7', 'Attach a photo', 'Remove photo {n}', 'Cancel', 'Retry'],
    de: ['KI-Assistent schließen', 'Schließen', 'Denke nach…', 'Frage an den KI-Assistenten', 'Schreib deine Frage…', 'Senden', 'Antwortet sofort · 24/7', 'Foto anhängen', 'Foto {n} entfernen', 'Abbrechen', 'Erneut versuchen'],
    es: ['Cerrar asistente IA', 'Cerrar', 'Pensando…', 'Pregunta para el asistente IA', 'Escribe tu pregunta…', 'Enviar', 'Responde al momento · 24/7', 'Adjuntar foto', 'Quitar foto {n}', 'Cancelar', 'Reintentar'],
    fr: ['Fermer l’assistant IA', 'Fermer', 'Réflexion…', 'Question pour l’assistant IA', 'Écris ta question…', 'Envoyer', 'Répond tout de suite · 24/7', 'Joindre une photo', 'Retirer la photo {n}', 'Annuler', 'Réessayer'],
    nl: ['AI-assistent sluiten', 'Sluiten', 'Aan het denken…', 'Vraag aan de AI-assistent', 'Typ je vraag…', 'Verzenden', 'Antwoordt meteen · 24/7', 'Foto toevoegen', 'Foto {n} verwijderen', 'Annuleren', 'Opnieuw proberen'],
    pl: ['Zamknij asystenta AI', 'Zamknij', 'Myślę…', 'Pytanie do asystenta AI', 'Napisz pytanie…', 'Wyślij', 'Odpowiada od razu · 24/7', 'Dołącz zdjęcie', 'Usuń zdjęcie {n}', 'Anuluj', 'Ponów'],
    uk: ['Закрити AI-асистента', 'Закрити', 'Думаю…', 'Запитання до AI-асистента', 'Напиши запитання…', 'Надіслати', 'Відповідає одразу · 24/7', 'Додати фото', 'Прибрати фото {n}', 'Скасувати', 'Спробувати знову']
  }[lang];
  // shipped app keys: [aiTakePhoto, aiPickGallery, aiPhotoLimit, aiPhotoError, reportSosIncident, clickToReportProblem, aiCommError, aiProcessError]
  const AK = {
    cs: ['Vyfotit budíky', 'Vybrat z galerie', 'Maximálně 3 fotky na zprávu', 'Fotku se nepodařilo načíst', 'Nahlásit SOS incident', 'Klepni a nahlas problém', 'Chyba komunikace s AI agentem. Zkus to znovu.', 'Omlouvám se, nepodařilo se zpracovat dotaz.'],
    en: ['Take a photo of the dash', 'Choose from gallery', 'Maximum 3 photos per message', 'Could not load the photo', 'Report SOS incident', 'Tap to report the problem', 'Error communicating with the AI agent. Please try again.', 'Sorry, I couldn\'t process the request.'],
    de: ['Cockpit fotografieren', 'Aus der Galerie wählen', 'Maximal 3 Fotos pro Nachricht', 'Foto konnte nicht geladen werden', 'SOS-Vorfall melden', 'Zum Melden des Problems tippen', 'Fehler bei der Kommunikation mit dem KI-Agenten. Bitte erneut versuchen.', 'Entschuldigung, die Anfrage konnte nicht verarbeitet werden.'],
    es: ['Fotografiar el salpicadero', 'Elegir de la galería', 'Máximo 3 fotos por mensaje', 'No se pudo cargar la foto', 'Reportar incidente SOS', 'Toque para reportar el problema', 'Error de comunicación con el agente IA. Inténtelo de nuevo.', 'Lo siento, no se pudo procesar la consulta.'],
    fr: ['Photographier le tableau de bord', 'Choisir dans la galerie', 'Maximum 3 photos par message', 'Impossible de charger la photo', 'Signaler un incident SOS', 'Touchez pour signaler le problème', 'Erreur de communication avec l\'agent IA. Veuillez réessayer.', 'Désolé, je n\'ai pas pu traiter la demande.'],
    nl: ['Dashboard fotograferen', 'Kies uit galerij', 'Maximaal 3 foto\'s per bericht', 'Foto kon niet worden geladen', 'SOS-incident melden', 'Tik om het probleem te melden', 'Communicatiefout met de AI-agent. Probeer het opnieuw.', 'Sorry, de vraag kon niet worden verwerkt.'],
    pl: ['Zrób zdjęcie zegarów', 'Wybierz z galerii', 'Maksymalnie 3 zdjęcia na wiadomość', 'Nie udało się wczytać zdjęcia', 'Zgłoś incydent SOS', 'Kliknij, aby zgłosić problem', 'Błąd komunikacji z agentem AI. Spróbuj ponownie.', 'Przepraszam, nie udało się przetworzyć zapytania.'],
    uk: ['Сфотографувати панель', 'Вибрати з галереї', 'Максимум 3 фото на повідомлення', 'Не вдалося завантажити фото', 'Повідомити про SOS-інцидент', 'Натисніть, щоб повідомити про проблему', 'Помилка зв’язку з AI-агентом. Спробуйте ще раз.', 'Вибачте, не вдалося обробити запит.']
  }[lang];
  const SOSL = { cs: 'Nehoda, krádež, porucha', en: 'Accident, theft, breakdown', de: 'Unfall, Diebstahl, Panne', es: 'Accidente, robo, avería', fr: 'Accident, vol, panne', nl: 'Ongeluk, diefstal, pech', pl: 'Wypadek, kradzież, awaria', uk: 'Аварія, крадіжка, поломка' }[lang];
  const HELLO = {                                  // tykání form of the app's aiGreeting (návrh) — promises what the agent really does
    cs: ['Ahoj', '! Jsem AI asistent MotoGo24. Poradím s kontrolkami, poruchami, návody i technickými dotazy — klidně pošli fotku budíků.'],
    en: ['Hi', '! I’m the MotoGo24 AI assistant. I can help with warning lights, faults, manuals and technical questions — feel free to send a photo of the dash.'],
    de: ['Hallo', '! Ich bin der KI-Assistent von MotoGo24. Ich helfe bei Kontrollleuchten, Störungen, Handbüchern und technischen Fragen — schick ruhig ein Foto vom Cockpit.'],
    es: ['¡Hola', '! Soy el asistente IA de MotoGo24. Te ayudo con testigos, averías, manuales y dudas técnicas; si quieres, envía una foto del salpicadero.'],
    fr: ['Salut', ' ! Je suis l’assistant IA de MotoGo24. Je t’aide pour les voyants, pannes, manuels et questions techniques — envoie une photo du tableau de bord si besoin.'],
    nl: ['Hoi', '! Ik ben de AI-assistent van MotoGo24. Ik help met waarschuwingslampjes, storingen, handleidingen en technische vragen — stuur gerust een foto van het dashboard.'],
    pl: ['Cześć', '! Jestem asystentem AI MotoGo24. Pomogę z kontrolkami, usterkami, instrukcjami i pytaniami technicznymi — możesz wysłać zdjęcie zegarów.'],
    uk: ['Привіт', '! Я AI-асистент MotoGo24. Допоможу з індикаторами, несправностями, інструкціями й технічними питаннями — можеш надіслати фото панелі.']
  }[lang];
  const bike = o.bike || ({ cs: 'tuhle motorku', en: 'this bike', de: 'dieses Motorrad', es: 'esta moto', fr: 'cette moto', nl: 'deze motor', pl: 'ten motocykl', uk: 'цей мотоцикл' }[lang]);
  const CHL = {
    cs: { home: ['Kódy a postup na pobočce', 'Kam o víkendu?', 'Jak vrátit motorku'], katalog: ['Poraď mi motorku', 'Jaký potřebuju řidičák?', 'Jak funguje samoobsluha?'],
      detail: ['Zeptej se na ' + bike, 'Hodí se pro spolujezdce?', 'Kolik stojí přistavení?'], booking: ['Jak funguje vyzvednutí od 12:00?', 'Můžu termín později změnit?', 'Platba a storno'], ext: 'Prodloužit rezervaci' },
    en: { home: ['Codes and steps at the branch', 'Where to ride this weekend?', 'How to return the bike'], katalog: ['Recommend me a bike', 'Which licence do I need?', 'How does self-service work?'],
      detail: ['Ask about ' + bike, 'Is it good with a passenger?', 'How much is delivery?'], booking: ['How does pick-up from 12:00 work?', 'Can I change the dates later?', 'Payment and cancellation'], ext: 'Extend my booking' },
    de: { home: ['Codes und Ablauf an der Filiale', 'Wohin am Wochenende?', 'Wie gebe ich das Motorrad zurück?'], katalog: ['Empfiehl mir ein Motorrad', 'Welchen Führerschein brauche ich?', 'Wie funktioniert die Selbstbedienung?'],
      detail: ['Fragen zu ' + bike, 'Taugt sie für einen Sozius?', 'Was kostet die Zustellung?'], booking: ['Wie funktioniert die Abholung ab 12:00?', 'Kann ich den Termin später ändern?', 'Zahlung und Storno'], ext: 'Buchung verlängern' },
    es: { home: ['Códigos y pasos en la sucursal', '¿Adónde ir el fin de semana?', 'Cómo devolver la moto'], katalog: ['Recomiéndame una moto', '¿Qué carné necesito?', '¿Cómo funciona el autoservicio?'],
      detail: ['Pregunta sobre ' + bike, '¿Sirve para ir con pasajero?', '¿Cuánto cuesta la entrega?'], booking: ['¿Cómo funciona la recogida desde las 12:00?', '¿Puedo cambiar las fechas después?', 'Pago y cancelación'], ext: 'Ampliar la reserva' },
    fr: { home: ['Codes et étapes à l’agence', 'Où rouler ce week-end ?', 'Comment rendre la moto'], katalog: ['Conseille-moi une moto', 'Quel permis me faut-il ?', 'Comment marche le libre-service ?'],
      detail: ['Question sur ' + bike, 'Convient-elle à un passager ?', 'Combien coûte la livraison ?'], booking: ['Comment marche le retrait dès 12:00 ?', 'Puis-je changer les dates plus tard ?', 'Paiement et annulation'], ext: 'Prolonger la réservation' },
    nl: { home: ['Codes en stappen bij het filiaal', 'Waarheen dit weekend?', 'Hoe lever ik de motor in?'], katalog: ['Raad me een motor aan', 'Welk rijbewijs heb ik nodig?', 'Hoe werkt de selfservice?'],
      detail: ['Vraag over ' + bike, 'Geschikt voor een passagier?', 'Wat kost bezorgen?'], booking: ['Hoe werkt ophalen vanaf 12:00?', 'Kan ik de datum later wijzigen?', 'Betaling en annulering'], ext: 'Boeking verlengen' },
    pl: { home: ['Kody i procedura w oddziale', 'Dokąd na weekend?', 'Jak oddać motocykl'], katalog: ['Doradź mi motocykl', 'Jakiego prawa jazdy potrzebuję?', 'Jak działa samoobsługa?'],
      detail: ['Zapytaj o ' + bike, 'Czy nadaje się dla pasażera?', 'Ile kosztuje dostawa?'], booking: ['Jak działa odbiór od 12:00?', 'Czy mogę później zmienić termin?', 'Płatność i anulowanie'], ext: 'Przedłużyć rezerwację' },
    uk: { home: ['Коди й порядок на філії', 'Куди на вихідні?', 'Як повернути мотоцикл'], katalog: ['Порадь мені мотоцикл', 'Які права мені потрібні?', 'Як працює самообслуговування?'],
      detail: ['Запитай про ' + bike, 'Чи підходить для пасажира?', 'Скільки коштує доставка?'], booking: ['Як працює видача з 12:00?', 'Чи можу пізніше змінити дати?', 'Оплата і скасування'], ext: 'Продовжити бронювання' }
  }[lang];
  const CH = { home: CHL.home, katalog: CHL.katalog, detail: CHL.detail, booking: CHL.booking, reservation: [CHL.home[0], CHL.ext, CHL.home[2]] };
  const mode = o.mode || 'full';
  const bottom = o.bottom === undefined ? 110 : o.bottom;
  const open = !!S.ai_open;
  const msgs = (S.ai_msgs || []).slice();
  const ph = Math.max(0, Math.min(3, parseInt(S.ai_ph, 10) || 0));       // photos attached to the next message (0–3)
  const sosAllowed = !!o.sos;
  const sosOpen = () => say('Otevře se SOS (/sos) — volání a hlášení jsou až další, vědomé kroky');
  const ask = (q, isRetry) => {
    const base = msgs.filter((m) => !(isRetry && m.k === 'err'));
    const m = isRetry ? base : base.concat([{ cls: 'ai-m me', t: q, ph }]);
    const fails = !!o.fail && !(S.ai_fails > 0);
    set({ ai_msgs: m, ai_typing: true, ai_val: '', ai_ph: 0, ai_src: false });
    setTimeout(() => {
      if (fails) { set({ ai_typing: false, ai_fails: (S.ai_fails || 0) + 1, ai_msgs: m.concat([{ k: 'err', t: AK[6], q }]) }); return; }
      const note = ph ? 'Ukázka: AI porovná ' + ph + (ph === 1 ? ' fotku' : ' fotky') + ' budíků s návodem motorky a odpoví — zná i tvoji rezervaci.' : 'Ukázka: odpověď napíše AI asistent — zná tvoji rezervaci i pobočku.';
      set({ ai_typing: false, ai_msgs: m.concat([{ cls: 'ai-m note', t: note }]).concat(sosAllowed && ph ? [{ k: 'sos' }] : []) });
    }, 1300);
  };
  const sosChip = { l: 'SOS · ' + SOSL, sos: true };
  const chips = (o.sos ? [sosChip] : []).concat((CH[o.screen] || CH.home).map((l) => ({ l })))
    .map((c, i) => ({ l: c.l, cls: 'ai-chip' + (c.sos ? ' sos' : ''), st: 'animation-delay:' + (120 + i * 60) + 'ms',
      a: () => (c.sos ? sosOpen() : ask(c.l)) }));
  const thumb = (n) => ({ n: String(n), st: 'animation-delay:' + (n * 60) + 'ms', xa: UI[8].replace('{n}', n), x: () => set({ ai_ph: Math.max(0, ph - 1) }) });
  const pick = () => {
    if (o.fail === 'photo') { set({ ai_src: false }); say(AK[3]); return; }
    set({ ai_src: false, ai_ph: Math.min(3, ph + 1) });
  };
  const norm = (m) => {
    const sos = m.k === 'sos', err = m.k === 'err', n = Math.max(0, Math.min(3, parseInt(m.ph, 10) || 0));
    return { cls: m.cls || 'ai-m bot', t: m.t || '', txt: !sos && !err, sos, err, hasPh: n > 0,
      ph: Array.from({ length: n }, (_, i) => ({ n: String(i + 1) })), phT: n ? '[' + n + '× foto]' : '',
      sosT: AK[4], sosS: AK[5], a: sosOpen, retryL: UI[10], retry: () => ask(m.q || '', true) };
  };
  const hello = HELLO[0] + (o.nick ? ', ' + o.nick : '') + HELLO[1];
  return {
    showFab: mode !== 'hidden' && !open,
    cls: 'ai-fab' + (mode === 'mini' ? ' mini' : '') + (mode === 'peek' ? ' peek' : '') + (S.ai_seen ? '' : ' in'),
    st: 'bottom:' + bottom + 'px',
    aria: LBL[lang],
    a: () => set({ ai_open: true, ai_coach: 'off', ai_seen: true }),
    coach: { show: !!o.coach && S.ai_coach !== 'off' && !open && mode !== 'hidden', st: 'bottom:' + (bottom + 10) + 'px', a: () => set({ ai_coach: 'off' }),
      t: COACH[lang][0], x: COACH[lang][1] },
    chat: {
      show: open, st: 'bottom:' + Math.max(12, bottom - 4) + 'px',
      title: LBL[lang], sub: UI[6], closeL: UI[1], inL: UI[3], ph: UI[4], sendL: UI[5], thinking: UI[2],
      msgs: [{ cls: 'ai-m bot', t: hello }].concat(msgs).map(norm), typing: !!S.ai_typing, chips,
      val: S.ai_val || '', input: (e) => set({ ai_val: (e && e.target && e.target.value) || '' }),
      send: () => { const q = String(S.ai_val || '').trim(); if (q || ph) ask(q || '[' + ph + '× foto]'); else say('Napiš dotaz, nebo klepni na návrh'); },
      close: () => set({ ai_open: false, ai_typing: false, ai_src: false }),
      camL: UI[7], camCls: 'ai-cam' + (ph ? ' on' : ''), camN: ph ? String(ph) : '', hasN: ph > 0, srcOpen: S.ai_src ? 'true' : 'false',
      cam: () => { if (ph >= 3) { say(AK[2]); return; } set({ ai_src: !S.ai_src }); },
      att: { show: ph > 0, list: Array.from({ length: ph }, (_, i) => thumb(i + 1)), cnt: ph + '/3' },
      src: { show: !!S.ai_src && ph < 3, aria: UI[7], camT: AK[0], galT: AK[1], cancel: UI[9], cam: pick, gal: pick, close: () => set({ ai_src: false }) }
    }
  };
}
