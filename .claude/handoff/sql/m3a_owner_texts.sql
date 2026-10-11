-- =============================================================================
-- m3a_owner_texts.sql — DATOVÁ migrace (bez změn schématu). NÁVRH, NEAPLIKOVÁNO.
--
-- Zadání majitele 2026-10-11 (doslova): „Mytí ani tankování není třeba na obslužné
-- pobočce. Na samoobsluze není potřeba tankovat. Důležité je pouze, aby motorka byla
-- umytá a nesvítila rezerva.“
--   Mezná u Pelhřimova (obslužná, i vrácení na sjednaném místě) = bez mytí, bez tankování.
--   Velké Němčice u Brna (samoobslužná) = plná nádrž netřeba, ALE umytá + nesvítí rezerva.
-- Dále schválené texty: aplikace i v App Store (iPhone), krok 3 na úvodní stránce
-- (Mezná / samoobsluha Velké Němčice, přistavení z Mezné) a překlady banneru.
--
-- Co mění (jen texty pro zákazníky; cs + en de es fr nl pl uk):
--  1) cms_variables (Velín CMS — má na webu přednost před PHP i lang soubory):
--     web.pujcovna.faq.items.0.a, web.home.process.steps.2.text/.title,
--     web.jak_pujcit_dokumenty.payments.rows.2.1, web.jak_pujcit_postup.process.steps.11.text,
--     web.jak_pujcit_vraceni_pujcovna.cta.text
--  2) faq_items e6df7d9f (Musím vracet s plnou nádrží a čistou?) a 02b6cfc8 (Jaké palivo
--     mám tankovat?) — čte je i AI (get_faq); uk doplněno
--  3) app_settings pages_overlay.<stránka>.<jazyk> — auto-překlady PHP textů, které mají
--     přednost před lang/pages_<jazyk>.php: list se nastaví na nový text z lang souborů
--  4) app_settings header_banner — translations {lang: text} + translations_src
--     (sha1 hex českého textu; web i appka překlad použijí jen když sedí)
--
-- Bezpečnost: mění se JEN text, který je ve stavu ověřeném proti živým datům 2026-10-11
-- (celá věta / přesná fráze). Co mezitím někdo upravil ve Velíně, se přeskočí s NOTICE.
-- Překlady se mění jen když česká hodnota řádku už obsahuje nový text (žádný nesoulad cs×překlad).
-- Idempotentní (druhý běh nic nezmění). Bez BEGIN/COMMIT — deploy běží v jedné transakci.
-- Web: cache dat 30 min + stránek 10 min → projeví se nejpozději do ~40 min.
-- =============================================================================

