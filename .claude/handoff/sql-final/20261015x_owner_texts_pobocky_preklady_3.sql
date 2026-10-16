-- =============================================================================
-- 20261015x_owner_texts_pobocky_preklady_3.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 3/7).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- Appka (obrazovka Pobočky, oba stromy) bere texty z cms_variables web.pobocky.* a bez překladu ukazuje
-- ve všech jazycích ČEŠTINU – včetně postupu samoobslužného převzetí ve Velkých Němčicích. Web cizí
-- jazyky bere z lang/v2/<jazyk>/pobocky.php; tytéž texty se sem doplní jako překlady (web se tím
-- nezmění, appka dostane 7 jazyků). Doplňuje jen chybějící překlad a jen když česká hodnota je přesně
-- ta, ze které lang/v2 vychází (data/pobocky.php).
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_cs text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: klíč, jazyk ('cs' = sloupec value, jinak translations.<jazyk>.value), how + old:
  --      'full'   = celý živý text má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --      'phrase' = věta old (v živém textu jednou) se nahradí new, zbytek textu zůstává
  --      'fill'   = překlad chybí → doplní se
  -- g: brána – překlad se mění jen když česká hodnota má otisk md5 = gate (nové / ověřené české znění)
  FOR f IN
    SELECT x.*, g.gate FROM (VALUES
    ('web.pobocky.branches.1.badge', 'pl', 'fill', NULL, $t$Oddział samoobsługowy$t$),
    ('web.pobocky.branches.1.badge', 'uk', 'fill', NULL, $t$Філія самообслуговування$t$),
    ('web.pobocky.branches.1.hours', 'en', 'fill', NULL, $t$Open 24/7 with the app code. You choose the pick-up time in your booking: if you pick up from 12:00 (rental of 2+ days), the 1st day is half price and the kiosk releases the bike from 12:00. You don't choose a return time: return the bike any time on the last day of the rental, by 24:00.$t$),
    ('web.pobocky.branches.1.hours', 'de', 'fill', NULL, $t$Rund um die Uhr (24/7) per Code aus der App. Die Abholzeit wählst du bei der Reservierung: Bei Abholung ab 12:00 Uhr (Miete ab 2 Tagen) zahlst du für den 1. Tag nur die Hälfte, und der Kiosk gibt dir das Motorrad erst ab 12:00 Uhr heraus. Die Rückgabezeit wählst du nicht: Du gibst das Motorrad am letzten Miettag jederzeit bis 24:00 Uhr zurück.$t$),
    ('web.pobocky.branches.1.hours', 'es', 'fill', NULL, $t$Abierta 24/7 con el código de la app. La hora de recogida la eliges en la reserva: si recoges a partir de las 12:00 (alquiler de 2 días o más), el 1.er día te sale a mitad de precio y el quiosco te entrega la moto a partir de las 12:00. La hora de devolución no se elige: devuelves la moto cuando quieras el último día del alquiler, hasta las 24:00.$t$),
    ('web.pobocky.branches.1.hours', 'fr', 'fill', NULL, $t$Ouverte 24/7 avec le code de l'appli. Tu choisis l'heure de retrait lors de la réservation : si tu récupères la moto à partir de 12 h (location de 2 jours ou plus), le 1er jour est à moitié prix et la borne te remet la moto à partir de 12 h. L'heure de retour ne se choisit pas : tu rends la moto quand tu veux le dernier jour de location, jusqu'à minuit.$t$),
    ('web.pobocky.branches.1.hours', 'nl', 'fill', NULL, $t$Open 24/7 met de code uit de app. Het ophaaltijdstip kies je in de reservering: haal je op vanaf 12:00 (huur van 2 dagen of langer), dan betaal je de 1e dag maar de helft en geeft de kiosk je de motor pas vanaf 12:00 mee. Het inlevertijdstip kies je niet: je levert de motor in wanneer je wilt op de laatste huurdag, tot 24:00.$t$),
    ('web.pobocky.branches.1.hours', 'pl', 'fill', NULL, $t$Czynny 24/7, na kod z aplikacji. Godzinę odbioru wybierasz w rezerwacji: przy odbiorze od 12:00 (wynajem na 2 dni lub dłużej) 1. dzień masz za pół ceny, a kiosk wyda ci motocykl dopiero od 12:00. Godziny zwrotu nie wybierasz: motocykl oddajesz o dowolnej porze ostatniego dnia wynajmu, do 24:00.$t$),
    ('web.pobocky.branches.1.hours', 'uk', 'fill', NULL, $t$Нонстоп 24/7 за кодом із застосунку. Час отримання обираєш у бронюванні: якщо забираєш з 12:00 (оренда на 2 дні й більше), 1-й день — за пів ціни, а кіоск видасть мотоцикл лише з 12:00. Час повернення не обирається: мотоцикл повертаєш будь-коли в останній день оренди до 24:00.$t$),
    ('web.pobocky.branches.1.steps', 'en', 'fill', NULL, $t$1. You book and pay online, choose your pick-up time and upload your documents (ID card/passport + driving licence): at the self-service branch this is essential; without verified documents you won't get the codes and can't enter the branch. Once your documents are verified, you'll receive the codes in the app, by e-mail and by SMS, in the order you'll enter them: <strong>1) lockbox code (gate key), 2) locker room code</strong> (if you're renting gear) <strong>and 3) bike code</strong>.<br>2. <strong>If the entrance gate is closed</strong>, use the app code to open the <strong>upper lockbox on the right gate pillar</strong>: it holds the padlock key. Unlock the gate, drive in and park in any of the spaces <strong>1–7 on the right by the fence</strong> (see the car park photo). Your car can stay here for free for the whole rental. If the gate is open, you don't need the lockbox code.<br>3. Enter the locker room code on the touchscreen: <strong>the locker room is door no. 8</strong>. Take your gear, get changed and close the locker room door (with your own gear, you skip the locker room). If you have the discount for pick-up from 12:00, the codes are valid from 12:00.<br>4. On the touchscreen, adjust the sizes in the handover protocol, sign it and enter the bike code: the bay with your bike opens. Close the bay and off you go!<br>5. <strong>If the gate was closed, close it again when you leave, lock the padlock, return the key to the upper lockbox and scramble the combination.</strong> If the gate is open, leave it open: never change the state of the gate.<br>6. After your ride, return the bike to its bay and the gear to the locker room, any time on the last day of the rental, by 24:00. Return the bike washed and with the reserve light off (no full tank needed). If the gate is closed, do the same: open it with the key from the lockbox and, when you leave, lock it again with the padlock and return the key.$t$),
    ('web.pobocky.branches.1.steps', 'de', 'fill', NULL, $t$1. Du reservierst und bezahlst online, wählst die Abholzeit und lädst deine Dokumente hoch (Ausweis/Reisepass + Führerschein) – in der Selbstbedienungsfiliale ist das zwingend: Ohne verifizierte Dokumente bekommst du keine Codes und kommst nicht in die Filiale. Nach der Prüfung der Dokumente erhältst du in der App, per E-Mail und SMS die Codes in der Reihenfolge, in der du sie eingibst: <strong>1) Code der Schlüsselbox mit dem Torschlüssel, 2) Code der Umkleide</strong> (wenn du Ausrüstung leihst) <strong>und 3) Code des Motorrads</strong>.<br>2. <strong>Ist das Einfahrtstor geschlossen</strong>, öffnest du mit dem Code aus der App die <strong>obere Schlüsselbox am rechten Torpfosten</strong>: Darin liegt der Schlüssel für das Vorhängeschloss. Schließ das Tor auf, fahr hinein und park auf einem der Stellplätze <strong>1–7 rechts am Zaun</strong> (siehe Foto vom Parkplatz). Dein Auto kann hier während der gesamten Miete kostenlos stehen. Ist das Tor offen, brauchst du den Code der Schlüsselbox nicht.<br>3. Am Display gibst du den Code der Umkleide ein: <strong>Die Umkleide ist Tür Nr. 8</strong>. Du nimmst die Ausrüstung, ziehst dich um und schließt die Tür der Umkleide (mit eigener Ausrüstung überspringst du die Umkleide). Hast du den Rabatt für die Abholung ab 12:00 Uhr, gelten die Codes erst ab 12:00 Uhr.<br>4. Am Display passt du im Übergabeprotokoll die Größen an, unterschreibst das Protokoll und gibst den Code des Motorrads ein: Die Box mit deinem Motorrad öffnet sich. Box schließen und los geht's!<br>5. <strong>War das Tor geschlossen, schließ es nach der Abfahrt wieder, sperr es mit dem Vorhängeschloss ab, leg den Schlüssel zurück in die obere Schlüsselbox und verstell die Zahlenräder.</strong> Ein offenes Tor lässt du offen: Ändere nie den Zustand des Tors.<br>6. Nach der Fahrt bringst du das Motorrad zurück in seine Box und die Ausrüstung in die Umkleide – jederzeit am letzten Miettag bis 24:00 Uhr. Bring das Motorrad gewaschen zurück, ohne dass die Reserveleuchte leuchtet (volltanken musst du nicht). Ist das Tor geschlossen, gehst du genauso vor: Du schließt es mit dem Schlüssel aus der Schlüsselbox auf, nach der Abfahrt wieder ab und legst den Schlüssel zurück.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.1.badge', 'bf8cdf78b8f55a709868faee09eaf66e'),
    ('web.pobocky.branches.1.hours', '8df93eb1fe78e7937ebbe95ccfc0d3ae'),
    ('web.pobocky.branches.1.steps', '55dacd7167a7f395dbf39a2a7593e705')
    ) AS g(k, gate) USING (k)
    ORDER BY (x.lang <> 'cs')            -- čeština první
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(CASE WHEN f.how = 'phrase' THEN replace(value #>> '{}', f.old, f.new) ELSE f.new END),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND CASE f.how WHEN 'full' THEN md5(value #>> '{}') = f.old
                        WHEN 'phrase' THEN strpos(value #>> '{}', f.old) > 0 AND strpos(value #>> '{}', f.new) = 0
                        ELSE false END;
    ELSE
      UPDATE public.cms_variables
         SET translations = jsonb_set(translations, ARRAY[f.lang],
               coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object('value',
                 CASE WHEN f.how = 'phrase' THEN replace(translations -> f.lang ->> 'value', f.old, f.new) ELSE f.new END)),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string' AND md5(value #>> '{}') = f.gate
         AND jsonb_typeof(translations) = 'object'
         AND CASE f.how
               WHEN 'fill' THEN (translations -> f.lang IS NULL OR jsonb_typeof(translations -> f.lang) = 'object')
                                AND coalesce(translations -> f.lang ->> 'value', '') = ''
               WHEN 'full' THEN jsonb_typeof(translations -> f.lang) = 'object'
                                AND md5(translations -> f.lang ->> 'value') = f.old
               ELSE jsonb_typeof(translations -> f.lang) = 'object'
                    AND strpos(translations -> f.lang ->> 'value', f.old) > 0
                    AND strpos(translations -> f.lang ->> 'value', f.new) = 0 END;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> '{}', CASE WHEN f.lang = 'cs' THEN value #>> '{}' ELSE translations -> f.lang ->> 'value' END
        INTO v_cs, v_cur FROM public.cms_variables WHERE key = f.k;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSIF f.lang <> 'cs' AND md5(v_cs) IS DISTINCT FROM f.gate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'pobocky_preklady: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'pobocky_preklady: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'pobocky_preklady: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
