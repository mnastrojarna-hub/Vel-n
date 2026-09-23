-- =============================================================================
-- FAQ: iOS appka je v App Store + Apple Pay / Google Pay v appce
-- Migrace: 20260923b_faq_ios_app_apple_pay.sql (DATOVÁ, bez změn schématu)
--
-- INCIDENT 2026-09-23: zákazník na iPhonu napsal AI agentovi v appce
-- (ai-moto-agent), že „nejde platit přes Apple Pay“. Agent odpověděl, že
-- „Apple Pay se u MotoGo24 nepodporuje“ a že „mobilní aplikace je zatím jen
-- pro Android, verze pro iOS se připravuje“ — výslovně „z FAQ“. Tool get_faq
-- čte tabulku faq_items a živé odpovědi byly zastaralé:
--   * bff7565d „Kde a jak si mohu stáhnout vaši mobilní aplikaci?“
--       → „zatím dostupná pouze pro Android, verze pro Apple se připravuje“
--   * 9d0038c0 „Jak probíhá rezervace?“ → „(zatím máme jen verzi pro Android)“
--   * 57912624 „Máte věrnostní program?“ → „Aplikace právě vychází“
--   * c54ab426 „Jak zaplatím?“ → „v aplikaci lze platit pouze kartou“
--       (bez zmínky o Apple Pay / Google Pay → AI z toho vyvodila „Apple Pay
--       není k dispozici“)
-- Skutečnost: iOS appka je v App Store od 2. 9. 2026 (Apple ID 6806045151),
-- v appce se platí kartou, na iPhonu i Apple Pay, na Androidu i Google Pay;
-- web (Stripe Checkout) nabízí kartu + Apple Pay + Google Pay, SEPA/QR jen web.
--
-- OPRAVA: v odpovědi (cs = sloupec answer) i ve VŠECH překladech
-- (translations->{lang}->answer: de, en, es, fr, nl, pl, uk) se nahradí JEN
-- zastaralá věta — zbytek textu (i případné ruční úpravy z Velína) zůstává.
-- Staré fráze jsou ověřené proti živým datům (REST faq_items 2026-09-23,
-- každá se v cílovém textu vyskytuje právě jednou).
--
-- Idempotentní: když už stará fráze v textu není (opraveno / přepsáno ve
-- Velíně), řádek se přeskočí s NOTICE — nic se nerozbije a migrace nespadne.
-- updated_at nastaví trigger faq_items_set_updated_at.
-- =============================================================================

