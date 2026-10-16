-- =============================================================================
-- 20261015f_owner_texts_faq_fuel.sql
-- datová migrace (bez změn schématu): FAQ – palivo/mytí (překlady k odpovědi majitele), uk, „tankvak“ ≠ nádrž.
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- e6df7d9f „Musím vracet s plnou nádrží a čistou?“: českou odpověď majitel přepsal 2026-10-12; překlady
-- en–pl dál tvrdily „u nás nikde nemyješ“ → nové překlady + uk (jen dokud je čeština v tomto znění).
-- 02b6cfc8 „Jaké palivo mám tankovat?“: čeština sedí, doplněna jen chybějící uk.
-- 4975240d / 77557a0b: „tankvak“ (taška na nádrž) byl v pl/fr/uk přeložen jako „nádrž na palivo“
-- (es nepřeloženo, de gramatika) – opraveno jen to slovo.
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
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'en', 'full', 'cf59f48a578a0708f83df2346a4d02cf', $t$<p>We don't worry about the fuel level. You get the bike with whatever is in the tank at the time (it may not be full) and you refuel it yourself as needed during your ride. When you return it, you don't have to refuel – just make sure the reserve light isn't on. You don't pay anything extra for fuel.</p><p>You don't have to wash the bike at our staffed branch in Mezná. At the self-service branch in Velké Němčice, return it washed.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'de', 'full', 'bdeb0a0aea85ac8c1244e1f52fdbf136', $t$<p>Um den Tankstand kümmern wir uns nicht. Du bekommst das Motorrad mit dem, was gerade im Tank ist (er muss nicht voll sein), und tankst unterwegs selbst nach Bedarf. Bei der Rückgabe musst du nicht tanken – nur die Reserveleuchte sollte nicht leuchten. Für Kraftstoff zahlst du nichts nach.</p><p>An unserer Filiale mit Personal in Mezná musst du das Motorrad nicht waschen. An der Selbstbedienungsfiliale in Velké Němčice bring es gewaschen zurück.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'es', 'full', 'e63e97965ebd9367dbe27b9150cb62a2', $t$<p>No nos preocupamos por el nivel de combustible. Recibes la moto con el combustible que haya en ese momento en el depósito (puede que no esté lleno) y durante el viaje repostas tú mismo según lo necesites. Al devolverla no tienes que repostar; solo procura que no esté encendido el testigo de reserva. No pagas nada extra por el combustible.</p><p>En nuestra sucursal con personal de Mezná no tienes que lavar la moto. En la sucursal de autoservicio de Velké Němčice, devuélvela lavada.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'fr', 'full', 'a9df49c6b270c1dbb8fef706dbf1ebb4', $t$<p>On ne se soucie pas du niveau de carburant. Tu reçois la moto avec ce qu'il y a dans le réservoir à ce moment-là (il n'est pas forcément plein) et tu fais le plein toi-même selon tes besoins pendant le trajet. Au retour, tu n'as pas besoin de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. Tu ne paies rien en plus pour le carburant.</p><p>À notre agence avec personnel de Mezná, tu n'as pas besoin de laver la moto. À l'agence en libre-service de Velké Němčice, rends-la lavée.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'nl', 'full', '46cf13df777bb6e539fc24c07e67aec1', $t$<p>Het brandstofniveau maakt ons niet uit. Je krijgt de motor mee met wat er op dat moment in de tank zit (die hoeft niet vol te zijn) en onderweg tank je zelf wanneer nodig. Bij het terugbrengen hoef je niet te tanken – zorg alleen dat het reservelampje niet brandt. Voor brandstof betaal je niets bij.</p><p>Bij onze bemande vestiging in Mezná hoef je de motor niet te wassen. Bij de zelfbedieningsvestiging in Velké Němčice lever je hem gewassen in.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'pl', 'full', '217360fc2cc55ed2d29c385a8122ef80', $t$<p>Stanem paliwa się nie przejmujemy. Motocykl dostajesz z tym, co akurat jest w baku (nie musi być pełny), a w trasie tankujesz sam według potrzeb. Przy zwrocie nie musisz tankować – byle nie świeciła się kontrolka rezerwy. Za paliwo nic nie dopłacasz.</p><p>W oddziale z obsługą w Mezná nie musisz myć motocykla. W samoobsługowym oddziale Velké Němčice oddaj motocykl umyty.</p>$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'question', 'uk', 'fill', NULL, $t$Чи потрібно повертати мотоцикл із повним баком і чистим?$t$),
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'answer', 'uk', 'fill', NULL, $t$<p>Рівнем пального ми не переймаємося. Мотоцикл отримаєш із тим, що якраз є в баку (він може бути неповним), а під час поїздки заправляєшся сам за потреби. Під час повернення заправляти його не потрібно – лише стеж, щоб не світився індикатор резерву. За пальне нічого не доплачуєш.</p><p>У філії з персоналом у Mezná мотоцикл мити не потрібно. У філії самообслуговування Velké Němčice поверни його вимитим.</p>$t$),
    ('02b6cfc8-83af-4887-8f5f-a62214f64f2a', 'question', 'uk', 'fill', NULL, $t$Яке пальне мені заправляти?$t$),
    ('02b6cfc8-83af-4887-8f5f-a62214f64f2a', 'answer', 'uk', 'fill', NULL, $t$<p>Завжди пальне, <strong>передбачене виробником</strong> конкретного мотоцикла – знайдеш його в посібнику користувача, зазвичай і біля кришки бака (у наших мотоциклів це, як правило, бензин Natural 95). Якщо заправиш неправильне пальне, орендар у повному обсязі оплачує всі витрати на відкачування пального та ремонт двигуна. Під час повернення повний бак не потрібен, лише щоб не світився індикатор резерву.</p>$t$),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', 'answer', 'pl', 'phrase', '1 kuferek lub zbiornik paliwa', $t$1 kuferek lub torbę na bak$t$),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', 'answer', 'pl', 'phrase', $t$stałą частью motocykla$t$, $t$stałą częścią motocykla$t$),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', 'answer', 'fr', 'phrase', $t$en ont 1 ou un réservoir$t$, $t$en ont 1 ou une sacoche de réservoir$t$),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', 'answer', 'es', 'phrase', $t$1 baúl o tankvak$t$, $t$1 baúl o una bolsa sobre el depósito$t$),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', 'answer', 'de', 'phrase', '1 Koffer oder einen Tankreisetasche', '1 Koffer oder einen Tankrucksack'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'answer', 'uk', 'phrase', $t$резервуар для палива$t$, $t$сумку на бак$t$),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'answer', 'fr', 'phrase', $t$un réservoir d'essence$t$, $t$une sacoche de réservoir$t$)
    ) AS x(id, field, lang, how, old, new)
    JOIN (VALUES
    ('e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63', 'fe3672b730ff8f2906eabdf8711a24c5'),
    ('02b6cfc8-83af-4887-8f5f-a62214f64f2a', 'b77336ca60fee4d2165d8d5c71279534'),
    ('4975240d-08a4-458b-9a21-3ec8fb9557b1', '30e1c70081cc54e0a8956a4547e38e07'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'a8f0728b5ef841ca83c6925dff5e0cb9')
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
        RAISE NOTICE 'faq_fuel: faq % % [%] PŘESKOČENO – česká odpověď není v očekávaném znění, překlad ponechán', f.id, f.field, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_fuel: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.id, f.field, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_fuel: faq_items upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
