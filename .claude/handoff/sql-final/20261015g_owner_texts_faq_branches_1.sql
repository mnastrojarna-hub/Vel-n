-- =============================================================================
-- 20261015g_owner_texts_faq_branches_1.sql
-- datová migrace (bez změn schématu): FAQ – vrácení jinde / osobní převzetí: co platí na samoobslužné pobočce (část 1/3).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- dac51062, 19b96b98, dd9c3286 (vrácení jinde) a 5c385d19 („Musím přijet osobně?“) popisovaly jen Meznou
-- a odporovaly FAQ e7079920 (motorky z Velkých Němčic se přebírají i vracejí jen na pobočce, převzetí
-- samoobslužně kódy). Doplněna jedna věta v češtině i ve všech existujících překladech + chybějící uk;
-- e7079920 dostává uk. Doklady: „ŘP a OP nebo PAS“ / „OP a ŘP“ (OP = občanský průkaz) bylo v překladech
-- 5c385d19 (en de fr nl pl) a 333ae882 (es de fr nl; pl jen české zkratky) přeloženo jako technický průkaz
-- vozidla → opraveno na doklad totožnosti, stejně 0b7ecebd „platný OP nebo PAS“ (pl technický průkaz, de české
-- zkratky); nl dac51062 „ander plaats“ → „andere plaats“ (otázka i odpověď).
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

