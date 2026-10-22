-- =============================================================================
-- 20261015p_owner_texts_layout_1.sql
-- datová migrace (bez změn schématu): texty rozvržení webu: úprava rezervace, potvrzení, patička, samoobsluha (část 1/2).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- cms_variables web.layout.* přebíjí lang/<jazyk>.php:
--  editRez.loc.atRentalDescPickup – překlady měly „autonomní pobočka“ a PSČ 257 87 → = lang/<jazyk>.php
--  editRez.loc.atRentalDescReturn – „vrátíte v autonomní pobočce“ i u Mezné → „Vrátíte přímo na pobočce.“
--  confirm.success.nextBookingPickup – „kódy odemknou dveře“ všem → rozlišeno VN / Mezná / přistavení
--  footer.aboutText – patička jen „v Pelhřimově“ → „v Pelhřimově a u Brna“
--  rez.pickup.selfServiceNoDeliveryText – kód až „po zaplacení a ověření dokladů“ (= lang/cs.php)
-- Stejné znění musí dostat i lang/<jazyk>.php (viz PŘEHLED).
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
    ('web.layout.editRez.loc.atRentalDescPickup', 'de', 'full', 'e4da0c5ab74034e0233f41e3136dafc7', $t$Mezná 9, 393 01 Pelhřimov — Filiale mit Personal, 24/7 geöffnet. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescPickup', 'en', 'full', 'ca31e2ede82e77008835551b91560add', $t$Mezná 9, 393 01 Pelhřimov — staffed branch, open 24/7. <strong>Free.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescPickup', 'es', 'full', 'e2dee81054726110539a66c4bf1ba441', $t$Mezná 9, 393 01 Pelhřimov — sucursal con personal, abierta 24/7. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescPickup', 'fr', 'full', '89a2f11ceeaecfc11d7b4dcb20b5e7b8', $t$Mezná 9, 393 01 Pelhřimov — agence avec personnel, ouverte 24/7. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescPickup', 'nl', 'full', 'eec88108169069b85c842d193b29d0a2', $t$Mezná 9, 393 01 Pelhřimov — bemande vestiging, 24/7 geopend. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescPickup', 'pl', 'full', '524e9879018f4a20bb1876c64026ab6f', $t$Mezná 9, 393 01 Pelhřimov — oddział z obsługą, czynny 24/7. <strong>0 CZK.</strong>$t$),
    ('web.layout.rez.pickup.selfServiceNoDeliveryText', 'cs', 'full', '1f302ba4f59da139c5fc503939e7ea3b', $t$Motorky ze samoobslužné pobočky se přebírají i vracejí pouze na pobočce — nonstop (24/7) pomocí kódu, který dostanete po zaplacení a ověření dokladů. Přistavení na adresu ani odvoz z adresy u nich zatím nenabízíme; v budoucnu tuto službu zapneme.$t$),
    ('web.layout.editRez.loc.atRentalDescReturn', 'cs', 'full', '5f8438b5aa7cd88f967522cafa10ffae', $t$Vrátíte přímo na pobočce. <strong>0 Kč.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescReturn', 'de', 'full', 'e0a6d1f57b1289f6d2fcb6ec3f645d29', $t$Rückgabe direkt in der Filiale. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescReturn', 'en', 'full', '5d5364d873abb3fbabebf2b926c8bd75', 'Return directly at the branch. <strong>Free.</strong>'),
    ('web.layout.editRez.loc.atRentalDescReturn', 'es', 'full', 'f36ee705825b63fb9926e9687f74c675', $t$Devolución directamente en la sucursal. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescReturn', 'fr', 'full', '1a3d28cb93bd0e71858d933595c9724d', $t$Retour directement à l'agence. <strong>0 CZK.</strong>$t$),
    ('web.layout.editRez.loc.atRentalDescReturn', 'nl', 'full', 'a902f105816d6f4cc094625245be8290', 'Inleveren direct bij de vestiging. <strong>0 CZK.</strong>'),
    ('web.layout.editRez.loc.atRentalDescReturn', 'pl', 'full', '752aeb2b5aff29251656019bc3e044c2', $t$Zwrot bezpośrednio w oddziale. <strong>0 CZK.</strong>$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'cs', 'full', 'b807151c3c9286a8f624f2d2f51cc806', $t$V den vyzvednutí přijeď na pobočku. Na samoobslužné pobočce ve Velkých Němčicích ti kódy odemknou dveře k výbavě i motorce, v Mezné ti motorku i výbavu předá obsluha. Máš-li objednané přistavení, čekej na zvolené adrese.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'de', 'full', '325cb158483bacebd5b2de0a114d3389', $t$Am Abholtag kommen Sie zur Filiale. In der Selbstbedienungsfiliale in Velké Němčice öffnen die Codes die Türen zu Ausrüstung und Motorrad, in Mezná übergibt Ihnen unser Personal Motorrad und Ausrüstung. Haben Sie eine Lieferung bestellt, warten Sie an der gewählten Adresse.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'en', 'full', '07c4fe0b6ac79baee20668ac1c568101', $t$On pick-up day, come to the branch. At the self-service branch in Velké Němčice the codes open the doors to your gear and bike; in Mezná our staff hand over the bike and gear. If you ordered delivery, wait at the chosen address.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'es', 'full', 'f8e4d4ecf71aab140eca58864a9d3476', $t$El día de la recogida, ven a la sucursal. En la sucursal de autoservicio de Velké Němčice los códigos abren las puertas del equipo y de la moto; en Mezná nuestro personal te entrega la moto y el equipo. Si pediste la entrega, espera en la dirección elegida.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'fr', 'full', 'ecf25a8adbb27f58af9f981d0c49afd7', $t$Le jour du retrait, rendez-vous à l'agence. À l'agence en libre-service de Velké Němčice, les codes ouvrent les portes de l'équipement et de la moto ; à Mezná, notre personnel vous remet la moto et l'équipement. Si vous avez commandé la livraison, attendez à l'adresse choisie.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'nl', 'full', 'a5f9a527340be1e1fa5e103603053933', $t$Kom op de ophaaldag naar de vestiging. Bij de zelfbedieningsvestiging in Velké Němčice openen de codes de deuren naar uitrusting en motor; in Mezná overhandigt ons personeel u de motor en uitrusting. Heeft u bezorging besteld, wacht dan op het gekozen adres.$t$),
    ('web.layout.confirm.success.nextBookingPickup', 'pl', 'full', '7d9dbe96a205e1a0b34a511efcfa7d25', $t$W dniu odbioru przyjedź do oddziału. W samoobsługowym oddziale Velké Němčice kody otworzą drzwi do sprzętu i motocykla, a w oddziale Mezná motocykl i sprzęt przekaże ci obsługa. Jeśli zamówiłeś dostawę, czekaj pod wybranym adresem.$t$),
    ('web.layout.footer.aboutText', 'cs', 'phrase', $t$<strong>půjčovny motorek v Pelhřimově</strong>$t$, $t$<strong>půjčovny motorek v Pelhřimově a u Brna</strong>$t$),
    ('web.layout.footer.aboutText', 'de', 'full', 'f00a9e2b7cd0147932173a1bc479dec3', $t$Willkommen bei MotoGo24, deiner&nbsp;<strong>Motorradvermietung in Pelhřimov und bei Brno</strong>! Wir bieten <strong>Motorradverleih</strong> für Einheimische und Touristen. Wähle aus unserem großen Angebot an Motorrädern und reserviere online in drei Schritten. Entdecke mit uns Motorradstrecken in Tschechien und im Ausland!$t$),
    ('web.layout.footer.aboutText', 'en', 'full', '5b5bd189056f94bb871e19578723262a', $t$Welcome to MotoGo24, your&nbsp;<strong>motorcycle rental in Pelhřimov and near Brno</strong>! We offer <strong>motorcycle rental</strong> for locals and tourists. Choose from our wide selection of motorcycles and book online in three simple steps. Discover motorcycle routes in the Czech Republic and abroad with us!$t$),
    ('web.layout.footer.aboutText', 'es', 'full', '12ce244d107b59b1ac6282f70bb095bd', $t$¡Bienvenido a MotoGo24, tu&nbsp;<strong>alquiler de motos en Pelhřimov y cerca de Brno</strong>! Ofrecemos <strong>alquiler de motos</strong> para residentes y turistas. Elige entre nuestra amplia oferta de motos y reserva online en tres pasos. ¡Descubre con nosotros rutas en moto por la República Checa y el extranjero!$t$),
    ('web.layout.footer.aboutText', 'fr', 'full', '7d206205f8df39540fe6c280827f1789', $t$Bienvenue chez MotoGo24, ta&nbsp;<strong>location de motos à Pelhřimov et près de Brno</strong> ! Nous proposons la <strong>location de motos</strong> aux habitants comme aux touristes. Choisis parmi notre large gamme de motos et réserve en ligne en trois étapes. Découvre avec nous des itinéraires à moto en République tchèque et à l'étranger !$t$),
    ('web.layout.footer.aboutText', 'nl', 'full', 'd9cad8faeebdaab9b5d289788e18dff1', $t$Welkom bij MotoGo24, jouw&nbsp;<strong>motorverhuur in Pelhřimov en bij Brno</strong>! Wij bieden <strong>motorverhuur</strong> voor inwoners en toeristen. Kies uit ons ruime aanbod aan motoren en reserveer online in drie stappen. Ontdek met ons motorroutes in Tsjechië en daarbuiten!$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.layout.editRez.loc.atRentalDescPickup', '1435911cbecd6cec6197f3cc577f2d4d'),
    ('web.layout.rez.pickup.selfServiceNoDeliveryText', '06aa490c120d99b88e4cd9b8ebc30724'),
    ('web.layout.editRez.loc.atRentalDescReturn', '3b23ee0ec5cb54f74fc0f3494cf9c804'),
    ('web.layout.confirm.success.nextBookingPickup', 'f07348861165446f6dec587d21e73766'),
    ('web.layout.footer.aboutText', '50763bb51834485b7a0d06b61f5099eb')
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
        RAISE NOTICE 'layout: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'layout: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'layout: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
