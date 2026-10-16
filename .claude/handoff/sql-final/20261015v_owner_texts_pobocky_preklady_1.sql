-- =============================================================================
-- 20261015v_owner_texts_pobocky_preklady_1.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 1/7).
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
    ('web.pobocky.branches.0.address', 'en', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'de', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'es', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'fr', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'nl', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'pl', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.address', 'uk', 'fill', NULL, $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.pobocky.branches.0.badge', 'en', 'fill', NULL, 'Staffed branch'),
    ('web.pobocky.branches.0.badge', 'de', 'fill', NULL, 'Filiale mit Personal'),
    ('web.pobocky.branches.0.badge', 'es', 'fill', NULL, 'Sucursal con personal'),
    ('web.pobocky.branches.0.badge', 'fr', 'fill', NULL, 'Agence avec personnel'),
    ('web.pobocky.branches.0.badge', 'nl', 'fill', NULL, 'Bemande vestiging'),
    ('web.pobocky.branches.0.badge', 'pl', 'fill', NULL, $t$Oddział z obsługą$t$),
    ('web.pobocky.branches.0.badge', 'uk', 'fill', NULL, $t$Філія з персоналом$t$),
    ('web.pobocky.branches.0.gear', 'en', 'fill', NULL, $t$Rider gear included in the price: jackets and trousers in sizes up to <strong>6XL</strong>. Only here can you also rent <strong>rain gear</strong> and other extra equipment.$t$),
    ('web.pobocky.branches.0.gear', 'de', 'fill', NULL, $t$Fahrerausrüstung im Preis inbegriffen: Jacken und Hosen in Größen bis <strong>6XL</strong>. Nur hier kannst du auch <strong>Regenkombis</strong> und weitere Zusatzausrüstung leihen.$t$),
    ('web.pobocky.branches.0.gear', 'es', 'fill', NULL, $t$Equipo de piloto incluido en el precio: chaquetas y pantalones en tallas hasta la <strong>6XL</strong>. Solo aquí puedes alquilar también <strong>trajes de lluvia</strong> y otro equipo adicional.$t$),
    ('web.pobocky.branches.0.gear', 'fr', 'fill', NULL, $t$Équipement pilote inclus dans le prix : vestes et pantalons jusqu'à la taille <strong>6XL</strong>. Ici seulement, tu peux aussi louer une <strong>tenue de pluie</strong> et d'autres équipements complémentaires.$t$),
    ('web.pobocky.branches.0.gear', 'nl', 'fill', NULL, $t$Rijuitrusting bij de prijs inbegrepen: jassen en broeken in maten tot <strong>6XL</strong>. Alleen hier kun je ook <strong>regenkleding</strong> en andere extra uitrusting huren.$t$),
    ('web.pobocky.branches.0.gear', 'pl', 'fill', NULL, $t$Wyposażenie kierowcy w cenie: kurtki i spodnie w rozmiarach do <strong>6XL</strong>. Tylko tutaj wypożyczysz też <strong>odzież przeciwdeszczową</strong> i inne dodatkowe wyposażenie.$t$),
    ('web.pobocky.branches.0.gear', 'uk', 'fill', NULL, $t$Екіпірування водія в ціні — куртки й штани розмірів до <strong>6XL</strong>. Лише тут можна взяти напрокат і <strong>дощовики</strong> та інше додаткове екіпірування.$t$),
    ('web.pobocky.branches.0.hours', 'en', 'fill', NULL, $t$Monday to Sunday, any time (nonstop), including weekends and public holidays. You choose the pick-up and return time in your booking.$t$),
    ('web.pobocky.branches.0.hours', 'de', 'fill', NULL, $t$Mo–So rund um die Uhr (nonstop), auch an Wochenenden und Feiertagen. Abhol- und Rückgabezeit wählst du bei der Reservierung.$t$),
    ('web.pobocky.branches.0.hours', 'es', 'fill', NULL, $t$De lunes a domingo, a cualquier hora (nonstop), también fines de semana y festivos. La hora de recogida y de devolución la eliges en la reserva.$t$),
    ('web.pobocky.branches.0.hours', 'fr', 'fill', NULL, $t$Du lundi au dimanche, à toute heure (non-stop), week-ends et jours fériés compris. Tu choisis l'heure de retrait et de retour lors de la réservation.$t$),
    ('web.pobocky.branches.0.hours', 'nl', 'fill', NULL, $t$Maandag t/m zondag, op elk moment (nonstop), ook in het weekend en op feestdagen. Het tijdstip van ophalen en inleveren kies je in de reservering.$t$),
    ('web.pobocky.branches.0.hours', 'pl', 'fill', NULL, $t$Od poniedziałku do niedzieli, o dowolnej porze (nonstop), także w weekendy i święta. Godzinę odbioru i zwrotu wybierasz w rezerwacji.$t$),
    ('web.pobocky.branches.0.hours', 'uk', 'fill', NULL, $t$Пн–Нд будь-коли (нонстоп), також у вихідні та свята. Час отримання й повернення обираєш у бронюванні.$t$),
    ('web.pobocky.branches.0.steps', 'en', 'fill', NULL, $t$1. You book and pay online (web or app) and upload your documents (ID card/passport + driving licence); we ask for this at the staffed branch too: if you don't upload them, we check them on the spot at pick-up.<br>2. At the chosen time you arrive at the branch, where we are waiting for you.<br>3. We hand over the bike and gear and sign the handover protocol.<br>4. After your ride you return the bike to the branch (or we collect it from the agreed address); no need to wash or refuel it, just make sure the reserve light is off.$t$),
    ('web.pobocky.branches.0.steps', 'de', 'fill', NULL, $t$1. Du reservierst und bezahlst online (Website oder App) und lädst deine Dokumente hoch (Ausweis/Reisepass + Führerschein) – darum bitten wir auch in der Filiale mit Personal; lädst du sie nicht hoch, prüfen wir sie bei der Übernahme vor Ort.<br>2. Zur gewählten Zeit kommst du zur Filiale, wo wir auf dich warten.<br>3. Wir übergeben dir Motorrad und Ausrüstung und unterschreiben das Übergabeprotokoll.<br>4. Nach der Fahrt gibst du das Motorrad in der Filiale zurück (oder wir holen es an der vereinbarten Adresse ab) – waschen und tanken musst du es nicht, nur die Reserveleuchte sollte nicht leuchten.$t$),
    ('web.pobocky.branches.0.steps', 'es', 'fill', NULL, $t$1. Reservas y pagas online (web o app) y subes tus documentos (DNI/pasaporte + carnet de conducir); también te lo pedimos en la sucursal con personal: si no los subes, los revisamos en el momento de la recogida.<br>2. A la hora elegida llegas a la sucursal, donde te esperamos.<br>3. Te entregamos la moto y el equipo y firmamos el protocolo de entrega.<br>4. Después de rodar, devuelves la moto en la sucursal (o la recogemos en la dirección acordada); no tienes que lavarla ni repostar, solo procura que no esté encendido el testigo de reserva.$t$),
    ('web.pobocky.branches.0.steps', 'fr', 'fill', NULL, $t$1. Tu réserves et paies en ligne (site ou appli) et tu téléverses tes documents (carte d'identité/passeport + permis de conduire) ; nous le demandons aussi à l'agence avec personnel : si tu ne les téléverses pas, nous les vérifions sur place au moment du retrait.<br>2. À l'heure choisie, tu arrives à l'agence, où nous t'attendons.<br>3. Nous te remettons la moto et l'équipement, et nous signons le procès-verbal de remise.<br>4. Après ta sortie, tu rends la moto à l'agence (ou nous venons la chercher à l'adresse convenue) ; pas besoin de la laver ni de faire le plein, veille seulement à ce que le voyant de réserve soit éteint.$t$),
    ('web.pobocky.branches.0.steps', 'nl', 'fill', NULL, $t$1. Je reserveert en betaalt online (website of app) en uploadt je documenten (ID-kaart/paspoort + rijbewijs); dat vragen we ook bij de bemande vestiging: upload je ze niet, dan controleren we ze ter plaatse bij het ophalen.<br>2. Op het gekozen tijdstip kom je naar de vestiging, waar we op je wachten.<br>3. We overhandigen je de motor en de uitrusting en ondertekenen het overdrachtsprotocol.<br>4. Na je rit lever je de motor in bij de vestiging (of we halen hem op het afgesproken adres op); wassen of tanken is niet nodig, zorg alleen dat het reservelampje niet brandt.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.0.address', '5dd3b9b44e99a17d25805547998f853b'),
    ('web.pobocky.branches.0.badge', '6ddd159aee08736ddf1ba843670da9f5'),
    ('web.pobocky.branches.0.gear', '09a0e7d7fe8e9ca5db29be7e4edbd0ca'),
    ('web.pobocky.branches.0.hours', 'e421f81bc5203ec09a527ce09602e7b6'),
    ('web.pobocky.branches.0.steps', '79176a8fcb0144ea9ecff2e4e9a0e904')
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