DO $$
DECLARE
  f     record;
  cnt   integer;
  n_upd integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'cs', $t$ nebo na Google Play.</span>&nbsp;Aplikace je zatím dostupná pouze pro Android (mobily a tablety), verze pro Apple už se připravuje.$t$, $t$, nebo přímo v Google Play (Android) či v App Store (iPhone).</span>&nbsp;Aplikace je dostupná pro Android i pro iPhone (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'en', $t$ or on Google Play.</span>&nbsp;The app is currently available only for Android (phones and tablets), the Apple version is being prepared.$t$, $t$, or directly on Google Play (Android) or the App Store (iPhone).</span>&nbsp;The app is available for both Android and iPhone (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'de', $t$ oder im Google Play Store.</span>&nbsp;Die App ist derzeit nur für Android (Handys und Tablets) verfügbar, die Version für Apple wird gerade vorbereitet.$t$, $t$, oder direkt bei Google Play (Android) bzw. im App Store (iPhone).</span>&nbsp;Die App ist für Android und für das iPhone (iOS) verfügbar.$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'es', $t$ o en Google Play.</span>&nbsp;La aplicación está disponible actualmente solo para Android (teléfonos y tabletas), la versión para Apple ya está en preparación.$t$, $t$, o directamente en Google Play (Android) o en la App Store (iPhone).</span>&nbsp;La aplicación está disponible para Android y para iPhone (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'fr', $t$ ou sur Google Play.</span>&nbsp;L'application est actuellement disponible uniquement pour Android (téléphones et tablettes), la version pour Apple est en préparation.$t$, $t$, ou directement sur Google Play (Android) ou l'App Store (iPhone).</span>&nbsp;L'application est disponible sur Android et sur iPhone (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'nl', $t$ of op Google Play.</span>&nbsp;De applicatie is voorlopig alleen beschikbaar voor Android (telefoons en tablets), de versie voor Apple wordt al voorbereid.$t$, $t$, of rechtstreeks via Google Play (Android) of de App Store (iPhone).</span>&nbsp;De applicatie is beschikbaar voor Android en voor iPhone (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'pl', $t$ lub na Google Play.</span>&nbsp;Aplikacja jest obecnie dostępna tylko dla systemu Android (telefony i tablety), wersja dla Apple jest już w przygotowaniu.$t$, $t$, lub bezpośrednio w Google Play (Android) albo w App Store (iPhone).</span>&nbsp;Aplikacja jest dostępna na Androida i na iPhone'a (iOS).$t$),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'uk', $t$ або на Google Play.</span>&nbsp;Програма наразі доступна лише для Android (телефони та планшети), версія для Apple вже готується.$t$, $t$, або безпосередньо в Google Play (Android) чи в App Store (iPhone).</span>&nbsp;Програма доступна для Android і для iPhone (iOS).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'cs', $t$, která je k dispozici ke stažení na Google Play (zatím máme jen verzi pro Android).$t$, $t$, která je k dispozici ke stažení na Google Play (Android) i v App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'en', $t$, which is available for download on Google Play (currently we only have the Android version).$t$, $t$, which is available for download on Google Play (Android) and the App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'de', $t$, die zum Download auf Google Play verfügbar ist (derzeit nur für Android).$t$, $t$, die zum Download auf Google Play (Android) und im App Store (iPhone) verfügbar ist.$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'es', $t$, que está disponible para descargar en Google Play (de momento solo tenemos versión para Android).$t$, $t$, que está disponible para descargar en Google Play (Android) y en la App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'fr', $t$, disponible au téléchargement sur Google Play (pour le moment, nous avons seulement la version Android).$t$, $t$, disponible au téléchargement sur Google Play (Android) et sur l'App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'nl', $t$, die beschikbaar is voor download op Google Play (voorlopig alleen de Android-versie).$t$, $t$, die beschikbaar is voor download op Google Play (Android) en in de App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'pl', $t$, która jest dostępna do pobrania na Google Play (na razie mamy tylko wersję na Androida).$t$, $t$, która jest dostępna do pobrania w Google Play (Android) i w App Store (iPhone).$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'uk', $t$, яка доступна для завантаження на Google Play (поки що у нас є лише версія для Android).$t$, $t$, яка доступна для завантаження в Google Play (Android) та в App Store (iPhone).$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'cs', $t$ Aplikace právě vychází, tak ji rozhodně vyzkoušej.$t$, $t$ Aplikaci najdeš v Google Play (Android) i v App Store (iPhone), tak ji rozhodně vyzkoušej.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'en', $t$ The app is just launching, so definitely try it out.$t$, $t$ The app is available on Google Play (Android) and the App Store (iPhone), so definitely try it out.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'de', $t$ Die Anwendung wird gerade veröffentlicht, probieren Sie sie also unbedingt aus.$t$, $t$ Die App gibt es bei Google Play (Android) und im App Store (iPhone) – probieren Sie sie unbedingt aus.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'es', $t$ La aplicación está a punto de salir, así que definitivamente pruébala.$t$, $t$ La aplicación está disponible en Google Play (Android) y en la App Store (iPhone), así que no dejes de probarla.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'fr', $t$ L'application vient de sortir, alors n'hésitez pas à l'essayer.$t$, $t$ L'application est disponible sur Google Play (Android) et sur l'App Store (iPhone), alors n'hésitez pas à l'essayer.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'nl', $t$ De app komt net uit, dus zeker proberen.$t$, $t$ De app is beschikbaar op Google Play (Android) en in de App Store (iPhone), dus zeker proberen.$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'pl', $t$ Aplikacja właśnie się pojawia, więc koniecznie ją wypróbuj.$t$, $t$ Aplikacja jest dostępna w Google Play (Android) i w App Store (iPhone), więc koniecznie ją wypróbuj.$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'cs', $t$Online platební kartou – zaplatíš přímo v rezervačním formuláři nebo v naší aplikaci. Nově podporujeme také platby SEPA na náš bankovní účet nebo přes QR kód (tato možnost jde pouze přes web, v aplikaci lze platit pouze kartou).$t$, $t$Online platební kartou, přes Apple Pay nebo Google Pay – zaplatíš přímo v rezervačním formuláři na webu nebo v naší aplikaci (v aplikaci na iPhonu i přes Apple Pay, na Androidu i přes Google Pay). Nově podporujeme také platby SEPA na náš bankovní účet nebo přes QR kód (tato možnost jde pouze přes web, v aplikaci se platí kartou, Apple Pay nebo Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'en', $t$Online by credit card – you can pay directly in the booking form or in our app. We now also support SEPA transfers to our bank account or via QR code (this option is only available via web, in the app you can only pay by card).$t$, $t$Online by card, Apple Pay or Google Pay – you can pay directly in the booking form on our website or in our app (in the iPhone app also with Apple Pay, in the Android app also with Google Pay). We now also support SEPA transfers to our bank account or via QR code (this option is only available on the website; in the app you pay by card, Apple Pay or Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'de', $t$Online mit Kreditkarte – bezahle direkt im Buchungsformular oder in unserer App. Wir unterstützen jetzt auch SEPA-Zahlungen auf unser Bankkonto oder per QR-Code (diese Option ist nur über die Website verfügbar, in der App können Sie nur mit Karte bezahlen).$t$, $t$Online mit Karte, Apple Pay oder Google Pay – bezahle direkt im Buchungsformular auf der Website oder in unserer App (in der iPhone-App auch per Apple Pay, in der Android-App auch per Google Pay). Wir unterstützen jetzt auch SEPA-Zahlungen auf unser Bankkonto oder per QR-Code (diese Option ist nur über die Website verfügbar; in der App zahlst du mit Karte, Apple Pay oder Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'es', $t$Tarjeta de crédito online – pagas directamente en el formulario de reserva o en nuestra aplicación. Ahora también soportamos pagos SEPA a nuestra cuenta bancaria o a través de código QR (esta opción solo está disponible en web, en la aplicación solo se puede pagar con tarjeta).$t$, $t$Online con tarjeta, Apple Pay o Google Pay – pagas directamente en el formulario de reserva de la web o en nuestra aplicación (en la app para iPhone también con Apple Pay, en la app para Android también con Google Pay). Ahora también admitimos pagos SEPA a nuestra cuenta bancaria o mediante código QR (esta opción solo está disponible en la web; en la aplicación se paga con tarjeta, Apple Pay o Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'fr', $t$Paiement en ligne par carte bancaire – tu peux payer directement dans le formulaire de réservation ou dans notre application. Nous supportons également les virements SEPA vers notre compte bancaire ou via code QR (cette option n'est disponible que sur le web, l'application ne permet que le paiement par carte).$t$, $t$Paiement en ligne par carte bancaire, Apple Pay ou Google Pay – tu peux payer directement dans le formulaire de réservation sur le site ou dans notre application (dans l'application iPhone aussi avec Apple Pay, dans l'application Android aussi avec Google Pay). Nous acceptons également les virements SEPA vers notre compte bancaire ou via code QR (cette option n'est disponible que sur le site ; dans l'application, tu paies par carte, Apple Pay ou Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'nl', $t$Online betaalkaar – je betaalt direct in het reserveringsformulier of in onze app. We ondersteunen ook SEPA-betalingen naar onze bankrekening of via QR-code (deze optie is alleen via de website, in de app kun je alleen met kaart betalen).$t$, $t$Online met je betaalkaart, Apple Pay of Google Pay – je betaalt direct in het reserveringsformulier op de website of in onze app (in de iPhone-app ook met Apple Pay, in de Android-app ook met Google Pay). We ondersteunen ook SEPA-betalingen naar onze bankrekening of via QR-code (deze optie is alleen via de website; in de app betaal je met kaart, Apple Pay of Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'pl', $t$Online kartą płatniczą – zapłacisz bezpośrednio w formularzu rezerwacji lub w naszej aplikacji. Teraz obsługujemy również płatności SEPA na nasze konto bankowe lub za pośrednictwem kodu QR (ta opcja jest dostępna tylko przez stronę internetową, w aplikacji można płacić wyłącznie kartą).$t$, $t$Online kartą płatniczą, Apple Pay lub Google Pay – zapłacisz bezpośrednio w formularzu rezerwacji na stronie lub w naszej aplikacji (w aplikacji na iPhone'a także przez Apple Pay, na Androida także przez Google Pay). Obsługujemy również płatności SEPA na nasze konto bankowe lub za pośrednictwem kodu QR (ta opcja jest dostępna tylko przez stronę internetową; w aplikacji płacisz kartą, Apple Pay lub Google Pay).$t$),
    ('c54ab426-5f9e-499a-b4fd-6d0905ee42ef', 'uk', $t$Онлайн платіжною карткою – ви сплачуєте прямо в формі бронювання або в нашій програмі. Ми також нововводимо платежі SEPA на наш банківський рахунок або через QR-код (ця опція доступна лише через веб-сайт, у програмі можна платити лише карткою).$t$, $t$Онлайн платіжною карткою, Apple Pay або Google Pay – ви сплачуєте прямо у формі бронювання на сайті або в нашій програмі (у програмі для iPhone також через Apple Pay, для Android також через Google Pay). Ми також приймаємо платежі SEPA на наш банківський рахунок або через QR-код (ця опція доступна лише через веб-сайт; у програмі ви платите карткою, Apple Pay або Google Pay).$t$)
    ) AS v(id, lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items
         SET answer = replace(answer, f.old_txt, f.new_txt)
       WHERE id = f.id::uuid
         AND strpos(answer, f.old_txt) > 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(
               translations,
               ARRAY[f.lang, 'answer'],
               to_jsonb(replace(translations -> f.lang ->> 'answer', f.old_txt, f.new_txt)))
       WHERE id = f.id::uuid
         AND strpos(coalesce(translations -> f.lang ->> 'answer', ''), f.old_txt) > 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
    IF cnt = 0 THEN
      RAISE NOTICE 'faq % [%]: zastaralá věta nenalezena (už opraveno / upraveno ve Velíně) — přeskočeno', f.id, f.lang;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_items: opraveno % textových úseků', n_upd;
END
$$;
