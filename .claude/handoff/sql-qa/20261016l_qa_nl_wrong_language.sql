-- =============================================================================
-- 20261016l_qa_nl_wrong_language.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- 1) Nizozemština: v překladech nl jsou ANGLICKÉ texty (Velín auto-překlad), které na webu přebíjejí
--    správnou nizozemštinu z lang/nl.php (web.layout.* má přednost před slovníkem) → nl zákazník vidí
--    angličtinu v rezervaci (tip přistavení/odvozu), v obnově hesla, na stránce Dokumenty a Kontakt.
--      • web.layout.rez.pickup.deliveryTip, .returnTip, web.layout.editRez.reset.otpHelp → = lang/nl.php
--      • web.jak_pujcit_dokumenty.payments.rows.4.1, web.kontakt.seo_text.body → nizozemský překlad
--        AKTUÁLNÍ české hodnoty v DB (kontakt: verze z Velínu „Mezná u Pelhřimova … choppery i skútry“)
--      • motorky (translations.nl): KTM SX 50 Replica – popis; Yamaha XT660 X – popis + výbava (features)
--        → nizozemský překlad aktuální češtiny (struktura HTML 1:1). (20261016k doplňuje jen PRÁZDNÁ pole.)
-- 2) Adresa: překlady de/en/es/fr/nl/pl mají „Mezná 9, 393 01 Mezná“, česká hodnota i web, smlouva, VOP
--    záhlaví, GDPR a e-maily „Mezná 9, 393 01 Pelhřimov“ → v překladu se vymění JEN adresa:
--    web.layout.rez.pickup.deliveryTip/returnTip (rezervace), web.layout.editRez.loc.atRental
--    (úprava rezervace), web.kontakt.address, web.kontakt.billing.addr (dnes webem nepoužité, sjednoceno).
-- Bezpečnost: překlad se mění jen když má PŘESNĚ znění ověřené proti živé DB 2026-10-16 (md5) a česká
-- hodnota je stále ta, ze které se překládalo (md5); jinak NOTICE a beze změny (úpravy ve Velínu
-- mají přednost). Ostatní jazyky/pole beze změny. Idempotentní (2. běh: „už hotovo“). Bez BEGIN/COMMIT.
-- =============================================================================
DO $$
DECLARE
  f record;
  v_cur text;
  n integer;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN SELECT * FROM (VALUES
    ('web.layout.rez.pickup.deliveryTip', 'nl', '60f34d9a128d726158b7090a56a319c4', 'b46a88f452315c22f5bc6e38ad635647', $t$Wij bezorgen de motor op een afgesproken plek. Prijs: {base} + {perKm}/km vanaf de vestiging Mezná 9, 393 01 Pelhřimov. De route wordt automatisch berekend nadat u het adres invoert.$t$),
    ('web.layout.rez.pickup.returnTip', 'nl', '73e515243881252c667b787dbadc0735', '305ae52beadac2ba54661572d79759a0', $t$We halen de motor graag elders op. Prijs: {base} + {perKm}/km vanaf de vestiging Mezná 9, 393 01 Pelhřimov. De route wordt automatisch berekend nadat u het adres invoert.$t$),
    ('web.layout.editRez.reset.otpHelp', 'nl', '69136c101f876fcca57028a4f04da79c', 'a51d77fbfaad8f9befdf67154f4fa82b', $t$Wij hebben een verificatiecode gestuurd naar <strong>{email}</strong>. Voer de code van 8 tekens uit de e-mail in (dezelfde code werkt voor app en web) en stel een nieuw wachtwoord in.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.4.1', 'nl', 'f0055802d6e25ce2dfa0a1eb70bf7490', '599a5d219a2d44a4fd49e9ff1673c4d2', $t$We vragen je de motor op de laatste huurdag op tijd terug te brengen of de huur officieel te laten verlengen.$t$),
    ('web.kontakt.seo_text.body', 'nl', '1f16763c76232b56fef81103628cb921', '80b3a046b725c166921446d265d8e140', $t$MotoGo24 is een <strong>moderne motorverhuur in Vysočina</strong>. We zijn gevestigd in <strong>Mezná bij Pelhřimov,</strong>&nbsp;zijn praktisch&nbsp;<strong>24/7</strong> open en verhuren <strong>zonder borg</strong>, met complete <strong>rijuitrusting bij de prijs inbegrepen</strong>. Neem contact met ons op voor <strong>toermotoren</strong>, <strong>naked bikes</strong>, <strong>supermoto's</strong>,&nbsp;<strong>kindermotoren, choppers</strong>&nbsp;en <strong>scooters </strong>- alles met een volledig geautomatiseerde en eenvoudige online reservering en betaling.$t$),
    ('web.layout.rez.pickup.deliveryTip', 'de', 'e995981342aeac54e944397cc9619c96', 'b46a88f452315c22f5bc6e38ad635647', $t$Das Motorrad bringen wir dir an den vereinbarten Ort. Preis: {base} + {perKm}/km ab Filiale Mezná 9, 393 01 Pelhřimov. Die Route berechnen wir automatisch nach Eingabe der Adresse.$t$),
    ('web.layout.rez.pickup.deliveryTip', 'en', '0676167b2d65669048178ba30b97762c', 'b46a88f452315c22f5bc6e38ad635647', $t$We will deliver the motorcycle to an agreed location. Price: {base} + {perKm}/km from the Mezná branch, Mezná 9, 393 01 Pelhřimov. We will calculate the route automatically after you enter the address.$t$),
    ('web.layout.rez.pickup.deliveryTip', 'es', 'cd0fea15b338cea66b1d1030a8a9eaf6', 'b46a88f452315c22f5bc6e38ad635647', $t$Te entregaremos la moto en el lugar acordado. Precio: {base} + {perKm}/km desde la sucursal Mezná 9, 393 01 Pelhřimov. Calcularemos la ruta automáticamente después de que ingreses la dirección.$t$),
    ('web.layout.rez.pickup.deliveryTip', 'fr', 'b111075f8b8bce6afd28f068b174daad', 'b46a88f452315c22f5bc6e38ad635647', $t$Nous vous livrerons la moto au lieu convenu. Prix : {base} + {perKm}/km depuis la succursale Mezná 9, 393 01 Pelhřimov. L'itinéraire sera calculé automatiquement après saisie de l'adresse.$t$),
    ('web.layout.rez.pickup.deliveryTip', 'pl', 'a9f63bed180c63e4d6169ea2b46c8dae', 'b46a88f452315c22f5bc6e38ad635647', $t$Motocykl dostarczymy do ustalonego miejsca. Cena: {base} + {perKm}/km od oddziału Mezná 9, 393 01 Pelhřimov. Trasę obliczymy automatycznie po podaniu adresu.$t$),
    ('web.layout.rez.pickup.returnTip', 'de', '8e3de2b60ecab5f90549613beee8776e', '305ae52beadac2ba54661572d79759a0', $t$Das Motorrad holen wir gerne woanders ab. Preis: {base} + {perKm}/km ab der Filiale Mezná 9, 393 01 Pelhřimov. Die Route berechnen wir automatisch nach Eingabe der Adresse.$t$),
    ('web.layout.rez.pickup.returnTip', 'en', '54cecb2b5edafb8817f7cef34e2e02b6', '305ae52beadac2ba54661572d79759a0', $t$We'll gladly pick up the motorcycle elsewhere. Price: {base} + {perKm}/km from the Mezná 9, 393 01 Pelhřimov branch. We'll calculate the route automatically once you enter the address.$t$),
    ('web.layout.rez.pickup.returnTip', 'es', '307562b2fa675dc4aae01f011b33c764', '305ae52beadac2ba54661572d79759a0', $t$Podemos recoger la moto en otro lugar. Precio: {base} + {perKm}/km desde la sucursal Mezná 9, 393 01 Pelhřimov. Calcularemos automáticamente la ruta después de ingresar la dirección.$t$),
    ('web.layout.rez.pickup.returnTip', 'fr', 'e485ed17c9f66b0ff3e2f58d2f584df2', '305ae52beadac2ba54661572d79759a0', $t$Nous sommes heureux de récupérer la moto ailleurs. Tarif: {base} + {perKm}/km à partir de la succursale Mezná 9, 393 01 Pelhřimov. L'itinéraire sera calculé automatiquement après la saisie de l'adresse.$t$),
    ('web.layout.rez.pickup.returnTip', 'pl', 'f813509a66be255d4b05e001bf52eab6', '305ae52beadac2ba54661572d79759a0', $t$Chętnie odbierzemy motor gdzie indziej. Cena: {base} + {perKm}/km od lokalizacji Mezná 9, 393 01 Pelhřimov. Trasę obliczymy automatycznie po podaniu adresu.$t$),
    ('web.layout.editRez.loc.atRental', 'de', '18f61190235f4b64d1b33b67e74bc0cc', 'bd7baebfb35141027e2e48d34a96fe16', $t$In der Vermietung Mezná 9, 393 01 Pelhřimov$t$),
    ('web.layout.editRez.loc.atRental', 'en', '7cec29034d2c900d5ecf3aa0f30e5949', 'bd7baebfb35141027e2e48d34a96fe16', $t$At MotoGo24 Mezná 9, 393 01 Pelhřimov$t$),
    ('web.layout.editRez.loc.atRental', 'es', '7b8b7d781b5a1a2b653b1e7e36a40dcb', 'bd7baebfb35141027e2e48d34a96fe16', $t$En la sucursal de alquiler Mezná 9, 393 01 Pelhřimov$t$),
    ('web.layout.editRez.loc.atRental', 'fr', '3d37436b006679d68a3f68085a743b1d', 'bd7baebfb35141027e2e48d34a96fe16', $t$À la location Mezná 9, 393 01 Pelhřimov$t$),
    ('web.layout.editRez.loc.atRental', 'nl', '1c7f812a5b7b72ed870be8297f3eea08', 'bd7baebfb35141027e2e48d34a96fe16', $t$In het verhuurkantoor Mezná 9, 393 01 Pelhřimov$t$),
    ('web.layout.editRez.loc.atRental', 'pl', '15de7ebbb78e4c59f74a3f64a6a22d47', 'bd7baebfb35141027e2e48d34a96fe16', $t$W wynajmie Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'de', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'en', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'es', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'fr', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'nl', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.address', 'pl', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'de', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'en', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'es', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'fr', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'nl', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$),
    ('web.kontakt.billing.addr', 'pl', '9584deb68a37722bd2183b03409b516c', '5dd3b9b44e99a17d25805547998f853b', $t$Mezná 9, 393 01 Pelhřimov$t$)
  ) AS x(k, lang, old_md5, cs_md5, new_val) LOOP
    SELECT translations -> f.lang ->> 'value' INTO v_cur FROM public.cms_variables WHERE key = f.k;
    IF v_cur IS NOT DISTINCT FROM f.new_val THEN
      n_done := n_done + 1;
      CONTINUE;
    END IF;
    UPDATE public.cms_variables
       SET translations = jsonb_set(translations, ARRAY[f.lang, 'value'], to_jsonb(f.new_val)),
           updated_at = now()
     WHERE key = f.k
       AND md5(translations -> f.lang ->> 'value') = f.old_md5
       AND md5(value #>> '{}') = f.cs_md5;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 1 THEN n_upd := n_upd + 1;
    ELSE n_skip := n_skip + 1; RAISE NOTICE 'cms_variables %/%: text se liší od ověřeného (Velín?) – beze změny', f.k, f.lang;
    END IF;
  END LOOP;
  RAISE NOTICE 'nl/adresa cms_variables: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;

  n_upd := 0; n_done := 0; n_skip := 0;
  FOR f IN SELECT * FROM (VALUES
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'description', 'a601d21dc7850f34325904615fbe3bba', '122528ffc5cda57c01292a1eca9bd38a', $t$<p><strong>De KTM SX 50 Replica is een oranje racelegende voor de kleinste rijders.</strong> Geen compromissen, geen halve oplossingen, geen kinderachtig design. <strong>De SX 50 hoort thuis op afgesloten motorcrossbanen of andere afgesloten terreinen</strong>&nbsp;— eerste pogingen, wedstrijden, dromen van een grote carrière — daar is ze voor gemaakt.</p>
<p><strong>5,5 kW uit een 49,9cc-tweetaktmotor</strong>, een gewicht onder de <strong>40 kg</strong> en een lage zithoogte van <strong>585 mm</strong> betekenen maar één ding: <strong>een racebeleving op maat van een kleine rijder</strong>. De Replica-versie draagt de kleuren en graphics van het <strong>KTM-fabrieksteam</strong> — oranje, zwart, de echte motorcrosslook. <strong>Vloeistofkoeling en schijfremmen</strong> maken er een echte racemotor van, geen speelgoed. <strong>Licht, wendbaar, krachtig.</strong> Wil je kind de adrenaline van het rijden beleven, zoek dan niet verder.&nbsp;</p>$t$),
    ('a0000001-0000-0000-0000-000000000006', 'description', 'e59aff59873b86d0142ca30d6d7f74d4', '59beb239f0187e0bc22972399f6f6af2', $t$<span style="font-weight: bold;">De Yamaha XT660X is een klassieke supermoto met een groot ééncilinderhart</span> — een motor zoals niemand die vandaag de dag nog bouwt.
In plaats van een soepele viercilinder of een toer-tweecilinder zit er onder de tank een <span style="font-weight: bold;">legendarische 660cc-ééncilinder — een "big single"</span> met alles wat daarbij hoort: het typische brommende geluid, trekkracht van onderuit als een tractor en het karakteristieke "pulseren", dat van elke rit een belevenis voor alle zintuigen maakt. 

Het is geen motor voor iedereen — maar wie er eenmaal op zit, komt er niet meer van los.&nbsp;<div>De "X"-versie is een supermoto — dat betekent <span style="font-weight: bold;">17-inch sportwielen voor en achter, sportbanden en een zithouding als op een crossmotor</span>. <span style="font-weight: bold;">Het hoge zadel (865 mm)</span>, de lange veerwegen en de enorme voorremschijf maken deze motor tot koning van het stadsverkeer en van haarspeldbochten.&nbsp;Je zit hoger dan de bestuurders om je heen en kijkt over de autodaken heen — in de stadsjungle een enorm voordeel. <span style="font-weight: bold;">De ideale motor voor bergbochten, de stad en weekendtripjes.</span> Snelwegen en lange afstanden zijn echter niet zijn terrein.</div>$t$),
    ('a0000001-0000-0000-0000-000000000006', 'features', '15d274cc749897c8b3bd9b6104d74cf6', 'f2009e400bf12a2d5dab4a2c5134b503', $t$"Big single"-karakter — brommend geluid en trekkracht van onderuit, zoals alleen een ééncilinder dat kan
Supermoto-geometrie — 17" sportwielen voor en achter, ideaal voor asfalt
Hoge zithouding (zadel 865 mm) — je kijkt over het verkeer heen en hebt de motor zelfverzekerd onder controle
Lange veerwegen — comfort, zelfs op hobbelige binnenwegen
Enorme voorremschijf van 320 mm — krachtig en gecontroleerd remmen
Upside-down voorvork — sportief onderstel
Licht (ca. 185 kg) — wendbaar in bochten en in de stad
Eenvoudige techniek — betrouwbare ééncilinder met minimaal onderhoud
Karakteristieke supermoto-stijl — een motor waarop je gezien wordt
Antivibratie-telefoonhouder
Geen USB$t$)
  ) AS x(id, field, old_md5, cs_md5, new_val) LOOP
    SELECT translations -> 'nl' ->> f.field INTO v_cur FROM public.motorcycles WHERE id = f.id::uuid;
    IF v_cur IS NOT DISTINCT FROM f.new_val THEN
      n_done := n_done + 1;
      CONTINUE;
    END IF;
    UPDATE public.motorcycles
       SET translations = jsonb_set(translations, ARRAY['nl', f.field], to_jsonb(f.new_val))
     WHERE id = f.id::uuid
       AND md5(translations -> 'nl' ->> f.field) = f.old_md5
       AND md5(CASE WHEN f.field = 'features' THEN array_to_string(features, E'\n') ELSE description END) = f.cs_md5;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 1 THEN n_upd := n_upd + 1;
    ELSE n_skip := n_skip + 1; RAISE NOTICE 'motorcycles %/nl.%: text se liší od ověřeného (Velín?) – beze změny', f.id, f.field;
    END IF;
  END LOOP;
  RAISE NOTICE 'nl motorky: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