-- updated_at nastaví trigger faq_items_set_updated_at.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_ans text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: id, pole (question/answer), jazyk ('cs' = sloupec, jinak translations.<jazyk>), how + old:
  --      'full'   = celý živý text má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --      'phrase' = věta old (v živém textu jednou) se nahradí new, zbytek textu zůstává
  --      'fill'   = překlad chybí → doplní se
  -- g: brána – překlad se mění jen když česká odpověď má otisk md5 = gate (nové / ověřené české znění)
  FOR f IN
    SELECT x.*, g.gate FROM (VALUES
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'cs', 'full', '99dbb53eee2c4c781e6c463f9fb2243f', $t$Ano, vrácení na jiném místě je možné v rámci celé ČR. Cena se řídí stejným ceníkem jako přistavení – 500 Kč za nakládku/vykládku a 20 Kč/km od Mezné u Pelhřimova. Nebo můžeš motorku vrátit přímo u nás na pobočce. Vrácení jinde ale neplatí pro motorky ze samoobslužné pobočky ve Velkých Němčicích – ty se přebírají i vracejí jen přímo na této pobočce.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'de', 'full', 'dc189c4fc5ee596e11ed96708ae34d5a', $t$Ja, eine Rückgabe an einem anderen Ort ist in der gesamten ČR möglich. Der Preis richtet sich nach derselben Gebührentabelle wie die Anlieferung – 500 Kč für Be- und Entladung und 20 Kč/km von Mezná u Pelhřimova. Oder du kannst das Motorrad direkt bei uns in der Filiale zurückgeben. Die Rückgabe an einem anderen Ort gilt jedoch nicht für Motorräder der Selbstbedienungsfiliale in Velké Němčice – sie werden nur direkt in dieser Filiale übernommen und zurückgegeben.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'en', 'full', '908db04a76284c01339a68f29a815403', $t$Yes, returning at a different location is possible throughout the Czech Republic. The price follows the same rate as delivery – 500 Kč for loading/unloading and 20 Kč/km from Mezná u Pelhřimova. Or you can return the motorcycle directly at our branch. Returning the bike elsewhere is not possible for bikes from the self-service branch in Velké Němčice – they are picked up and returned only at that branch.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'es', 'full', '36ea12b3cbbe1bcda7370b2361eef2d6', $t$Sí, es posible devolver la motocicleta en otro lugar dentro de toda la República Checa. El precio se rige por la misma tarifa que el envío: 500 Kč por carga/descarga y 20 Kč/km desde Mezná u Pelhřimova. O puedes devolver la motocicleta directamente en nuestra sucursal. La devolución en otro lugar no es posible para las motos de la sucursal de autoservicio de Velké Němčice: se recogen y se devuelven solo en esa sucursal.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'fr', 'full', '7e42928ba061b960313361dcd6cd1b53', $t$Oui, il est possible de retourner la moto à un autre endroit dans toute la République tchèque. Le prix est régi par le même barème que la livraison – 500 Kč pour le chargement/déchargement et 20 Kč/km à partir de Mezná u Pelhřimova. Ou tu peux retourner la moto directement à notre succursale. La restitution ailleurs ne s'applique pas aux motos de l'agence en libre-service de Velké Němčice : elles se retirent et se restituent uniquement dans cette agence.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'nl', 'full', '5a51c380af99fe9f5544eb3ce2a33526', $t$Ja, het terugbrengen op een andere plaats is mogelijk in heel de ČR. De prijs volgt dezelfde prijslijst als levering – 500 Kč per laden/afladen en 20 Kč/km vanaf Mezná u Pelhřimova. Of je kunt de motor direct bij ons op de vestiging terugbrengen. Terugbrengen op een andere plek geldt niet voor motoren van de zelfbedieningsvestiging in Velké Němčice – die worden alleen bij die vestiging opgehaald en teruggebracht.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'pl', 'full', 'fb0ed54a5be3ad6a800586dc43795d31', $t$Tak, zwrot w innym miejscu jest możliwy na terenie całej ČR. Cena jest ustalana według tego samego cennika co dostawa – 500 Kč za załadunek/rozładunek i 20 Kč/km od Mezná u Pelhřimova. Możesz również zwrócić motocykl bezpośrednio w naszym oddziale. Zwrot w innym miejscu nie dotyczy jednak motocykli z samoobsługowego oddziału Velké Němčice – odbiera się je i zwraca wyłącznie w tym oddziale.&nbsp;$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'question', 'nl', 'phrase', 'op een ander plaats', 'op een andere plaats'),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'question', 'uk', 'fill', NULL, $t$Чи можу повернути мотоцикл в іншому місці, ніж його отримав?$t$),
    ('dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'uk', 'fill', NULL, $t$Так, повернення в іншому місці можливе по всій Чехії. Ціна визначається за тим самим тарифом, що й доставка, – 500 Kč за завантаження/розвантаження та 20 Kč/км від Mezná біля Пельгржимова. Або можеш повернути мотоцикл безпосередньо в нашій філії. Проте повернення в іншому місці не стосується мотоциклів із філії самообслуговування Velké Němčice – їх отримують і повертають лише безпосередньо в цій філії.$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'cs', 'full', 'a379e6f1819c82a03ac07532fd31943b', $t$Ano, můžeš vyzvednout motorku u nás&nbsp; na pobočce a vrátit&nbsp; ji pak tam, kde ti to vyhovuje. Vrácení jinde ale neplatí pro motorky ze samoobslužné pobočky ve Velkých Němčicích – ty se přebírají i vracejí jen přímo na této pobočce.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'de', 'full', '11d27b8bc7ee46c757e8c3a192c04403', $t$Ja, du kannst das Motorrad bei uns&nbsp; in der Filiale abholen und es dann dort zurückgeben, wo es dir passt. Die Rückgabe an einem anderen Ort gilt jedoch nicht für Motorräder der Selbstbedienungsfiliale in Velké Němčice – sie werden nur direkt in dieser Filiale übernommen und zurückgegeben.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'en', 'full', '36ea9fee2846df3a7847d45e5a205786', $t$Yes, you can pick up a motorcycle at our branch and return it wherever works best for you. Returning the bike elsewhere is not possible for bikes from the self-service branch in Velké Němčice – they are picked up and returned only at that branch.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'es', 'full', 'e271466329132f3a03160773db760dca', $t$Sí, puedes recoger la moto en nuestra&nbsp;sucursal y devolverla luego donde te convenga. La devolución en otro lugar no es posible para las motos de la sucursal de autoservicio de Velké Němčice: se recogen y se devuelven solo en esa sucursal.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'fr', 'full', '2c875000860f344fa02f50e0f0680097', $t$Oui, tu peux louer une moto à notre succursale et la retourner ensuite là où cela t'arrange. La restitution ailleurs ne s'applique pas aux motos de l'agence en libre-service de Velké Němčice : elles se retirent et se restituent uniquement dans cette agence.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'nl', 'full', 'c61eced735b0a48f82d62e5aaa2b6350', $t$Ja, je kunt een motorfiets bij ons&nbsp;  op het kantoor ophalen en deze dan terugbrengen waar het jou uitkomt. Terugbrengen op een andere plek geldt niet voor motoren van de zelfbedieningsvestiging in Velké Němčice – die worden alleen bij die vestiging opgehaald en teruggebracht.&nbsp;$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'pl', 'full', 'bf31964b83e4eecc43d1f28b456b2a3b', $t$Tak, możesz odebrać motocykl w naszej&nbsp;  filii i zwrócić&nbsp;  go w wybranym przez siebie miejscu. Zwrot w innym miejscu nie dotyczy jednak motocykli z samoobsługowego oddziału Velké Němčice – odbiera się je i zwraca wyłącznie w tym oddziale.&nbsp;$t$)
    ) AS x(id, field, lang, how, old, new)
    JOIN (VALUES
    ('dac51062-20c0-4ea9-8422-54720f27b87e', '28c2bfb189e713299e77f2a94ac3b527'),
    ('19b96b98-8f06-485b-9748-b196de636132', 'b28e50a0099f466fe7c286ccaac5e4ab')
    ) AS g(id, gate) USING (id)
    ORDER BY (x.lang <> 'cs')            -- čeština první
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items
         SET answer = CASE WHEN f.field <> 'answer' THEN answer
                           WHEN f.how = 'phrase' THEN replace(answer, f.old, f.new) ELSE f.new END,
             question = CASE WHEN f.field <> 'question' THEN question
                             WHEN f.how = 'phrase' THEN replace(question, f.old, f.new) ELSE f.new END
       WHERE id = f.id::uuid
         AND CASE f.how WHEN 'full' THEN md5(CASE WHEN f.field = 'answer' THEN answer ELSE question END) = f.old
                        WHEN 'phrase' THEN strpos(CASE WHEN f.field = 'answer' THEN answer ELSE question END, f.old) > 0
                                       AND strpos(CASE WHEN f.field = 'answer' THEN answer ELSE question END, f.new) = 0
                        ELSE false END;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang],
               coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object(f.field,
                 CASE WHEN f.how = 'phrase' THEN replace(translations -> f.lang ->> f.field, f.old, f.new) ELSE f.new END))
       WHERE id = f.id::uuid
         AND md5(answer) = f.gate
         AND jsonb_typeof(translations) = 'object'
         AND (translations -> f.lang IS NULL OR jsonb_typeof(translations -> f.lang) = 'object')
         AND CASE f.how WHEN 'fill' THEN coalesce(translations -> f.lang ->> f.field, '') = ''
                        WHEN 'full' THEN md5(translations -> f.lang ->> f.field) = f.old
                        ELSE strpos(translations -> f.lang ->> f.field, f.old) > 0
                         AND strpos(translations -> f.lang ->> f.field, f.new) = 0 END;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT answer, CASE WHEN f.lang = 'cs' THEN (CASE WHEN f.field = 'answer' THEN answer ELSE question END)
                          ELSE translations -> f.lang ->> f.field END
        INTO v_ans, v_cur FROM public.faq_items WHERE id = f.id::uuid;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSIF f.lang <> 'cs' AND md5(v_ans) IS DISTINCT FROM f.gate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_branches: faq % % [%] PŘESKOČENO – česká odpověď není v očekávaném znění, překlad ponechán', f.id, f.field, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_branches: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.id, f.field, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_branches: faq_items upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
