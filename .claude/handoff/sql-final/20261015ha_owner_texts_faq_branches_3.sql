-- =============================================================================
-- 20261015ha_owner_texts_faq_branches_3.sql
-- datová migrace (bez změn schématu): FAQ – vrácení jinde / osobní převzetí: co platí na samoobslužné pobočce (část 3/3).
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
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'fr', 'full', '7ba7776ab89e8ae63ea7fa9766e282be', $t$Oui, lors de la prise en charge de la moto, votre présence personnelle est obligatoire – nous vérifierons vos documents (permis de conduire et carte d'identité ou passeport), nous remettrons la moto et l'équipement éventuel et nous signerons le protocole de remise. C'est ainsi que cela se passe dans notre agence avec personnel de Mezná. À l'agence en libre-service de Velké Němčice, vous récupérez la moto vous-même avec les codes reçus dans l'application ou par e-mail et signez le protocole de remise sur l'écran – vos documents doivent être téléchargés et vérifiés en ligne au préalable.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'nl', 'full', '47e10930a78732dc0be1d9e89d5768d4', $t$Ja, bij het ophalen van de motorfiets is persoonlijke aanwezigheid vereist – we verifiëren je documenten (rijbewijs en identiteitskaart of paspoort), we geven de motorfiets en eventuele uitrusting aan je over en we ondertekenen het overdrachtdocument. Zo gaat het bij onze bemande vestiging in Mezná. Bij de zelfbedieningsvestiging in Velké Němčice haal je de motor zelf op met de codes uit de app of e-mail en onderteken je het overdrachtsprotocol op het scherm – je documenten moeten vooraf online zijn geüpload en geverifieerd.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'pl', 'full', '6b2f0b30fee90c747e8b3c0578862b92', $t$Tak, przy odbiorze motocykla wymagana jest osobista obecność – zweryfikujemy Twoje dokumenty (prawo jazdy i dowód osobisty lub paszport), wydamy motocykl i ewentualny sprzęt oraz podpiszemy protokół przekazania. Tak to wygląda w naszym oddziale z obsługą w Mezná. W samoobsługowym oddziale Velké Němčice odbierasz motocykl sam za pomocą kodów z aplikacji lub e-maila i podpisujesz protokół przekazania na wyświetlaczu – dokumenty musisz mieć wcześniej przesłane i zweryfikowane online.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'question', 'uk', 'fill', NULL, $t$Чи потрібно приїжджати особисто?$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'uk', 'fill', NULL, $t$Так, під час отримання мотоцикла потрібна твоя особиста присутність – перевіримо твої документи (посвідчення водія та ID-картку або паспорт), передамо мотоцикл і за потреби екіпірування та підпишемо протокол передачі. Так це відбувається у філії з персоналом у Mezná. У філії самообслуговування Velké Němčice мотоцикл забереш сам за допомогою кодів із застосунку або електронного листа, а протокол передачі підпишеш на дисплеї – документи мусиш заздалегідь завантажити онлайн, і їх мають перевірити.$t$),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'es', 'phrase', '(certificado de registro y licencia de conducir)', '(documento de identidad y permiso de conducir)'),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'de', 'phrase', $t$(Kraftfahrzeugschein und Führerschein)$t$, $t$(Personalausweis und Führerschein)$t$),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'fr', 'phrase', '(carte grise et permis de conduire)', $t$(carte d'identité et permis de conduire)$t$),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'nl', 'phrase', '(eigendomsbewijs en rijbewijs)', '(identiteitskaart en rijbewijs)'),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'pl', 'phrase', $t$(OP i ŘP)$t$, $t$(dowód osobisty i prawo jazdy)$t$),
    ('0b7ecebd-da89-44ec-ab2b-e3ac2063781b', 'answer', 'pl', 'phrase', $t$ważny dowód rejestracyjny lub paszport$t$, $t$ważny dowód osobisty lub paszport$t$),
    ('0b7ecebd-da89-44ec-ab2b-e3ac2063781b', 'answer', 'de', 'phrase', $t$einen gültigen OP oder PAS hat$t$, $t$einen gültigen Personalausweis oder Reisepass hat$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'question', 'uk', 'fill', NULL, $t$Де відбувається отримання та повернення?$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'answer', 'uk', 'fill', NULL, $t$У мотопрокаті за адресою Mezná 9, 393 01 Mezná (біля Пельгржимова). У формі бронювання можеш домовитися й про отримання чи повернення в іншому місці. Мотоцикли з філії самообслуговування Velké Němčice (Boudky, 691 63 Velké Němčice, біля Брна) отримують і повертають лише безпосередньо в цій філії, 24/7 за допомогою кодів із застосунку (бронювання зі знижкою за отримання з 12:00 кіоск видасть лише з 12:00) — доставку чи забирання для них не пропонуємо.$t$)
    ) AS x(id, field, lang, how, old, new)
    JOIN (VALUES
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'be28a39605eac5b7f5984b23e494547d'),
    ('333ae882-1e32-4d8e-818e-027e48af5c35', 'adeebc37e42123f99866b0829e27fd1f'),
    ('0b7ecebd-da89-44ec-ab2b-e3ac2063781b', '1e0d958b046f092def29b37529adac7e'),
    ('e7079920-f08c-4b08-b52a-9b8623909035', '5fb5ae18ac4117c52cd0b3090ba20de0')
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