-- 1) cms_variables ------------------------------------------------------------
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_nogate boolean;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ($t$web.pujcovna.faq.items.0.a$t$, $t$cs$t$, $t$která je zdarma ke stažení na Google Play (dostupná pro Android).$t$, $t$která je zdarma ke stažení na Google Play (Android) i v App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$en$t$, $t$which is free to download on Google Play (available for Android).$t$, $t$which is free to download on Google Play (Android) and the App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$de$t$, $t$die im Google Play Store (verfügbar für Android) heruntergeladen werden kann.$t$, $t$die bei Google Play (Android) und im App Store (iPhone) heruntergeladen werden kann.$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$es$t$, $t$que está disponible de forma gratuita en Google Play (disponible para Android).$t$, $t$que está disponible de forma gratuita en Google Play (Android) y en la App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$fr$t$, $t$qui est gratuite à télécharger sur Google Play (disponible pour Android).$t$, $t$qui est gratuite à télécharger sur Google Play (Android) et sur l'App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$nl$t$, $t$die beschikbaar is in Google Play (beschikbaar voor Android).$t$, $t$die beschikbaar is in Google Play (Android) en in de App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$pl$t$, $t$którą można bezpłatnie pobrać z Google Play (dostępna na Androida).$t$, $t$którą można bezpłatnie pobrać z Google Play (Android) i z App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.pujcovna.faq.items.0.a$t$, $t$uk$t$, $t$який можна безплатно завантажити на Google Play (доступний для Android).$t$, $t$який можна безплатно завантажити з Google Play (Android) та App Store (iPhone).$t$, $t$Google Play (Android) i v App Store (iPhone)$t$),
    ($t$web.home.process.steps.2.text$t$, $t$cs$t$, $t$Převezmi si motorku v naší půjčovně u Pelhřimova, nebo využij přistavení motorky kamkoliv v ČR.$t$, $t$Převezmi si motorku v naší půjčovně v Mezné u Pelhřimova, nebo si ji vyzvedni na samoobslužné pobočce ve Velkých Němčicích u Brna. Z Mezné můžeš využít i přistavení motorky kamkoliv v ČR.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$en$t$, $t$Pick up a motorcycle at our rental shop near Pelhřimov, or use our delivery service anywhere in the Czech Republic.$t$, $t$Pick up your bike at our rental shop in Mezná near Pelhřimov, or collect it at our self-service branch in Velké Němčice near Brno. From Mezná, you can also have the bike delivered anywhere in the Czech Republic.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$de$t$, $t$Miete ein Motorrad in unserer Vermietungsstation bei Pelhřimov oder nutze unseren Lieferservice überall in der ČR.$t$, $t$Hol dein Motorrad in unserer Vermietung in Mezná bei Pelhřimov ab oder an unserer Selbstbedienungsfiliale in Velké Němčice bei Brno. Von Mezná aus kannst du es dir auch überallhin in Tschechien liefern lassen.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$es$t$, $t$Recoge la motocicleta en nuestro alquiler cerca de Pelhřimova, o utiliza el servicio de entrega de motocicletas en cualquier lugar de la República Checa.$t$, $t$Recoge la moto en nuestro alquiler de Mezná, cerca de Pelhřimov, o en nuestra sucursal de autoservicio de Velké Němčice, cerca de Brno. Desde Mezná también podemos llevarte la moto a cualquier lugar de la República Checa.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$fr$t$, $t$Loue une moto à notre agence près de Pelhřimova, ou utilise la livraison de moto n'importe où en Tchéquie.$t$, $t$Récupère ta moto à notre agence de Mezná, près de Pelhřimov, ou à notre agence en libre-service de Velké Němčice, près de Brno. Depuis Mezná, tu peux aussi te faire livrer la moto n'importe où en Tchéquie.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$nl$t$, $t$Haal je motor op bij onze verhuurlocatie bij Pelhřimov, of maak gebruik van motorbezorging overal in Tsjechië.$t$, $t$Haal je motor op bij onze verhuur in Mezná bij Pelhřimov, of bij onze zelfbedieningsvestiging in Velké Němčice bij Brno. Vanuit Mezná kun je de motor ook overal in Tsjechië laten bezorgen.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$pl$t$, $t$Odbiór motocykla w naszej wypożyczalni koło Pelhřimova lub skorzystaj z dostawy motocykla w dowolne miejsce w Czechach.$t$, $t$Odbierz motocykl w naszym oddziale Mezná koło Pelhřimova albo w samoobsługowym oddziale Velké Němčice koło Brna. Z oddziału Mezná możesz też zamówić dostawę motocykla w dowolne miejsce w Czechach.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.text$t$, $t$uk$t$, NULL, $t$Забери мотоцикл у нашому прокаті в Mezná біля Пельгржимова або у філії самообслуговування Velké Němčice біля Брна. З Mezná можеш скористатися й доставкою мотоцикла будь-куди в Чехії.$t$, $t$samoobslužné pobočce ve Velkých Němčicích u Brna$t$),
    ($t$web.home.process.steps.2.title$t$, $t$en$t$, $t$3. I'll take it$t$, $t$3. Pick up$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$de$t$, $t$3. Ich werde abholen$t$, $t$3. Abholen$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$es$t$, $t$3. Me haré cargo$t$, $t$3. Recógela$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$fr$t$, $t$3. Je reprendrai$t$, $t$3. Récupère$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$nl$t$, $t$3. Ik zal overnemen$t$, $t$3. Ophalen$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$pl$t$, $t$3. Przejmu$t$, $t$3. Odbierz$t$, $t$3. Převezmi$t$),
    ($t$web.home.process.steps.2.title$t$, $t$uk$t$, NULL, $t$3. Забери$t$, $t$3. Převezmi$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$cs$t$, $t$Vrácení bez povinnosti dotankovat a mýt.$t$, $t$V Mezné a při vrácení jinde bez povinnosti dotankovat a mýt. Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy (plná nádrž není nutná).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$en$t$, $t$Return without obligation to refuel and wash.$t$, $t$In Mezná and when returning elsewhere, no need to refuel or wash the bike. At the self-service branch, return it washed and with the reserve light off (no full tank needed).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$de$t$, $t$Rückgabe ohne Verpflichtung zu tanken und zu waschen.$t$, $t$In Mezná und bei Rückgabe an einem anderen Ort musst du das Motorrad weder tanken noch waschen. An der Selbstbedienungsfiliale bring es gewaschen zurück, ohne dass die Reserveleuchte leuchtet (volltanken musst du nicht).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$es$t$, $t$Devolución sin obligación de repostar ni lavar.$t$, $t$En Mezná y si la devuelves en otro lugar, no tienes que repostar ni lavar la moto. En la sucursal de autoservicio, cerca de Brno, devuélvela lavada y sin el testigo de reserva encendido (no hace falta el depósito lleno).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$fr$t$, $t$Retour sans obligation de faire le plein et de laver.$t$, $t$À Mezná et en cas de restitution ailleurs, tu n'as ni à faire le plein ni à laver la moto. À l'agence en libre-service, rends-la lavée et sans voyant de réserve allumé (le plein n'est pas nécessaire).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$nl$t$, $t$Retourneren zonder verplichting om bij te tanken en schoon te maken.$t$, $t$In Mezná en bij teruggave op een andere plek hoef je niet te tanken of te wassen. Bij de zelfbedieningsvestiging lever je de motor gewassen in en zonder brandend reservelampje (een volle tank is niet nodig).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$pl$t$, $t$Zwrot bez obowiązku tankowania i mycia.$t$, $t$W oddziale Mezná i przy zwrocie w innym miejscu bez obowiązku tankowania i mycia. W oddziale samoobsługowym oddaj motocykl umyty i bez świecącej kontrolki rezerwy (pełny bak nie jest potrzebny).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_dokumenty.payments.rows.2.1$t$, $t$uk$t$, NULL, $t$У Mezná та при поверненні в іншому місці – без обов’язку заправляти й мити. У філії самообслуговування поверни мотоцикл вимитим і так, щоб не світився індикатор резерву (повний бак не потрібен).$t$, $t$Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$cs$t$, $t$Nemusíš tankovat ani mýt.$t$, $t$Nemusíš tankovat ani mýt – jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$en$t$, $t$You don't need to refuel or wash it.$t$, $t$You don't need to refuel or wash it – only at the self-service branch in Velké Němčice, return it washed and with the reserve light off.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$de$t$, $t$Du musst es nicht tanken oder waschen.$t$, $t$Du musst es nicht tanken oder waschen – nur an der Selbstbedienungsfiliale in Velké Němčice bring es gewaschen und ohne leuchtende Reserveanzeige zurück.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$es$t$, $t$No necesitas llenar el depósito ni lavar la moto.$t$, $t$No necesitas llenar el depósito ni lavar la moto; solo en la sucursal de autoservicio de Velké Němčice devuélvela lavada y sin la luz de reserva encendida.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$fr$t$, $t$Tu n'as pas besoin de faire le plein ni de la laver.$t$, $t$Tu n'as pas besoin de faire le plein ni de la laver – seulement à l'agence en libre-service de Velké Němčice, rends-la lavée et sans voyant de réserve allumé.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$nl$t$, $t$Je hoeft niet te tanken of te wassen.$t$, $t$Je hoeft niet te tanken of te wassen – alleen bij de zelfbedieningsvestiging in Velké Němčice lever je de motor gewassen in en zonder brandend reservelampje.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$pl$t$, $t$Nie musisz tankować ani myć.$t$, $t$Nie musisz tankować ani myć – tylko w samoobsługowym oddziale Velké Němčice oddaj motocykl umyty i bez świecącej kontrolki rezerwy.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_postup.process.steps.11.text$t$, $t$uk$t$, $t$Тобі не потрібно заправляти бензин чи мити мотоцикл.$t$, $t$Тобі не потрібно заправляти бензин чи мити мотоцикл – лише у філії самообслуговування Velké Němčice поверни його вимитим і так, щоб не світився індикатор резерву.$t$, $t$jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$cs$t$, $t$Bez kauce, bez mytí, bez tankování.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$en$t$, $t$No deposit, no washing, no refueling.$t$, $t$No deposit, no refuelling – and in Mezná no washing either.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$de$t$, $t$Ohne Kaution, ohne Waschen, ohne Tanken.$t$, $t$Ohne Kaution, ohne Tanken – und in Mezná auch ohne Waschen.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$es$t$, $t$Sin depósito, sin lavado, sin repostar.$t$, $t$Sin depósito, sin repostar y, en Mezná, también sin lavado.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$fr$t$, $t$Sans dépôt de garantie, sans lavage, sans carburant.$t$, $t$Sans dépôt de garantie, sans faire le plein – et à Mezná, sans lavage non plus.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$nl$t$, $t$Geen borg, geen schoonmaak, geen tankstation.$t$, $t$Geen borg, niet tanken – en in Mezná ook niet wassen.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$pl$t$, $t$Bez kaucji, bez mycia, bez tankowania.$t$, $t$Bez kaucji, bez tankowania, a w oddziale Mezná także bez mycia.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$),
    ($t$web.jak_pujcit_vraceni_pujcovna.cta.text$t$, $t$uk$t$, $t$Без застави, без миття, без заправлення.$t$, $t$Без застави, без заправлення, а в Mezná ще й без миття.$t$, $t$Bez kauce, bez tankování, v Mezné i bez mytí.$t$)
    ) AS x(k, lang, old_txt, new_txt, gate)
    ORDER BY (x.lang <> 'cs')            -- čeština první (překlady se řídí branou gate)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(replace(value #>> '{}', f.old_txt, f.new_txt)), updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.old_txt) > 0
         AND strpos(value #>> '{}', f.new_txt) = 0;
    ELSIF f.old_txt IS NULL THEN         -- jazyk chybí → doplnit
      UPDATE public.cms_variables
         SET translations = jsonb_set(coalesce(translations, '{}'::jsonb), ARRAY[f.lang],
                                      jsonb_build_object('value', f.new_txt)),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.gate) > 0
         AND coalesce(translations -> f.lang ->> 'value', '') = '';
    ELSE
      UPDATE public.cms_variables
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'value'],
                                      to_jsonb(replace(translations -> f.lang ->> 'value', f.old_txt, f.new_txt))),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.gate) > 0
         AND strpos(translations -> f.lang ->> 'value', f.old_txt) > 0
         AND strpos(translations -> f.lang ->> 'value', f.new_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT CASE WHEN f.lang = 'cs' THEN value #>> '{}' ELSE translations -> f.lang ->> 'value' END,
             f.lang <> 'cs' AND strpos(coalesce(value #>> '{}', ''), f.gate) = 0
        INTO v_cur, v_nogate FROM public.cms_variables WHERE key = f.k;
      IF strpos(coalesce(v_cur, ''), f.new_txt) > 0 THEN
        n_done := n_done + 1;
      ELSIF v_nogate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a cms_variables % [%] PŘESKOČENO — česká hodnota řádku nebyla změněna, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a cms_variables % [%] PŘESKOČENO — text ve Velíně mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a cms_variables: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 2) faq_items ------------------------------------------------------------------
-- updated_at nastaví trigger faq_items_set_updated_at.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_nogate boolean;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$cs$t$, $t$Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.$t$, $t$Ne. V Mezné u Pelhřimova i při vrácení na domluveném místě netankuješ ani nemyješ. Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ – jen motorku vrať umytou a hlídej, aby nesvítila rezerva.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$en$t$, $t$No. With us, you don't fill up or wash. Just make sure the reserve light isn't on.$t$, $t$No. In Mezná near Pelhřimov, and when you return the bike at an agreed place, you don't refuel or wash it. At the self-service branch in Velké Němčice near Brno you don't need a full tank either – just return the bike washed and make sure the reserve light isn't on.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$de$t$, $t$Nein. Bei uns tankst du nicht und wäschst nicht. Achte nur darauf, dass die Reserveanzeige nicht leuchtet.$t$, $t$Nein. In Mezná bei Pelhřimov und bei der Rückgabe an einem vereinbarten Ort musst du weder tanken noch waschen. An der Selbstbedienungsfiliale in Velké Němčice bei Brno musst du auch nicht volltanken – bring das Motorrad nur gewaschen zurück und achte darauf, dass die Reserveanzeige nicht leuchtet.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$es$t$, $t$No. Con nosotros no repostas ni lavas. Solo asegúrate de que no se encienda la luz de reserva.$t$, $t$No. En Mezná, cerca de Pelhřimov, y si devuelves la moto en un lugar acordado, no tienes que repostar ni lavarla. En la sucursal de autoservicio de Velké Němčice, cerca de Brno, tampoco hace falta el depósito lleno: solo devuelve la moto lavada y asegúrate de que no esté encendida la luz de reserva.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$fr$t$, $t$Non. Chez nous, tu ne fais ni le plein ni le nettoyage. Juste veille à ce que la réserve ne s'allume pas.$t$, $t$Non. À Mezná, près de Pelhřimov, et si tu rends la moto à un endroit convenu, tu n'as ni à faire le plein ni à la laver. À l'agence en libre-service de Velké Němčice, près de Brno, le plein n'est pas nécessaire non plus : rends simplement la moto lavée et veille à ce que le voyant de réserve ne soit pas allumé.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$nl$t$, $t$Nee. Bij ons tank je niet en was je niet. Let alleen op dat het reservelampje niet brandt.$t$, $t$Nee. In Mezná bij Pelhřimov en bij teruggave op een afgesproken plek hoef je niet te tanken of te wassen. Bij de zelfbedieningsvestiging in Velké Němčice bij Brno hoeft de tank ook niet vol – lever de motor alleen gewassen in en let erop dat het reservelampje niet brandt.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$pl$t$, $t$Nie. U nas nie tankujesz ani nie myjesz. Tylko pilnuj, żeby się nie zapalała rezerwa.$t$, $t$Nie. W oddziale Mezná koło Pelhřimova i przy zwrocie w umówionym miejscu nie tankujesz ani nie myjesz. W samoobsługowym oddziale Velké Němčice koło Brna pełny bak też nie jest potrzebny – oddaj tylko motocykl umyty i pilnuj, żeby nie świeciła się kontrolka rezerwy.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$question$t$, $t$uk$t$, NULL, $t$Чи маю повертати мотоцикл з повним баком і чистим?$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63$t$, $t$answer$t$, $t$uk$t$, NULL, $t$Ні. У Mezná біля Пельгржимова і при поверненні в узгодженому місці ти не заправляєш і не миєш мотоцикл. У філії самообслуговування Velké Němčice біля Брна повний бак теж не потрібен – лише поверни мотоцикл вимитим і стеж, щоб не світився індикатор резерву.$t$, $t$Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$cs$t$, $t$Při vrácení nemusíš mít plnou nádrž, jen ať nesvítí kontrolka rezervy.$t$, $t$Při vrácení nemusíš mít plnou nádrž: v Mezné u Pelhřimova netankuješ vůbec, na samoobslužné pobočce ve Velkých Němčicích u Brna jen hlídej, aby nesvítila kontrolka rezervy.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$en$t$, $t$When returning the bike, you don't need to have a full tank, just make sure the reserve light isn't on.$t$, $t$When returning the bike, you don't need a full tank: in Mezná near Pelhřimov you don't refuel at all, and at the self-service branch in Velké Němčice near Brno just make sure the reserve light isn't on.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$de$t$, $t$Bei der Rückgabe musst du den Tank nicht vollständig gefüllt haben, nur die Reserveanzeige darf nicht leuchten.$t$, $t$Bei der Rückgabe muss der Tank nicht voll sein: In Mezná bei Pelhřimov musst du gar nicht tanken, an der Selbstbedienungsfiliale in Velké Němčice bei Brno achte nur darauf, dass die Reserveanzeige nicht leuchtet.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$es$t$, $t$Al devolver la moto no necesitas tener el depósito lleno, solo que no se encienda la luz de reserva.$t$, $t$Al devolver la moto no necesitas el depósito lleno: en Mezná, cerca de Pelhřimov, no tienes que repostar en absoluto, y en la sucursal de autoservicio de Velké Němčice, cerca de Brno, solo asegúrate de que no esté encendida la luz de reserva.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$fr$t$, $t$Au retour, tu n'as pas besoin d'avoir un réservoir plein, il suffit que le témoin de réserve ne s'allume pas.$t$, $t$Au retour, tu n'as pas besoin d'un réservoir plein : à Mezná, près de Pelhřimov, tu n'as pas du tout à faire le plein, et à l'agence en libre-service de Velké Němčice, près de Brno, veille simplement à ce que le témoin de réserve ne soit pas allumé.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$nl$t$, $t$Bij retournering hoef je niet met een volle tank terug te komen, zolang het reservelampje maar niet brandt.$t$, $t$Bij het terugbrengen hoeft de tank niet vol te zijn: in Mezná bij Pelhřimov hoef je helemaal niet te tanken, en bij de zelfbedieningsvestiging in Velké Němčice bij Brno let je er alleen op dat het reservelampje niet brandt.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$pl$t$, $t$Przy zwracaniu nie musisz mieć pełnego baku, tylko żeby nie świeciła się lampka rezerwy.$t$, $t$Przy zwrocie nie musisz mieć pełnego baku: w oddziale Mezná koło Pelhřimova w ogóle nie tankujesz, a w samoobsługowym oddziale Velké Němčice koło Brna pilnuj tylko, żeby nie świeciła się lampka rezerwy.$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$question$t$, $t$uk$t$, NULL, $t$Яке пальне мені заправляти?$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$),
    ($t$02b6cfc8-83af-4887-8f5f-a62214f64f2a$t$, $t$answer$t$, $t$uk$t$, NULL, $t$<p>Завжди пальне, <strong>передбачене виробником</strong> конкретного мотоцикла – знайдеш його в посібнику користувача, зазвичай і біля кришки бака (у наших мотоциклів це зазвичай бензин Natural 95). Якщо заправиш неправильне пальне, орендар у повному обсязі оплачує всі витрати на відкачування пального й ремонт двигуна. Під час повернення повний бак не потрібен: у Mezná біля Пельгржимова взагалі не заправляєш, а у філії самообслуговування Velké Němčice біля Брна лише стеж, щоб не світився індикатор резерву.</p>$t$, $t$v Mezné u Pelhřimova netankuješ vůbec$t$)
    ) AS x(id, field, lang, old_txt, new_txt, gate)
    ORDER BY (x.lang <> 'cs')
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items
         SET answer   = CASE WHEN f.field = 'answer'   THEN replace(answer,   f.old_txt, f.new_txt) ELSE answer END,
             question = CASE WHEN f.field = 'question' THEN replace(question, f.old_txt, f.new_txt) ELSE question END
       WHERE id = f.id::uuid
         AND strpos(CASE f.field WHEN 'answer' THEN answer ELSE question END, f.old_txt) > 0
         AND strpos(CASE f.field WHEN 'answer' THEN answer ELSE question END, f.new_txt) = 0;
    ELSIF f.old_txt IS NULL THEN         -- jazyk chybí → doplnit
      UPDATE public.faq_items
         SET translations = jsonb_set(coalesce(translations, '{}'::jsonb), ARRAY[f.lang],
                                      coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object(f.field, f.new_txt))
       WHERE id = f.id::uuid
         AND strpos(answer, f.gate) > 0
         AND coalesce(translations -> f.lang ->> f.field, '') = '';
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, f.field],
                                      to_jsonb(replace(translations -> f.lang ->> f.field, f.old_txt, f.new_txt)))
       WHERE id = f.id::uuid
         AND strpos(answer, f.gate) > 0
         AND strpos(translations -> f.lang ->> f.field, f.old_txt) > 0
         AND strpos(translations -> f.lang ->> f.field, f.new_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT CASE WHEN f.lang = 'cs' THEN (CASE f.field WHEN 'answer' THEN answer ELSE question END)
                  ELSE translations -> f.lang ->> f.field END,
             f.lang <> 'cs' AND strpos(answer, f.gate) = 0
        INTO v_cur, v_nogate FROM public.faq_items WHERE id = f.id::uuid;
      IF strpos(coalesce(v_cur, ''), f.new_txt) > 0 THEN
        n_done := n_done + 1;
      ELSIF v_nogate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a faq_items % % [%] PŘESKOČENO — česká odpověď nebyla změněna, překlad ponechán', f.id, f.field, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a faq_items % % [%] PŘESKOČENO — text ve Velíně mezitím změněn: %', f.id, f.field, f.lang, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a faq_items: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 3) app_settings pages_overlay (cizí jazyky stránek Jak si půjčit) -------------
