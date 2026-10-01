/* MotoGo24 kiosk — výdej až od 12:00 (pickup_gate.py, chyba `pickup_too_early`, rozhodnutí majitele 2026-10-01, CONTRACT §31).
   Rezervace se slevou 50 % na 1. den za vyzvednutí od 12:00 se vydává (šatna i motorka) až od `release_at`.
   Stejných 8 jazyků jako i18n.js; přes MG.i18n.extend() do `et` (titulek), `es` (text se slotem {w}) a `pk` (slot: dnes / den / obecně).
   MG.i18n.pickup(releaseAt) skládá titulek + text; čas i „dnes“ VŽDY v Europe/Prague (displej může mít jinou zónu). */
'use strict';
window.MG = window.MG || {};

MG.i18n.extend({
  cs: { et: { pickup_too_early: 'Vyzvednutí až od 12:00' },
    es: { pickup_too_early: 'Vaše rezervace má slevu 50 % na 1. den za vyzvednutí od 12:00, proto vám motorku i šatnu vydáme {w}. Potřebujete ji dřív? V aplikaci MotoGo24 nebo na motogo24.cz/upravit-rezervaci změňte čas vyzvednutí na dřívější — sleva zanikne, rozdíl doplatíte a kód bude platit hned.' },
    pk: { today: 'dnes od {t} (za {m} min)', day: '{d} od {t}', any: 'až od 12:00 v den začátku pronájmu' } },
  en: { et: { pickup_too_early: 'Pickup from 12:00 only' },
    es: { pickup_too_early: 'Your booking has a 50 % discount on day 1 for pickup from 12:00, so we will release the motorcycle and the locker room to you {w}. Need it earlier? In the MotoGo24 app or at motogo24.cz/upravit-rezervaci, change the pickup time to an earlier one — the discount will be cancelled, you pay the difference and the code will work immediately.' },
    pk: { today: 'today from {t} (in {m} min)', day: 'on {d} from {t}', any: 'from 12:00 on the first day of the rental' } },
  de: { et: { pickup_too_early: 'Abholung erst ab 12:00' },
    es: { pickup_too_early: 'Ihre Buchung hat 50 % Rabatt auf den 1. Tag für die Abholung ab 12:00, daher geben wir Ihnen das Motorrad und die Umkleide {w} frei. Sie brauchen es früher? Ändern Sie in der MotoGo24-App oder auf motogo24.cz/upravit-rezervaci die Abholzeit auf eine frühere — der Rabatt entfällt, Sie zahlen die Differenz und der Code gilt sofort.' },
    pk: { today: 'heute ab {t} (in {m} Min.)', day: 'am {d} ab {t}', any: 'erst ab 12:00 am ersten Miettag' } },
  es: { et: { pickup_too_early: 'Recogida solo a partir de las 12:00' },
    es: { pickup_too_early: 'Su reserva tiene un 50 % de descuento en el 1.er día por recoger a partir de las 12:00, por eso le entregaremos la moto y el vestuario {w}. ¿La necesita antes? En la app MotoGo24 o en motogo24.cz/upravit-rezervaci cambie la hora de recogida a una anterior: el descuento se anulará, pagará la diferencia y el código funcionará de inmediato.' },
    pk: { today: 'hoy a partir de las {t} (dentro de {m} min)', day: 'el {d} a partir de las {t}', any: 'a partir de las 12:00 del primer día del alquiler' } },
  fr: { et: { pickup_too_early: 'Retrait à partir de 12:00 uniquement' },
    es: { pickup_too_early: 'Votre réservation bénéficie de 50 % de réduction sur le 1er jour pour un retrait à partir de 12:00, c’est pourquoi nous vous remettrons la moto et le vestiaire {w}. Vous en avez besoin plus tôt ? Dans l’application MotoGo24 ou sur motogo24.cz/upravit-rezervaci, choisissez une heure de retrait plus tôt — la réduction sera annulée, vous paierez la différence et le code fonctionnera immédiatement.' },
    pk: { today: 'aujourd’hui à partir de {t} (dans {m} min)', day: 'le {d} à partir de {t}', any: 'à partir de 12:00 le premier jour de la location' } },
  nl: { et: { pickup_too_early: 'Ophalen pas vanaf 12:00' },
    es: { pickup_too_early: 'Uw reservering heeft 50 % korting op de 1e dag voor ophalen vanaf 12:00, daarom geven wij u de motor en de kleedkamer {w} vrij. Heeft u hem eerder nodig? Wijzig in de MotoGo24-app of op motogo24.cz/upravit-rezervaci de ophaaltijd naar een eerder tijdstip — de korting vervalt, u betaalt het verschil bij en de code werkt meteen.' },
    pk: { today: 'vandaag vanaf {t} (over {m} min.)', day: 'op {d} vanaf {t}', any: 'pas vanaf 12:00 op de eerste huurdag' } },
  pl: { et: { pickup_too_early: 'Odbiór dopiero od 12:00' },
    es: { pickup_too_early: 'Twoja rezerwacja ma 50 % zniżki na 1. dzień za odbiór od 12:00, dlatego motocykl i szatnię wydamy Ci {w}. Potrzebujesz wcześniej? W aplikacji MotoGo24 lub na motogo24.cz/upravit-rezervaci zmień godzinę odbioru na wcześniejszą — zniżka przepadnie, dopłacisz różnicę, a kod zadziała od razu.' },
    pk: { today: 'dziś od {t} (za {m} min)', day: '{d} od {t}', any: 'dopiero od 12:00 w pierwszym dniu wynajmu' } },
  uk: { et: { pickup_too_early: 'Отримання лише з 12:00' },
    es: { pickup_too_early: 'Ваше бронювання має знижку 50 % на 1-й день за отримання з 12:00, тому мотоцикл і роздягальню ми видамо вам {w}. Потрібно раніше? У застосунку MotoGo24 або на motogo24.cz/upravit-rezervaci змініть час отримання на раніший — знижка зникне, ви доплатите різницю, і код запрацює одразу.' },
    pk: { today: 'сьогодні з {t} (через {m} хв)', day: '{d} з {t}', any: 'лише з 12:00 у перший день оренди' } },
});

