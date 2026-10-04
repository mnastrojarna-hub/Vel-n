/* MotoGo24 kiosk — výzva „nejdřív kód šatny“ (handover_locker.py, chyba `locker_first`, zadání majitele 2026-09-29)
   + skupina `lk` = číslo dveří šatny (zadání majitele 2026-10-04: na dveřích jsou jen čísla, šatna = dveře č. 8 —
   po kódu šatny displej říká „Šatna otevřena — dveře č. N“, N = číslo zóny šatny z HW mapy, viz MG.i18n.doorNo).
   Stejných 8 jazyků jako i18n.js; slučuje se přes MG.i18n.extend() do skupin `et` (titulek), `es` (podtitulek) a `lk`. */
'use strict';
window.MG = window.MG || {};

MG.i18n.extend({
  cs: { et: { locker_first: 'Nejdřív zadejte kód šatny' },
    es: { locker_first: 'K rezervaci máte výbavu v šatně. Zadejte nejdřív kód šatny, vezměte si výbavu a zavřete dveře — pak zadejte kód motorky. Kód šatny najdete v aplikaci MotoGo24, v e-mailu nebo v SMS. Výbavu nechcete? Zadejte kód motorky znovu.' } },
  en: { et: { locker_first: 'Enter the locker room code first' },
    es: { locker_first: 'Your booking includes gear in the locker room. Enter the locker room code first, take your gear and close the door — then enter the motorcycle code. You will find the locker room code in the MotoGo24 app, in the e-mail or in the SMS. Don’t want the gear? Enter the motorcycle code again.' } },
  de: { et: { locker_first: 'Zuerst den Umkleide-Code eingeben' },
    es: { locker_first: 'Zu Ihrer Buchung gehört Ausrüstung in der Umkleide. Geben Sie zuerst den Umkleide-Code ein, nehmen Sie die Ausrüstung und schließen Sie die Tür — danach den Motorrad-Code. Den Umkleide-Code finden Sie in der MotoGo24-App, in der E-Mail oder in der SMS. Keine Ausrüstung gewünscht? Geben Sie den Motorrad-Code erneut ein.' } },
  es: { et: { locker_first: 'Introduzca primero el código del vestuario' },
    es: { locker_first: 'Su reserva incluye equipo en el vestuario. Introduzca primero el código del vestuario, recoja el equipo y cierre la puerta — después, el código de la moto. Encontrará el código del vestuario en la app MotoGo24, en el e-mail o en el SMS. ¿No quiere el equipo? Introduzca de nuevo el código de la moto.' } },
  fr: { et: { locker_first: 'Saisissez d’abord le code du vestiaire' },
    es: { locker_first: 'Votre réservation comprend un équipement au vestiaire. Saisissez d’abord le code du vestiaire, prenez l’équipement et fermez la porte — puis saisissez le code moto. Le code du vestiaire se trouve dans l’application MotoGo24, dans l’e-mail ou dans le SMS. Vous ne voulez pas l’équipement ? Saisissez à nouveau le code moto.' } },
  nl: { et: { locker_first: 'Voer eerst de kleedkamercode in' },
    es: { locker_first: 'Bij uw reservering hoort uitrusting in de kleedkamer. Voer eerst de kleedkamercode in, pak de uitrusting en sluit de deur — voer daarna de motorcode in. De kleedkamercode vindt u in de MotoGo24-app, in de e-mail of in de sms. Wilt u de uitrusting niet? Voer de motorcode opnieuw in.' } },
  pl: { et: { locker_first: 'Najpierw wpisz kod do szatni' },
    es: { locker_first: 'Do Twojej rezerwacji należy wyposażenie w szatni. Najpierw wpisz kod do szatni, weź wyposażenie i zamknij drzwi — potem wpisz kod do motocykla. Kod do szatni znajdziesz w aplikacji MotoGo24, w e-mailu lub w SMS-ie. Nie chcesz wyposażenia? Wpisz kod do motocykla ponownie.' } },
  uk: { et: { locker_first: 'Спочатку введіть код роздягальні' },
    es: { locker_first: 'До вашого бронювання входить екіпірування в роздягальні. Спочатку введіть код роздягальні, візьміть екіпірування та зачиніть двері — потім введіть код мотоцикла. Код роздягальні є в застосунку MotoGo24, в e-mail або в SMS. Не потрібне екіпірування? Введіть код мотоцикла ще раз.' } },
});

/* Číslo dveří šatny — `lk.opened` titulek / `lk.go` podtitulek po kódu šatny, `lk.close` modální hláška #wardrobe. */
MG.i18n.extend({
  cs: { lk: { opened: 'Šatna otevřena — dveře č. {n}', go: 'Běžte ke dveřím č. {n} a vemte za kliku.',
    close: 'Šatna — dveře č. {n}: vezměte si výbavu a zavřete dveře' } },
  en: { lk: { opened: 'Locker room open — door no. {n}', go: 'Go to door no. {n} and pull the handle.',
    close: 'Locker room — door no. {n}: take your gear and close the door' } },
  de: { lk: { opened: 'Umkleide offen — Tür Nr. {n}', go: 'Gehen Sie zu Tür Nr. {n} und ziehen Sie am Griff.',
    close: 'Umkleide — Tür Nr. {n}: Ausrüstung nehmen und Tür schließen' } },
  es: { lk: { opened: 'Vestuario abierto — puerta n.º {n}', go: 'Vaya a la puerta n.º {n} y tire de la manija.',
    close: 'Vestuario — puerta n.º {n}: recoja su equipo y cierre la puerta' } },
  fr: { lk: { opened: 'Vestiaire ouvert — porte n° {n}', go: 'Allez à la porte n° {n} et tirez la poignée.',
    close: 'Vestiaire — porte n° {n} : prenez votre équipement et fermez la porte' } },
  nl: { lk: { opened: 'Kleedkamer open — deur nr. {n}', go: 'Ga naar deur nr. {n} en trek aan de klink.',
    close: 'Kleedkamer — deur nr. {n}: pak uw uitrusting en sluit de deur' } },
  pl: { lk: { opened: 'Szatnia otwarta — drzwi nr {n}', go: 'Podejdź do drzwi nr {n} i pociągnij za klamkę.',
    close: 'Szatnia — drzwi nr {n}: weź wyposażenie i zamknij drzwi' } },
  uk: { lk: { opened: 'Роздягальню відчинено — двері № {n}', go: 'Підійдіть до дверей № {n} і потягніть за ручку.',
    close: 'Роздягальня — двері № {n}: візьміть екіпірування та зачиніть двері' } },
});