-- Listy jsou v polích (seznamech), která web přebírá celá → mění se jen daný list.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$en$t$, $t${faq,items,1,a}$t$, $t$No. You don't refuel or wash with us. Just make sure the reserve isn't on.&nbsp;$t$, $t$No. In Mezná you don't refuel or wash the bike. At the self-service branch in Velké Němčice you don't need a full tank either – just return the bike washed and make sure the reserve light isn't on.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$de$t$, $t${faq,items,1,a}$t$, $t$Nein. Bei uns musst du nicht tanken oder waschen. Achte nur darauf, dass die Reserve nicht leuchtet.&nbsp;$t$, $t$Nein. In Mezná musst du weder tanken noch waschen. An der Selbstbedienungsfiliale in Velké Němčice musst du auch nicht volltanken – bring das Motorrad nur gewaschen zurück und achte darauf, dass die Reserveleuchte nicht leuchtet.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$es$t$, $t${faq,items,1,a}$t$, $t$No. En nuestro lugar no cargas gasolina ni lavas. Solo asegúrate de que no se encienda la reserva.&nbsp;$t$, $t$No. En Mezná no tienes que repostar ni lavarla. En la sucursal de autoservicio de Velké Němčice tampoco hace falta el depósito lleno: solo devuelve la moto lavada y procura que no esté encendido el testigo de reserva.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$fr$t$, $t${faq,items,1,a}$t$, $t$Non. Chez nous, tu ne fais pas le plein et tu ne laves pas. Assure-toi juste que la réserve ne s'allume pas.&nbsp;$t$, $t$Non. À Mezná, tu n'as ni à faire le plein ni à laver la moto. À l'agence en libre-service de Velké Němčice, le plein n'est pas nécessaire non plus : rends simplement la moto lavée et veille à ce que le voyant de réserve ne soit pas allumé.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$nl$t$, $t${faq,items,1,a}$t$, $t$Nee. Bij ons hoef je niet te tanken of te wassen. Let er alleen op dat de reservelamp niet brandt.&nbsp;$t$, $t$Nee. In Mezná hoef je niet te tanken of te wassen. Bij de zelfbedieningsvestiging in Velké Němčice hoeft de tank ook niet vol – lever de motor alleen gewassen in en let erop dat het reservelampje niet brandt.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_pujcovna$t$, $t$pl$t$, $t${faq,items,1,a}$t$, $t$Nie. U nas nie tankujesz ani nie myjesz. Tylko pamiętaj, aby nie świeciła rezerwa.&nbsp;$t$, $t$Nie. W oddziale Mezná nie tankujesz ani nie myjesz. W samoobsługowym oddziale Velké Němčice pełny bak też nie jest potrzebny – oddaj tylko motocykl umyty i pilnuj, żeby nie świeciła kontrolka rezerwy.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$en$t$, $t${faq,items,1,a}$t$, $t$No. With us, you don't fuel up or wash it. Just make sure the reserve light isn't on.&nbsp;$t$, $t$No. When you return the bike elsewhere, you don't refuel or wash it.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$de$t$, $t${faq,items,1,a}$t$, $t$Nein. Bei uns tankst und wäschst du nicht. Achte nur darauf, dass die Reserve nicht leuchtet.&nbsp;$t$, $t$Nein. Bei der Rückgabe an einem anderen Ort musst du weder tanken noch waschen.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$es$t$, $t${faq,items,1,a}$t$, $t$No. Con nosotros no repostas ni lavas. Solo asegúrate de que no se encienda la reserva.&nbsp;$t$, $t$No. Si la devuelves en otro lugar, no tienes que repostar ni lavarla.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$fr$t$, $t${faq,items,1,a}$t$, $t$Non. Chez nous, tu n'as pas besoin de faire le plein ni de laver la moto. Juste veille à ce que la réserve ne s'allume pas.&nbsp;$t$, $t$Non. Si tu la rends ailleurs, tu n'as ni à faire le plein ni à laver la moto.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$nl$t$, $t${faq,items,1,a}$t$, $t$Nee. Bij ons tank je niet en was je niet. Let er alleen op dat de reserve niet brandt.&nbsp;$t$, $t$Nee. Bij teruggave op een andere plek hoef je niet te tanken of te wassen.&nbsp;$t$),
    ($t$jak_pujcit_vraceni_jinde$t$, $t$pl$t$, $t${faq,items,1,a}$t$, $t$Nie. U nas nie tankowujesz ani nie myjesz. Tylko pamiętaj, aby nie świeciła rezerwa.&nbsp;$t$, $t$Nie. Przy zwrocie w innym miejscu nie tankujesz ani nie myjesz.&nbsp;$t$),
    ($t$jak_pujcit_postup$t$, $t$en$t$, $t${process,steps,11,text}$t$, $t$Return the bike on time – in person to our shop in Pelhřimov, or to an agreed location. You don't need to fill up or wash it.$t$, $t$Return the bike on time – in person at our branch in Pelhřimov, or at a place agreed in advance; no need to refuel or wash it. At the self-service branch in Velké Němčice, return it washed and with the reserve light off.$t$),
    ($t$jak_pujcit_postup$t$, $t$de$t$, $t${process,steps,11,text}$t$, $t$Gib das Motorrad pünktlich zurück – persönlich in der Motorradverleih in Pelhřimov oder an einem zuvor vereinbarten Ort. Du musst nicht tanken oder waschen.$t$, $t$Bring das Motorrad pünktlich zurück – persönlich in unsere Filiale in Pelhřimov oder an einen vorher vereinbarten Ort; tanken und waschen musst du nicht. An der Selbstbedienungsfiliale in Velké Němčice bring es gewaschen zurück, ohne dass die Reserveleuchte leuchtet.$t$),
    ($t$jak_pujcit_postup$t$, $t$es$t$, $t${process,steps,11,text}$t$, $t$Devuelve la motocicleta a tiempo – en persona al alquiler en Pelhřimov, o en el lugar acordado previamente. No necesitas llenarla de gasolina ni limpiarla.$t$, $t$Devuelve la moto a tiempo: en persona en nuestra sucursal de Pelhřimov o en el lugar acordado previamente; no tienes que repostar ni lavarla. En la sucursal de autoservicio de Velké Němčice, devuélvela lavada y sin el testigo de reserva encendido.$t$),
    ($t$jak_pujcit_postup$t$, $t$fr$t$, $t${process,steps,11,text}$t$, $t$Retourne la moto à temps – personnellement à l'agence de location de Pelhřimov, ou au lieu convenu à l'avance. Tu n'as pas besoin de la faire le plein ni de la laver.$t$, $t$Rends la moto à l'heure – en personne à notre agence de Pelhřimov ou à un endroit convenu à l'avance ; pas besoin de faire le plein ni de la laver. À l'agence en libre-service de Velké Němčice, rends-la lavée et sans voyant de réserve allumé.$t$),
    ($t$jak_pujcit_postup$t$, $t$nl$t$, $t${process,steps,11,text}$t$, $t$Breng je motorfiets op tijd terug – persoonlijk naar het verhuurbedrijf in Pelhřimov, of naar een vooraf afgesproken plek. Je hoeft niet te tanken of schoon te maken.$t$, $t$Breng de motor op tijd terug – persoonlijk bij de verhuur in Pelhřimov, of op de afgesproken plek; tanken of wassen is niet nodig. Bij de zelfbedieningsvestiging in Velké Němčice lever je hem gewassen in en zonder brandend reservelampje.$t$),
    ($t$jak_pujcit_postup$t$, $t$pl$t$, $t${process,steps,11,text}$t$, $t$Zwróć motocykl na czas – osobiście do wypożyczalni w Pelhřimowie lub w wcześniej umówione miejsce. Nie musisz tankować ani myć.$t$, $t$Zwróć motocykl na czas – osobiście do wypożyczalni w Pelhřimovie albo na umówione miejsce; nie trzeba tankować ani myć. W samoobsługowym oddziale Velké Němčice oddaj go umytego i bez świecącej kontrolki rezerwy.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$en$t$, $t${handover,items,2}$t$, $t$<strong>Return</strong>&nbsp;anytime during the last day of rental (even at midnight). No need to wash or refuel.$t$, $t$<strong>Return</strong>&nbsp;any time on the last day of your rental (even at midnight). In Mezná there's no need to refuel or wash the bike; at the self-service branch, return it washed and with the reserve light off.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$de$t$, $t${handover,items,2}$t$, $t$<strong>Rückgabe</strong>&nbsp;jederzeit während des letzten Miet­tags (auch um Mitternacht). Es ist nicht erforderlich, zu waschen oder zu tanken.$t$, $t$Die <strong>Rückgabe</strong>&nbsp;ist jederzeit am letzten Miettag möglich (auch um Mitternacht). In Mezná musst du weder tanken noch waschen; an der Selbstbedienungsfiliale bring das Motorrad gewaschen zurück, ohne dass die Reserveleuchte leuchtet.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$es$t$, $t${handover,items,2}$t$, $t$<strong>La devolución</strong> en cualquier momento durante el último día del alquiler (incluso a medianoche). No es necesario limpiar ni repostar.$t$, $t$<strong>Devolución</strong>&nbsp;en cualquier momento del último día del alquiler (incluso a medianoche). En Mezná no tienes que repostar ni lavar la moto; en la sucursal de autoservicio, cerca de Brno, devuélvela lavada y sin el testigo de reserva encendido.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$fr$t$, $t${handover,items,2}$t$, $t$<strong>Retour</strong>&nbsp;à tout moment le dernier jour de la location (même à minuit). Aucune obligation de nettoyer ou de faire le plein.$t$, $t$La <strong>restitution</strong>&nbsp;est possible à toute heure le dernier jour de la location (même à minuit). À Mezná, pas besoin de faire le plein ni de laver la moto ; à l'agence en libre-service, rends-la lavée et sans voyant de réserve allumé.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$nl$t$, $t${handover,items,2}$t$, $t$<strong>Teruggave</strong>&nbsp;op elk moment gedurende de laatste verhuurdag (zelfs om middernacht). Niet nodig om schoon te maken of te tanken.$t$, $t$<strong>Teruggave</strong>&nbsp;op elk moment van de laatste huurdag (ook om middernacht). In Mezná is wassen of tanken niet nodig; bij de zelfbedieningsvestiging lever je de motor gewassen in en zonder brandend reservelampje.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$pl$t$, $t${handover,items,2}$t$, $t$<strong>Zwrot</strong>&nbsp;o każdej porze w ostatnim dniu wynajmu (nawet o północy). Nie trzeba myć ani tankować.$t$, $t$<strong>Zwrot</strong>&nbsp;o dowolnej porze w ostatnim dniu wynajmu (nawet o północy). W oddziale Mezná nie trzeba myć ani tankować; w oddziale samoobsługowym oddaj motocykl umyty i bez świecącej kontrolki rezerwy.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$en$t$, $t${payments,rows,2,1}$t$, $t$Return without obligation to refuel and wash. Any excessive dirt will be handled individually.$t$, $t$In Mezná and when returning elsewhere, no need to refuel or wash the bike. At the self-service branch, return it washed and with the reserve light off (no full tank needed). Excessive dirt is dealt with individually.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$de$t$, $t${payments,rows,2,1}$t$, $t$Rückgabe ohne Verpflichtung zu tanken und zu waschen. Bei übermäßiger Verschmutzung einigen wir uns individuell.$t$, $t$In Mezná und bei Rückgabe an einem anderen Ort musst du das Motorrad weder tanken noch waschen. An der Selbstbedienungsfiliale bring es gewaschen zurück, ohne dass die Reserveleuchte leuchtet (volltanken musst du nicht). Starke Verschmutzung klären wir individuell.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$es$t$, $t${payments,rows,2,1}$t$, $t$Devolución sin obligación de repostar y limpiar. Cualquier suciedad excesiva se resuelve individualmente.$t$, $t$En Mezná y si la devuelves en otro lugar, no tienes que repostar ni lavar la moto. En la sucursal de autoservicio, cerca de Brno, devuélvela lavada y sin el testigo de reserva encendido (no hace falta el depósito lleno). La suciedad excesiva se resuelve de forma individual.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$fr$t$, $t${payments,rows,2,1}$t$, $t$Retour sans obligation de faire le plein ou de nettoyer. Toute saleté excessive sera réglée individuellement.$t$, $t$À Mezná et en cas de restitution ailleurs, tu n'as ni à faire le plein ni à laver la moto. À l'agence en libre-service, rends-la lavée et sans voyant de réserve allumé (le plein n'est pas nécessaire). Une saleté excessive est réglée au cas par cas.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$nl$t$, $t${payments,rows,2,1}$t$, $t$Teruggave zonder verplichting tanken en schoonmaken. Eventuele buitensporige vervuiling behandelen we individueel.$t$, $t$In Mezná en bij teruggave op een andere plek hoef je niet te tanken of te wassen. Bij de zelfbedieningsvestiging lever je de motor gewassen in en zonder brandend reservelampje (een volle tank is niet nodig). Overmatig vuil wordt individueel afgehandeld.$t$),
    ($t$jak_pujcit_dokumenty$t$, $t$pl$t$, $t${payments,rows,2,1}$t$, $t$Zwrot bez obowiązku zatankowania i mycia. Wszelkie nadmierne zabrudzenie rozwiązujemy indywidualnie.$t$, $t$W oddziale Mezná i przy zwrocie w innym miejscu bez obowiązku tankowania i mycia. W oddziale samoobsługowym oddaj motocykl umyty i bez świecącej kontrolki rezerwy (pełny bak nie jest potrzebny). Nadmierne zabrudzenie rozpatrujemy indywidualnie.$t$)
    ) AS x(page, lang, path, old_txt, new_txt)
  LOOP
    UPDATE public.app_settings
       SET value = jsonb_set(value, f.path::text[], to_jsonb(f.new_txt), false), updated_at = now()
     WHERE key = 'pages_overlay.' || f.page || '.' || f.lang
       AND jsonb_typeof(value) = 'object'
       AND value #>> f.path::text[] = f.old_txt;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> f.path::text[] INTO v_cur FROM public.app_settings
       WHERE key = 'pages_overlay.' || f.page || '.' || f.lang;
      IF v_cur = f.new_txt THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a pages_overlay.%.% % PŘESKOČENO — text mezitím změněn: %', f.page, f.lang, f.path, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a pages_overlay: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 4) app_settings header_banner — překlady stávajícího českého textu ---------------
-- Přidá jen klíče translations + translations_src (enabled/text/bg/color zůstávají).
-- Jen když je text pořád tento a překlady k němu ještě nejsou (jinak NOTICE).
DO $$
DECLARE
  c_text constant text := $t$V zimním období od 1.11.2026 do 25.3.2027 zavřeno.$t$;
  v_tr constant jsonb := jsonb_build_object(
      'en', $t$Closed for the winter season from 1 November 2026 to 25 March 2027.$t$,
      'de', $t$In der Wintersaison vom 1. November 2026 bis 25. März 2027 geschlossen.$t$,
      'es', $t$Cerrado durante la temporada de invierno, del 1 de noviembre de 2026 al 25 de marzo de 2027.$t$,
      'fr', $t$Fermé pendant la saison d'hiver, du 1er novembre 2026 au 25 mars 2027.$t$,
      'nl', $t$Gesloten in het winterseizoen, van 1 november 2026 tot en met 25 maart 2027.$t$,
      'pl', $t$Nieczynne w sezonie zimowym, od 1 listopada 2026 do 25 marca 2027.$t$,
      'uk', $t$Зачинено на зимовий сезон: з 1 листопада 2026 до 25 березня 2027.$t$);
  v_val jsonb;
  cnt integer;
BEGIN
  UPDATE public.app_settings
     SET value = value || jsonb_build_object(
           'translations', v_tr,
           'translations_src', encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex')),
         updated_at = now()
   WHERE key = 'header_banner'
     AND jsonb_typeof(value) = 'object'
     AND value ->> 'text' = c_text
     AND (value ->> 'translations_src') IS DISTINCT FROM
         encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex');
  GET DIAGNOSTICS cnt = ROW_COUNT;
  IF cnt > 0 THEN
    RAISE NOTICE 'm3a header_banner: doplněny překlady (% jazyků)', (SELECT count(*) FROM jsonb_object_keys(v_tr));
  ELSE
    SELECT value INTO v_val FROM public.app_settings WHERE key = 'header_banner';
    RAISE NOTICE 'm3a header_banner: beze změny (text: %, translations_src: %)',
      left(coalesce(v_val ->> 'text', '∅'), 80), coalesce(v_val ->> 'translations_src', '∅');
  END IF;
END $$;
