-- =============================================================================
-- 20261015y_owner_texts_pobocky_preklady_4.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 4/7).
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
    ('web.pobocky.branches.1.steps', 'es', 'fill', NULL, $t$1. Reservas y pagas online, eliges la hora de recogida y subes tus documentos (DNI/pasaporte + carnet de conducir): en la sucursal de autoservicio es imprescindible; sin documentos verificados no recibes los códigos y no puedes entrar en la sucursal. Una vez verificados los documentos, recibirás en la app, por e-mail y por SMS los códigos en el orden en que los vas a introducir: <strong>1) código de la caja con la llave del portón, 2) código del vestuario</strong> (si alquilas equipo) <strong>y 3) código de la moto</strong>.<br>2. <strong>Si el portón de entrada está cerrado</strong>, abre con el código de la app la <strong>caja superior del pilar derecho del portón</strong>: dentro está la llave del candado. Abre el portón, entra y aparca en cualquiera de las plazas <strong>1–7, a la derecha junto a la valla</strong> (mira la foto del aparcamiento). Tu coche puede quedarse aquí gratis durante todo el alquiler. Si el portón está abierto, no necesitas el código de la caja.<br>3. En la pantalla introduces el código del vestuario: <strong>el vestuario es la puerta n.º 8</strong>. Coges el equipo, te cambias y cierras la puerta del vestuario (si llevas tu propio equipo, te saltas el vestuario). Si tienes el descuento por recogida a partir de las 12:00, los códigos valen a partir de las 12:00.<br>4. En la pantalla ajustas las tallas en el protocolo de entrega, lo firmas e introduces el código de la moto: se abre el box con tu moto. Cierras el box y ¡a rodar!<br>5. <strong>Si el portón estaba cerrado, al salir vuelve a cerrarlo, échale el candado, devuelve la llave a la caja superior y gira los números de la combinación.</strong> Si el portón está abierto, déjalo abierto: nunca cambies el estado del portón.<br>6. Después de rodar, devuelves la moto a su box y el equipo al vestuario, cuando quieras el último día del alquiler, hasta las 24:00. Devuelve la moto lavada y sin el testigo de reserva encendido (no hace falta el depósito de combustible lleno). Si el portón está cerrado, haces lo mismo: lo abres con la llave de la caja y, al salir, lo vuelves a cerrar con el candado y devuelves la llave.$t$),
    ('web.pobocky.branches.1.steps', 'fr', 'fill', NULL, $t$1. Tu réserves et paies en ligne, tu choisis l'heure de retrait et tu téléverses tes documents (carte d'identité/passeport + permis de conduire) : à l'agence en libre-service, c'est indispensable ; sans documents vérifiés, tu ne reçois pas les codes et tu ne peux pas entrer dans l'agence. Une fois tes documents vérifiés, tu reçois dans l'appli, par e-mail et par SMS les codes dans l'ordre où tu vas les saisir : <strong>1) code de la boîte avec la clé du portail, 2) code du vestiaire</strong> (si tu loues de l'équipement) <strong>et 3) code de la moto</strong>.<br>2. <strong>Si le portail d'entrée est fermé</strong>, ouvre avec le code de l'appli la <strong>boîte du haut sur le pilier droit du portail</strong> : elle contient la clé du cadenas. Déverrouille le portail, entre et gare-toi sur l'une des places <strong>1–7, à droite le long de la clôture</strong> (voir la photo du parking). Ta voiture peut y rester gratuitement pendant toute la location. Si le portail est ouvert, tu n'as pas besoin du code de la boîte.<br>3. Sur l'écran, saisis le code du vestiaire : <strong>le vestiaire est la porte n° 8</strong>. Prends l'équipement, change-toi et referme la porte du vestiaire (avec ton propre équipement, tu passes l'étape du vestiaire). Si tu as la réduction pour un retrait à partir de 12 h, les codes ne sont valables qu'à partir de 12 h.<br>4. Sur l'écran, ajuste les tailles dans le procès-verbal de remise, signe-le et saisis le code de la moto : le box avec ta moto s'ouvre. Referme le box et c'est parti !<br>5. <strong>Si le portail était fermé, referme-le en partant, verrouille le cadenas, remets la clé dans la boîte du haut et brouille la combinaison.</strong> Si le portail est ouvert, laisse-le ouvert : ne change jamais l'état du portail.<br>6. Après ta sortie, rends la moto dans son box et l'équipement au vestiaire, quand tu veux le dernier jour de location, jusqu'à minuit. Rends la moto lavée et sans voyant de réserve allumé (le plein n'est pas nécessaire). Si le portail est fermé, même procédure : ouvre-le avec la clé de la boîte puis, en partant, referme-le au cadenas et remets la clé.$t$),
    ('web.pobocky.branches.1.steps', 'nl', 'fill', NULL, $t$1. Je reserveert en betaalt online, kiest het ophaaltijdstip en uploadt je documenten (ID-kaart/paspoort + rijbewijs): bij de zelfbedieningsvestiging is dat noodzakelijk; zonder geverifieerde documenten krijg je geen codes en kom je de vestiging niet in. Na verificatie van je documenten ontvang je in de app, per e-mail en per sms de codes in de volgorde waarin je ze invoert: <strong>1) code van het kastje met de poortsleutel, 2) code van de kleedkamer</strong> (als je uitrusting huurt) <strong>en 3) code van de motor</strong>.<br>2. <strong>Is de toegangspoort gesloten</strong>, open dan met de code uit de app het <strong>bovenste kastje aan de rechterpaal van de poort</strong>: daarin zit de sleutel van het hangslot. Open de poort, rijd naar binnen en parkeer op een van de plekken <strong>1–7, rechts langs het hek</strong> (zie de foto van de parkeerplaats). Je auto mag hier de hele huurperiode gratis staan. Staat de poort open, dan heb je de code van het kastje niet nodig.<br>3. Op het scherm voer je de code van de kleedkamer in: <strong>de kleedkamer is deur nr. 8</strong>. Je pakt de uitrusting, kleedt je om en sluit de deur van de kleedkamer (met je eigen uitrusting sla je de kleedkamer over). Heb je de korting voor ophalen vanaf 12:00, dan zijn de codes pas vanaf 12:00 geldig.<br>4. Op het scherm pas je in het overdrachtsprotocol de maten aan, onderteken je het en voer je de code van de motor in: de box met je motor gaat open. Je sluit de box en gaat op pad.<br>5. <strong>Was de poort gesloten, sluit hem dan na vertrek weer, doe het hangslot erop, leg de sleutel terug in het bovenste kastje en verdraai de cijferwieltjes.</strong> Staat de poort open, laat hem dan open: verander nooit de stand van de poort.<br>6. Na je rit zet je de motor terug in zijn box en de uitrusting in de kleedkamer, wanneer je wilt op de laatste huurdag, tot 24:00. Lever de motor gewassen in en zonder brandend reservelampje (een volle tank is niet nodig). Is de poort gesloten, dan doe je hetzelfde: je opent hem met de sleutel uit het kastje en sluit hem na vertrek weer af met het hangslot en legt de sleutel terug.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
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