(function () {
  const TZ = 'Europe/Prague';
  const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' };
  const DAY = { year: 'numeric', month: '2-digit', day: '2-digit' };
  function fmt(date, opts, locale) {
    try { return new Intl.DateTimeFormat(locale || 'en-GB', Object.assign({ timeZone: TZ }, opts)).format(date); }
    catch (e) { return null; }
  }
  /** `{title, body}` hlášky `pickup_too_early`: dnes → „dnes od {t} (za {m} min)“, jiný den → „{d} od {t}“,
      bez platného `release_at` → obecné „od 12:00 v den začátku“. `nowMs` jen pro testy / náhledy. */
  function pickup(releaseAt, nowMs) {
    const ms = Date.parse(releaseAt || '');
    const now = nowMs != null ? Number(nowMs) : Date.now();
    let w;
    if (!isFinite(ms)) w = MG.i18n.g('pk', 'any');
    else {
      const at = new Date(ms);
      const t = fmt(at, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }) || '12:00';
      if (fmt(at, DAY, 'en-CA') === fmt(new Date(now), DAY, 'en-CA')) {
        w = MG.i18n.g('pk', 'today', { t: t, m: Math.max(1, Math.ceil((ms - now) / 60000)) });
      } else {
        const d = fmt(at, { day: 'numeric', month: 'numeric', year: 'numeric' }, LOCALE[MG.i18n.lang] || 'cs-CZ') || '';
        w = MG.i18n.g('pk', 'day', { t: t, d: d });
      }
    }
    return { title: MG.i18n.errorTitle('pickup_too_early'), body: MG.i18n.g('es', 'pickup_too_early', { w: w }) };
  }
  MG.i18n.pickup = pickup;
  // Obecné cesty (odometer.js, diag.js …) volají errorSubtitle(e, locked_until) — u `pickup_too_early` je 2. argument
  // `release_at` (nebo nic → obecné znění), aby se nikdy neukázal surový slot {w}.
  const baseSubtitle = MG.i18n.errorSubtitle;
  MG.i18n.errorSubtitle = (e, arg) => (e === 'pickup_too_early' ? pickup(arg).body : baseSubtitle(e, arg));
})();
