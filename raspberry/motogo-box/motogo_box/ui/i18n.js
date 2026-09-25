/* MotoGo24 kiosk — jazyky zákaznické obrazovky (stejných 8 jazyků jako appka/web).
   Servisní panel, setup a diagnostika zůstávají česky (technik). Vanilla JS, offline. */
'use strict';
window.MG = window.MG || {};

MG.i18n = (function () {
  const SUPPORT = '+420 774 256 271';
  const DEFAULT = 'cs';
  const LANGS = [
    ['cs', '🇨🇿', 'CZ'], ['en', '🇬🇧', 'EN'], ['de', '🇩🇪', 'DE'], ['es', '🇪🇸', 'ES'],
    ['fr', '🇫🇷', 'FR'], ['nl', '🇳🇱', 'NL'], ['pl', '🇵🇱', 'PL'], ['uk', '🇺🇦', 'UA'],
  ];
  const S = {
    cs: { banner: 'Řídicí jednotka nedostupná — zkuste to prosím za chvíli',
      promptTitle: 'Zadejte přístupový kód', hint1: 'Kód najdete v aplikaci MotoGo24 — v detailu rezervace a ve zprávách — nebo v potvrzovacím e‑mailu.',
      hint2: 'Berete si oblečení? Zadejte nejdřív kód šatny, potom kód motorky. Máte vlastní výbavu? Zadejte rovnou kód motorky.',
      clear: 'SMAZAT', tap: 'Klepnutím zavřete', verifying: 'Ověřuji kód…', opened: 'Otevřeno', support: 'Podpora',
      okAcc: 'Vezměte si výbavu a zavřete dveře šatny.', okMoto: 'Příjemnou cestu! 🏍️',
      acc: 'Šatna', box: 'Kóje {n}', zone: 'Zóna {n}', closed: 'zavřeno', open: 'otevřeno', unknown: 'neznámo',
      st: { SECURED: 'Zamčeno', WAITING_FOR_OPEN: 'Otevřete dveře', DOOR_OPEN: 'Otevřeno', CLOSED_CONFIRMATION: 'Zavřeno', FAULT: 'Porucha' },
      fa: { io_offline: 'I/O modul nedostupný', forced_open: 'dveře otevřeny bez kódu', open_at_startup: 'dveře otevřené při startu', contact_fault: 'porucha dveřního kontaktu', fault: 'porucha' },
      et: { invalid_code: 'Neplatný kód', network: 'Chyba spojení', locked: 'Zadávání dočasně zablokováno', zone_not_configured: 'Dveře nejsou nastaveny',
        io_offline: 'Kóje je mimo provoz', door_open: 'Dveře jsou otevřené', busy: 'Kóje je právě používána', lock_failed: 'Dveře se neozvaly', fault: 'Porucha kóje',
        empty_code: 'Zadejte kód', not_ready: 'Jednotka startuje', unavailable: 'Kód nelze ověřit',
        protocol_required: 'Nejdřív podepište protokol', protocol_failed: 'Protokol se nepodařilo uložit' },
      es: { invalid_code: 'Kód nebyl rozpoznán nebo už není platný.', network: 'Chyba spojení. Zkontrolujte internet a zkuste znovu.',
        zone_not_configured: 'Kód je platný, ale dveře nejsou ve Velíně nastaveny. Kontaktujte podporu: {s}.',
        io_offline: 'Řídicí modul kóje je nedostupný. Kontaktujte podporu: {s}.', door_open: 'Dveře jsou už otevřené — zavřete je a zadejte kód znovu.',
        fault: 'Kóje hlásí poruchu. Kontaktujte podporu: {s}.', unauthorized: 'Kiosk není správně spárovaný s pobočkou.',
        not_ready: 'Řídicí jednotka právě startuje. Zkuste to prosím za chvíli.', retry: 'Zkuste to prosím znovu nebo kontaktujte podporu: {s}.', again: 'Zkuste to prosím znovu.',
        lockedMin: 'Příliš mnoho neplatných pokusů. Zkuste to znovu za {m} min.', lockedLater: 'Příliš mnoho neplatných pokusů. Zkuste to později.',
        protocol_required: 'Kód motorky je v pořádku. Kóje se otevře až po podpisu předávacího protokolu — na displeji nebo v aplikaci MotoGo24.' },
      al: { unit: 'Řídicí jednotka: ', overtime: '{z}: dveře jsou otevřené příliš dlouho — zavřete je prosím.', fault: '{z}: {f} — kontaktujte podporu {s}' } },
    en: { banner: 'Control unit unavailable — please try again in a moment',
      promptTitle: 'Enter your access code', hint1: 'You will find the code in the MotoGo24 app — in the booking detail and in messages — or in the confirmation e-mail.',
      hint2: 'Renting gear? Enter the locker code first, then the motorcycle code. Bringing your own gear? Enter the motorcycle code straight away.',
      clear: 'CLEAR', tap: 'Tap to close', verifying: 'Checking code…', opened: 'Open', support: 'Support',
      okAcc: 'Take your gear and close the locker room door.', okMoto: 'Have a great ride! 🏍️',
      acc: 'Locker room', box: 'Bay {n}', zone: 'Zone {n}', closed: 'closed', open: 'open', unknown: 'unknown',
      st: { SECURED: 'Locked', WAITING_FOR_OPEN: 'Open the door', DOOR_OPEN: 'Open', CLOSED_CONFIRMATION: 'Closed', FAULT: 'Fault' },
      fa: { io_offline: 'I/O module offline', forced_open: 'door opened without a code', open_at_startup: 'door open at start-up', contact_fault: 'door contact fault', fault: 'fault' },
      et: { invalid_code: 'Invalid code', network: 'Connection error', locked: 'Code entry temporarily blocked', zone_not_configured: 'Door not configured',
        io_offline: 'Bay out of service', door_open: 'Door is open', busy: 'Bay is in use', lock_failed: 'Door did not respond', fault: 'Bay fault',
        empty_code: 'Enter a code', not_ready: 'Unit is starting', unavailable: 'Code cannot be verified',
        protocol_required: 'Sign the handover protocol first', protocol_failed: 'The protocol could not be saved' },
      es: { invalid_code: 'The code was not recognised or is no longer valid.', network: 'Connection error. Check the internet and try again.',
        zone_not_configured: 'The code is valid, but the door is not configured. Contact support: {s}.',
        io_offline: 'The bay controller is unreachable. Contact support: {s}.', door_open: 'The door is already open — close it and enter the code again.',
        fault: 'The bay reports a fault. Contact support: {s}.', unauthorized: 'The kiosk is not paired with the branch.',
        not_ready: 'The control unit is starting. Please try again in a moment.', retry: 'Please try again or contact support: {s}.', again: 'Please try again.',
        lockedMin: 'Too many invalid attempts. Try again in {m} min.', lockedLater: 'Too many invalid attempts. Try again later.',
        protocol_required: 'Your motorcycle code is valid. The bay opens once you sign the handover protocol — on this screen or in the MotoGo24 app.' },
      al: { unit: 'Control unit: ', overtime: '{z}: the door has been open too long — please close it.', fault: '{z}: {f} — contact support {s}' } },
    de: { banner: 'Steuereinheit nicht erreichbar — bitte versuchen Sie es gleich noch einmal',
      promptTitle: 'Zugangscode eingeben', hint1: 'Den Code finden Sie in der MotoGo24-App — in den Buchungsdetails und in den Nachrichten — oder in der Bestätigungs-E-Mail.',
      hint2: 'Leihen Sie Ausrüstung? Geben Sie zuerst den Umkleide-Code ein, dann den Motorrad-Code. Eigene Ausrüstung? Geben Sie direkt den Motorrad-Code ein.',
      clear: 'LÖSCHEN', tap: 'Zum Schließen tippen', verifying: 'Code wird geprüft…', opened: 'Geöffnet', support: 'Support',
      okAcc: 'Nehmen Sie Ihre Ausrüstung und schließen Sie die Umkleidetür.', okMoto: 'Gute Fahrt! 🏍️',
      acc: 'Umkleide', box: 'Box {n}', zone: 'Zone {n}', closed: 'geschlossen', open: 'offen', unknown: 'unbekannt',
      st: { SECURED: 'Verriegelt', WAITING_FOR_OPEN: 'Tür öffnen', DOOR_OPEN: 'Offen', CLOSED_CONFIRMATION: 'Geschlossen', FAULT: 'Störung' },
      fa: { io_offline: 'I/O-Modul nicht erreichbar', forced_open: 'Tür ohne Code geöffnet', open_at_startup: 'Tür beim Start offen', contact_fault: 'Türkontakt defekt', fault: 'Störung' },
      et: { invalid_code: 'Ungültiger Code', network: 'Verbindungsfehler', locked: 'Eingabe vorübergehend gesperrt', zone_not_configured: 'Tür nicht konfiguriert',
        io_offline: 'Box außer Betrieb', door_open: 'Tür ist offen', busy: 'Box wird gerade benutzt', lock_failed: 'Tür reagiert nicht', fault: 'Störung der Box',
        empty_code: 'Code eingeben', not_ready: 'Einheit startet', unavailable: 'Code kann nicht geprüft werden',
        protocol_required: 'Bitte zuerst das Übergabeprotokoll unterschreiben', protocol_failed: 'Protokoll konnte nicht gespeichert werden' },
      es: { invalid_code: 'Der Code wurde nicht erkannt oder ist nicht mehr gültig.', network: 'Verbindungsfehler. Internet prüfen und erneut versuchen.',
        zone_not_configured: 'Der Code ist gültig, aber die Tür ist nicht konfiguriert. Support kontaktieren: {s}.',
        io_offline: 'Die Steuerung der Box ist nicht erreichbar. Support kontaktieren: {s}.', door_open: 'Die Tür ist bereits offen — schließen und den Code erneut eingeben.',
        fault: 'Die Box meldet eine Störung. Support kontaktieren: {s}.', unauthorized: 'Der Kiosk ist nicht mit der Filiale gekoppelt.',
        not_ready: 'Die Steuereinheit startet gerade. Bitte gleich noch einmal versuchen.', retry: 'Bitte erneut versuchen oder Support kontaktieren: {s}.', again: 'Bitte erneut versuchen.',
        lockedMin: 'Zu viele ungültige Versuche. In {m} Min. erneut versuchen.', lockedLater: 'Zu viele ungültige Versuche. Später erneut versuchen.',
        protocol_required: 'Ihr Motorrad-Code ist gültig. Die Box öffnet sich erst nach der Unterschrift des Übergabeprotokolls — hier am Display oder in der MotoGo24-App.' },
      al: { unit: 'Steuereinheit: ', overtime: '{z}: Die Tür ist zu lange offen — bitte schließen.', fault: '{z}: {f} — Support kontaktieren {s}' } },
    es: { banner: 'Unidad de control no disponible — inténtelo de nuevo en un momento',
      promptTitle: 'Introduzca el código de acceso', hint1: 'Encontrará el código en la app MotoGo24 — en el detalle de la reserva y en los mensajes — o en el e-mail de confirmación.',
      hint2: '¿Alquila equipo? Introduzca primero el código del vestuario y después el de la moto. ¿Trae su propio equipo? Introduzca directamente el código de la moto.',
      clear: 'BORRAR', tap: 'Toque para cerrar', verifying: 'Comprobando código…', opened: 'Abierto', support: 'Soporte',
      okAcc: 'Recoja su equipo y cierre la puerta del vestuario.', okMoto: '¡Buen viaje! 🏍️',
      acc: 'Vestuario', box: 'Plaza {n}', zone: 'Zona {n}', closed: 'cerrada', open: 'abierta', unknown: 'desconocido',
      st: { SECURED: 'Cerrado', WAITING_FOR_OPEN: 'Abra la puerta', DOOR_OPEN: 'Abierto', CLOSED_CONFIRMATION: 'Cerrado', FAULT: 'Avería' },
      fa: { io_offline: 'módulo I/O sin conexión', forced_open: 'puerta abierta sin código', open_at_startup: 'puerta abierta al iniciar', contact_fault: 'fallo del contacto de puerta', fault: 'avería' },
      et: { invalid_code: 'Código no válido', network: 'Error de conexión', locked: 'Entrada bloqueada temporalmente', zone_not_configured: 'Puerta no configurada',
        io_offline: 'Plaza fuera de servicio', door_open: 'La puerta está abierta', busy: 'La plaza está en uso', lock_failed: 'La puerta no responde', fault: 'Avería de la plaza',
        empty_code: 'Introduzca el código', not_ready: 'La unidad se está iniciando', unavailable: 'No se puede verificar el código',
        protocol_required: 'Firme primero el protocolo de entrega', protocol_failed: 'No se pudo guardar el protocolo' },
      es: { invalid_code: 'El código no se reconoce o ya no es válido.', network: 'Error de conexión. Compruebe internet e inténtelo de nuevo.',
        zone_not_configured: 'El código es válido, pero la puerta no está configurada. Contacte con soporte: {s}.',
        io_offline: 'El controlador de la plaza no responde. Contacte con soporte: {s}.', door_open: 'La puerta ya está abierta — ciérrela e introduzca el código de nuevo.',
        fault: 'La plaza indica una avería. Contacte con soporte: {s}.', unauthorized: 'El kiosco no está emparejado con la sucursal.',
        not_ready: 'La unidad de control se está iniciando. Inténtelo en un momento.', retry: 'Inténtelo de nuevo o contacte con soporte: {s}.', again: 'Inténtelo de nuevo.',
        lockedMin: 'Demasiados intentos no válidos. Inténtelo en {m} min.', lockedLater: 'Demasiados intentos no válidos. Inténtelo más tarde.',
        protocol_required: 'Su código de la moto es válido. La plaza se abrirá cuando firme el protocolo de entrega — en esta pantalla o en la app MotoGo24.' },
      al: { unit: 'Unidad de control: ', overtime: '{z}: la puerta lleva demasiado tiempo abierta — ciérrela, por favor.', fault: '{z}: {f} — contacte con soporte {s}' } },
    fr: { banner: 'Unité de commande indisponible — réessayez dans un instant',
      promptTitle: 'Saisissez votre code d’accès', hint1: 'Le code se trouve dans l’application MotoGo24 — dans le détail de la réservation et dans les messages — ou dans l’e-mail de confirmation.',
      hint2: 'Vous louez un équipement ? Saisissez d’abord le code du vestiaire, puis le code moto. Équipement personnel ? Saisissez directement le code moto.',
      clear: 'EFFACER', tap: 'Touchez pour fermer', verifying: 'Vérification du code…', opened: 'Ouvert', support: 'Assistance',
      okAcc: 'Prenez votre équipement et fermez la porte du vestiaire.', okMoto: 'Bonne route ! 🏍️',
      acc: 'Vestiaire', box: 'Box {n}', zone: 'Zone {n}', closed: 'fermée', open: 'ouverte', unknown: 'inconnu',
      st: { SECURED: 'Verrouillé', WAITING_FOR_OPEN: 'Ouvrez la porte', DOOR_OPEN: 'Ouvert', CLOSED_CONFIRMATION: 'Fermé', FAULT: 'Panne' },
      fa: { io_offline: 'module E/S hors ligne', forced_open: 'porte ouverte sans code', open_at_startup: 'porte ouverte au démarrage', contact_fault: 'contact de porte défectueux', fault: 'panne' },
      et: { invalid_code: 'Code invalide', network: 'Erreur de connexion', locked: 'Saisie temporairement bloquée', zone_not_configured: 'Porte non configurée',
        io_offline: 'Box hors service', door_open: 'La porte est ouverte', busy: 'Le box est en cours d’utilisation', lock_failed: 'La porte ne répond pas', fault: 'Panne du box',
        empty_code: 'Saisissez un code', not_ready: 'Unité en cours de démarrage', unavailable: 'Impossible de vérifier le code',
        protocol_required: 'Signez d’abord le protocole de remise', protocol_failed: 'Le protocole n’a pas pu être enregistré' },
      es: { invalid_code: 'Le code n’a pas été reconnu ou n’est plus valide.', network: 'Erreur de connexion. Vérifiez internet et réessayez.',
        zone_not_configured: 'Le code est valide, mais la porte n’est pas configurée. Contactez l’assistance : {s}.',
        io_offline: 'Le contrôleur du box est injoignable. Contactez l’assistance : {s}.', door_open: 'La porte est déjà ouverte — fermez-la et saisissez le code à nouveau.',
        fault: 'Le box signale une panne. Contactez l’assistance : {s}.', unauthorized: 'Le kiosque n’est pas associé à l’agence.',
        not_ready: 'L’unité de commande démarre. Réessayez dans un instant.', retry: 'Réessayez ou contactez l’assistance : {s}.', again: 'Veuillez réessayer.',
        lockedMin: 'Trop de tentatives invalides. Réessayez dans {m} min.', lockedLater: 'Trop de tentatives invalides. Réessayez plus tard.',
        protocol_required: 'Votre code moto est valide. Le box s’ouvrira après la signature du protocole de remise — sur cet écran ou dans l’application MotoGo24.' },
      al: { unit: 'Unité de commande : ', overtime: '{z} : la porte est ouverte depuis trop longtemps — veuillez la fermer.', fault: '{z} : {f} — contactez l’assistance {s}' } },
    nl: { banner: 'Besturingseenheid niet bereikbaar — probeer het zo opnieuw',
      promptTitle: 'Voer uw toegangscode in', hint1: 'De code vindt u in de MotoGo24-app — bij de reserveringsdetails en in de berichten — of in de bevestigingsmail.',
      hint2: 'Huurt u uitrusting? Voer eerst de kleedkamercode in en daarna de motorcode. Eigen uitrusting? Voer meteen de motorcode in.',
      clear: 'WISSEN', tap: 'Tik om te sluiten', verifying: 'Code controleren…', opened: 'Geopend', support: 'Support',
      okAcc: 'Pak uw uitrusting en sluit de deur van de kleedkamer.', okMoto: 'Goede rit! 🏍️',
      acc: 'Kleedkamer', box: 'Box {n}', zone: 'Zone {n}', closed: 'dicht', open: 'open', unknown: 'onbekend',
      st: { SECURED: 'Vergrendeld', WAITING_FOR_OPEN: 'Open de deur', DOOR_OPEN: 'Open', CLOSED_CONFIRMATION: 'Gesloten', FAULT: 'Storing' },
      fa: { io_offline: 'I/O-module offline', forced_open: 'deur zonder code geopend', open_at_startup: 'deur open bij opstarten', contact_fault: 'deurcontact defect', fault: 'storing' },
      et: { invalid_code: 'Ongeldige code', network: 'Verbindingsfout', locked: 'Invoer tijdelijk geblokkeerd', zone_not_configured: 'Deur niet geconfigureerd',
        io_offline: 'Box buiten gebruik', door_open: 'Deur staat open', busy: 'Box is in gebruik', lock_failed: 'Deur reageert niet', fault: 'Storing van de box',
        empty_code: 'Voer een code in', not_ready: 'Eenheid start op', unavailable: 'Code kan niet worden gecontroleerd',
        protocol_required: 'Onderteken eerst het overdrachtsprotocol', protocol_failed: 'Protocol kon niet worden opgeslagen' },
      es: { invalid_code: 'De code is niet herkend of niet meer geldig.', network: 'Verbindingsfout. Controleer internet en probeer opnieuw.',
        zone_not_configured: 'De code is geldig, maar de deur is niet geconfigureerd. Neem contact op met support: {s}.',
        io_offline: 'De besturing van de box is niet bereikbaar. Neem contact op met support: {s}.', door_open: 'De deur staat al open — sluit hem en voer de code opnieuw in.',
        fault: 'De box meldt een storing. Neem contact op met support: {s}.', unauthorized: 'De kiosk is niet gekoppeld aan het filiaal.',
        not_ready: 'De besturingseenheid start op. Probeer het zo opnieuw.', retry: 'Probeer opnieuw of neem contact op met support: {s}.', again: 'Probeer het opnieuw.',
        lockedMin: 'Te veel ongeldige pogingen. Probeer over {m} min. opnieuw.', lockedLater: 'Te veel ongeldige pogingen. Probeer het later opnieuw.',
        protocol_required: 'Uw motorcode is geldig. De box gaat open zodra u het overdrachtsprotocol ondertekent — op dit scherm of in de MotoGo24-app.' },
      al: { unit: 'Besturingseenheid: ', overtime: '{z}: de deur staat te lang open — sluit hem a.u.b.', fault: '{z}: {f} — neem contact op met support {s}' } },
    pl: { banner: 'Jednostka sterująca niedostępna — spróbuj ponownie za chwilę',
      promptTitle: 'Wpisz kod dostępu', hint1: 'Kod znajdziesz w aplikacji MotoGo24 — w szczegółach rezerwacji i w wiadomościach — lub w e-mailu potwierdzającym.',
      hint2: 'Wypożyczasz wyposażenie? Wpisz najpierw kod do szatni, potem kod do motocykla. Masz własne wyposażenie? Wpisz od razu kod do motocykla.',
      clear: 'USUŃ', tap: 'Dotknij, aby zamknąć', verifying: 'Sprawdzam kod…', opened: 'Otwarte', support: 'Wsparcie',
      okAcc: 'Weź swoje wyposażenie i zamknij drzwi szatni.', okMoto: 'Miłej jazdy! 🏍️',
      acc: 'Szatnia', box: 'Boks {n}', zone: 'Strefa {n}', closed: 'zamknięte', open: 'otwarte', unknown: 'nieznane',
      st: { SECURED: 'Zamknięte', WAITING_FOR_OPEN: 'Otwórz drzwi', DOOR_OPEN: 'Otwarte', CLOSED_CONFIRMATION: 'Zamknięto', FAULT: 'Awaria' },
      fa: { io_offline: 'moduł I/O niedostępny', forced_open: 'drzwi otwarte bez kodu', open_at_startup: 'drzwi otwarte przy starcie', contact_fault: 'awaria czujnika drzwi', fault: 'awaria' },
      et: { invalid_code: 'Nieprawidłowy kod', network: 'Błąd połączenia', locked: 'Wpisywanie tymczasowo zablokowane', zone_not_configured: 'Drzwi nieskonfigurowane',
        io_offline: 'Boks wyłączony z użytku', door_open: 'Drzwi są otwarte', busy: 'Boks jest w użyciu', lock_failed: 'Drzwi nie odpowiadają', fault: 'Awaria boksu',
        empty_code: 'Wpisz kod', not_ready: 'Jednostka się uruchamia', unavailable: 'Nie można zweryfikować kodu',
        protocol_required: 'Najpierw podpisz protokół przekazania', protocol_failed: 'Nie udało się zapisać protokołu' },
      es: { invalid_code: 'Kod nie został rozpoznany lub jest już nieważny.', network: 'Błąd połączenia. Sprawdź internet i spróbuj ponownie.',
        zone_not_configured: 'Kod jest ważny, ale drzwi nie są skonfigurowane. Skontaktuj się ze wsparciem: {s}.',
        io_offline: 'Sterownik boksu jest niedostępny. Skontaktuj się ze wsparciem: {s}.', door_open: 'Drzwi są już otwarte — zamknij je i wpisz kod ponownie.',
        fault: 'Boks zgłasza awarię. Skontaktuj się ze wsparciem: {s}.', unauthorized: 'Kiosk nie jest sparowany z oddziałem.',
        not_ready: 'Jednostka sterująca się uruchamia. Spróbuj ponownie za chwilę.', retry: 'Spróbuj ponownie lub skontaktuj się ze wsparciem: {s}.', again: 'Spróbuj ponownie.',
        lockedMin: 'Zbyt wiele nieprawidłowych prób. Spróbuj ponownie za {m} min.', lockedLater: 'Zbyt wiele nieprawidłowych prób. Spróbuj później.',
        protocol_required: 'Kod do motocykla jest prawidłowy. Boks otworzy się po podpisaniu protokołu przekazania — na tym ekranie lub w aplikacji MotoGo24.' },
      al: { unit: 'Jednostka sterująca: ', overtime: '{z}: drzwi są otwarte zbyt długo — proszę je zamknąć.', fault: '{z}: {f} — skontaktuj się ze wsparciem {s}' } },
    uk: { banner: 'Блок керування недоступний — спробуйте ще раз за хвилину',
      promptTitle: 'Введіть код доступу', hint1: 'Код є в застосунку MotoGo24 — у деталях бронювання та в повідомленнях — або в підтверджувальному e-mail.',
      hint2: 'Берете екіпірування? Спочатку введіть код роздягальні, потім код мотоцикла. Маєте власне екіпірування? Одразу введіть код мотоцикла.',
      clear: 'СТЕРТИ', tap: 'Торкніться, щоб закрити', verifying: 'Перевіряю код…', opened: 'Відкрито', support: 'Підтримка',
      okAcc: 'Візьміть екіпірування та зачиніть двері роздягальні.', okMoto: 'Гарної дороги! 🏍️',
      acc: 'Роздягальня', box: 'Бокс {n}', zone: 'Зона {n}', closed: 'зачинено', open: 'відчинено', unknown: 'невідомо',
      st: { SECURED: 'Замкнено', WAITING_FOR_OPEN: 'Відчиніть двері', DOOR_OPEN: 'Відкрито', CLOSED_CONFIRMATION: 'Зачинено', FAULT: 'Несправність' },
      fa: { io_offline: 'модуль вводу/виводу недоступний', forced_open: 'двері відчинено без коду', open_at_startup: 'двері відчинені під час запуску', contact_fault: 'несправність дверного контакту', fault: 'несправність' },
      et: { invalid_code: 'Невірний код', network: 'Помилка з’єднання', locked: 'Введення тимчасово заблоковано', zone_not_configured: 'Двері не налаштовано',
        io_offline: 'Бокс не працює', door_open: 'Двері відчинені', busy: 'Бокс зараз використовується', lock_failed: 'Двері не відповідають', fault: 'Несправність боксу',
        empty_code: 'Введіть код', not_ready: 'Блок запускається', unavailable: 'Не вдалося перевірити код',
        protocol_required: 'Спочатку підпишіть протокол передачі', protocol_failed: 'Не вдалося зберегти протокол' },
      es: { invalid_code: 'Код не розпізнано або він уже недійсний.', network: 'Помилка з’єднання. Перевірте інтернет і спробуйте ще раз.',
        zone_not_configured: 'Код дійсний, але двері не налаштовано. Зверніться до підтримки: {s}.',
        io_offline: 'Контролер боксу недоступний. Зверніться до підтримки: {s}.', door_open: 'Двері вже відчинені — зачиніть їх і введіть код ще раз.',
        fault: 'Бокс повідомляє про несправність. Зверніться до підтримки: {s}.', unauthorized: 'Кіоск не пов’язано з філією.',
        not_ready: 'Блок керування запускається. Спробуйте за хвилину.', retry: 'Спробуйте ще раз або зверніться до підтримки: {s}.', again: 'Спробуйте ще раз.',
        lockedMin: 'Забагато невірних спроб. Спробуйте через {m} хв.', lockedLater: 'Забагато невірних спроб. Спробуйте пізніше.',
        protocol_required: 'Код мотоцикла дійсний. Бокс відкриється після підписання протоколу передачі — на цьому екрані або в застосунку MotoGo24.' },
      al: { unit: 'Блок керування: ', overtime: '{z}: двері відчинені надто довго — будь ласка, зачиніть їх.', fault: '{z}: {f} — зверніться до підтримки {s}' } },
  };

  /** Je `label` jen automaticky složený český název, ne vlastní popis od obsluhy?
      Jednotka posílá `label` už složený (kontrakt §14) a Velín historicky zakládal dveřím popisy
      „Garáž #3 — Honda CB500“ a „Skříň oblečení“ — ty by na displeji zůstaly česky ve všech jazycích
      a neodpovídaly by jednotnému názvosloví (kóje 1–7 / šatna / venek). Takové názvy tedy přeložíme
      z `kind` a `box_number`; cokoli jiného je vlastní popis a zobrazí se přesně tak, jak byl zadán. */
  function isGeneratedLabel(label, z) {
    const text = String(label || '').trim();
    if (!text) return true;
    if (z && z.kind === 'accessories') {
      return ['Šatna', 'Satna', 'Oblečení', 'Obleceni', 'Skříň oblečení', 'Skrin obleceni'].indexOf(text) !== -1;
    }
    if (text === 'Zóna ' + (z && z.zone)) return true;
    const box = z && z.box_number != null ? z.box_number : null;
    if (box == null) return false;
    // „Kóje 3“ / „Koje 3“ / „Garáž #3“ / „Garáž 3“ — volitelně s doplňkem za pomlčkou (model motorky)
    const re = new RegExp('^(?:K[óo]je|Gar[áa][žz])\\s*#?\\s*' + box + '(?:\\s*[—–-]\\s*.*)?$', 'i');
    return re.test(text);
  }

  const SIGNAL = { red: 'červená', green: 'zelená', green_pulse: 'zelená (pulzuje)', red_blink: 'červená (bliká)', both_blink: 'červená/zelená', off: 'vypnuto' };
  let lang = DEFAULT;
  const listeners = [];
  const D = () => S[lang] || S[DEFAULT];
  const fmt = (text, vars) => String(text || '').replace(/\{(\w+)\}/g, (m, k) => (vars && vars[k] != null ? vars[k] : m));
  const sub = (group, key) => { const g = D()[group] || {}; return g[key] != null ? g[key] : (S[DEFAULT][group] || {})[key]; };
  /** Text podle klíče; „skupina.klíč“ (např. `ho.title`, `g.helmet`) sáhne do skupiny — i pro data-i18n v HTML. */
  const t = (key, vars) => {
    const dot = String(key).indexOf('.');
    const raw = dot > 0 ? sub(key.slice(0, dot), key.slice(dot + 1)) : (D()[key] != null ? D()[key] : S[DEFAULT][key]);
    return fmt(raw != null ? raw : key, Object.assign({ s: SUPPORT }, vars || {}));
  };
  /** Doplnění slovníků z dalšího modulu (i18n-handover.js): `{cs: {ho: {…}, g: {…}}, en: …}` — skupiny se slučují. */
  function extend(dict) {
    Object.keys(dict || {}).forEach((code) => {
      if (!S[code]) return;
      Object.keys(dict[code]).forEach((k) => {
        const v = dict[code][k];
        if (v && typeof v === 'object') S[code][k] = Object.assign(S[code][k] || {}, v); else S[code][k] = v;
      });
    });
  }

  function setLang(code, silent) {
    if (!S[code]) code = DEFAULT;
    if (code === lang && !silent) return;
    lang = code;
    document.documentElement.lang = code;
    // Změna `lang` je přesně to, co prohlížeči nabídne překlad stránky. Kiosk má vlastní překlady
    // (lišta jazyků nahoře), takže překladač musí zůstat vypnutý — atribut jistíme při každém přepnutí.
    document.documentElement.setAttribute('translate', 'no');
    document.documentElement.classList.add('notranslate');
    applyStatic();
    if (!silent) listeners.forEach((fn) => { try { fn(code); } catch (e) { /* noop */ } });
  }
  /** Statické texty: prvky s data-i18n="klíč" (textContent). */
  function applyStatic() {
    document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.getAttribute('data-i18n')); });
    document.querySelectorAll('.lang-btn').forEach((b) => b.classList.toggle('on', b.dataset.lang === lang));
  }
  /** Lišta jazyků (vlajka + kód) do kontejneru; klik = přepnutí. */
  function renderBar(container) {
    container.textContent = '';
    LANGS.forEach(([code, flag, label]) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'lang-btn' + (code === lang ? ' on' : '');
      b.dataset.lang = code;
      b.innerHTML = '<span class="lang-flag"></span><span class="lang-code"></span>';
      b.querySelector('.lang-flag').textContent = flag;
      b.querySelector('.lang-code').textContent = label;
      b.addEventListener('click', (e) => { e.preventDefault(); setLang(code); });
      container.appendChild(b);
    });
  }
  function lockedSubtitle(lockedUntil) {
    const min = lockedUntil ? Math.max(1, Math.ceil((Number(lockedUntil) - Date.now() / 1000) / 60)) : null;
    return (min ? fmt(sub('es', 'lockedMin'), { m: min }) : sub('es', 'lockedLater')) + '\n' + t('support') + ': ' + SUPPORT;
  }
  return {
    SUPPORT, LANGS, DEFAULT, t, setLang, renderBar, applyStatic, extend,
    g: (group, key, vars) => fmt(sub(group, key) || '', Object.assign({ s: SUPPORT }, vars || {})),
    get lang() { return lang; },
    onChange: (fn) => listeners.push(fn),
    RETRY: () => fmt(sub('es', 'retry'), { s: SUPPORT }),
    zoneState: (s) => sub('st', s) || s || '—',
    fault: (f) => sub('fa', f) || f || '',
    door: (c) => t(c === true ? 'closed' : c === false ? 'open' : 'unknown'),
    /** Signalizace zóny pro servisní panel (technik, česky) — panel.js volá MG.i18n.signal(z.signal). */
    signal: (s) => SIGNAL[String(s || '').toLowerCase()] || s || '—',
    /** Název zóny na displeji. Jednotka posílá `label` už složený (kontrakt §14) a vždy česky, takže
        by v cizím jazyce zůstala česká „Kóje 3" / „Šatna". Když se `label` rovná názvu, který si jednotka
        složila sama (viz Zone.display_name v models.py — včetně starších „Oblečení"), přeložíme ho z `kind`
        a `box_number`; vlastní popis dveří z Velína se naopak nepřekládá a zobrazí se přesně tak, jak ho zadal. */
    isGenerated: isGeneratedLabel,
    zoneName: (z) => {
      const n = z.box_number != null ? z.box_number : z.zone;
      const custom = z.label && !isGeneratedLabel(z.label, z) ? z.label : '';
      return custom || (z.kind === 'accessories' ? t('acc') : t('box', { n: n }));
    },
    errorTitle: (e) => sub('et', e === 'unauthorized' || e === 'branch_not_found' ? 'invalid_code' : e) || sub('et', 'unavailable'),
    errorSubtitle: (e, lockedUntil) => {
      if (e === 'locked') return lockedSubtitle(lockedUntil);
      const key = e === 'busy' ? 'door_open' : e === 'lock_failed' ? 'retry' : e === 'branch_not_found' ? 'unauthorized' : e;
      return fmt(sub('es', key) || sub('es', 'again'), { s: SUPPORT });
    },
    successSubtitle: (kind, name) => (kind === 'accessories' ? name + '\n\n' + t('okAcc') : kind === 'motorcycle' ? name + '\n\n' + t('okMoto') : name),
    alert: (key, vars) => fmt(sub('al', key), Object.assign({ s: SUPPORT }, vars || {})),
  };
})();
