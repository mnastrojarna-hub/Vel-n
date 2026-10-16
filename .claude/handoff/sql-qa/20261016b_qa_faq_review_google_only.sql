-- =============================================================================
-- 20261016b_qa_faq_review_google_only.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- FAQ „Jak vám mohu zanechat recenzi?“ (faq_items fa9603a9-…, web /jak-pujcit/faq v 8 jazycích + AI agenti
-- přes get_faq) dnes vyjmenovává Google, Facebook, Firmy.cz a Tripadvisor. Pravidlo majitele 2026-10-15:
-- „odkaz na recenze by měl být vždy google“.
--
-- Varianta „hned“: jen Google (odkaz = app_settings.google_review_url) + soukromá zpětná vazba e-mailem.
-- Na nové tlačítko v appce („Napiš nám přímo, co máme zlepšit“) zatím NEODKAZUJE, takže jde nasadit
-- před vydáním appky. S vydáním appky lze přepsat návrhem reviews/sql/DRAFT_20261015_faq_review_google_only.sql
-- (stejný první odstavec, druhý odstavec navíc popisuje tlačítko v appce).
--
-- Bezpečnost: čeština se mění jen dokud odpověď ještě jmenuje Facebook/Firmy.cz/Tripadvisor (tj. nikdo ji
-- mezitím ve Velínu neupravil); překlad jazyka jen když chybí nebo stále jmenuje jiné recenzní weby.
-- Otázka (question) beze změny. Idempotentní (2. běh nic nezmění). Bez BEGIN/COMMIT.
-- Kontrola po aplikaci (nesmí vrátit řádek):
--   SELECT id FROM public.faq_items WHERE id = 'fa9603a9-a628-4349-9797-4c0bcc71fc57'
--     AND (answer ~* 'facebook|firmy|tripadvisor' OR translations::text ~* 'facebook|firmy|tripadvisor');
-- =============================================================================
DO $$
DECLARE
  c_id constant uuid := 'fa9603a9-a628-4349-9797-4c0bcc71fc57';
  c_cs constant text := $t$Budeme moc rádi za tvou zpětnou vazbu. Recenzi nám můžeš napsat na <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – stačí účet Google, ohodnotíš nás hvězdičkami a můžeš přidat krátký komentář.<div>Chceš nám napsat přímo, co máme zlepšit? Napiš nám na <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – zpráva přijde jen našemu týmu a nikde se nezveřejní.</div>$t$;
  r record;
  n_cs integer := 0;
  n_tr integer := 0;
BEGIN
  UPDATE public.faq_items SET answer = c_cs, updated_at = now()
   WHERE id = c_id AND answer ~* 'facebook|firmy|tripadvisor';
  GET DIAGNOSTICS n_cs = ROW_COUNT;
  IF n_cs = 0 THEN
    RAISE NOTICE 'faq_review: čeština beze změny (už bez jiných recenzních webů, nebo řádek chybí)';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('en', $t$We'd love to hear your feedback. You can write us a review on <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – all you need is a Google account: rate us with stars and add a short comment if you like.<div>Want to tell us directly what we can improve? Write to us at <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – the message goes only to our team and is never published.</div>$t$),
    ('de', $t$Wir freuen uns sehr über dein Feedback. Eine Bewertung kannst du uns auf <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> schreiben – du brauchst nur ein Google-Konto, vergibst Sterne und kannst einen kurzen Kommentar hinzufügen.<div>Möchtest du uns direkt sagen, was wir besser machen können? Schreib uns an <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – die Nachricht geht nur an unser Team und wird nirgends veröffentlicht.</div>$t$),
    ('es', $t$Nos encantará conocer tu opinión. Puedes escribirnos una reseña en <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a>: solo necesitas una cuenta de Google, nos valoras con estrellas y, si quieres, añades un breve comentario.<div>¿Quieres decirnos directamente qué podemos mejorar? Escríbenos a <a href="mailto:info@motogo24.cz">info@motogo24.cz</a>: el mensaje llega solo a nuestro equipo y nunca se publica.</div>$t$),
    ('fr', $t$Ton avis nous fait très plaisir. Tu peux nous écrire un avis sur <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – il suffit d'un compte Google : tu nous notes avec des étoiles et tu peux ajouter un court commentaire.<div>Tu veux nous dire directement ce qu'on peut améliorer ? Écris-nous à <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – le message arrive uniquement à notre équipe et n'est jamais publié.</div>$t$),
    ('nl', $t$We horen graag wat je ervan vond. Je kunt een review voor ons schrijven op <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – je hebt alleen een Google-account nodig, geeft ons sterren en kunt een korte opmerking toevoegen.<div>Wil je ons direct laten weten wat we kunnen verbeteren? Mail ons via <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – het bericht gaat alleen naar ons team en wordt nergens gepubliceerd.</div>$t$),
    ('pl', $t$Bardzo się ucieszymy z Twojej opinii. Recenzję możesz nam napisać w <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – wystarczy konto Google, oceniasz nas gwiazdkami i możesz dodać krótki komentarz.<div>Chcesz napisać nam wprost, co możemy poprawić? Napisz na <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – wiadomość trafi tylko do naszego zespołu i nigdzie nie zostanie opublikowana.</div>$t$),
    ('uk', $t$Ми будемо дуже раді твоєму відгуку. Написати нам відгук можна в <a href="https://g.page/r/CUmeYvk-sNf6EBM/review" target="_blank" rel="noopener"><span style="font-weight: bold;">Google</span></a> – потрібен лише обліковий запис Google: оціни нас зірками й за бажання додай короткий коментар.<div>Хочеш написати нам напряму, що варто покращити? Напиши на <a href="mailto:info@motogo24.cz">info@motogo24.cz</a> – повідомлення отримає лише наша команда, і його ніде не буде опубліковано.</div>$t$)
  ) AS v(lang, answer) LOOP
    UPDATE public.faq_items
       SET translations = jsonb_set(COALESCE(translations, '{}'::jsonb), ARRAY[r.lang],
             COALESCE(translations -> r.lang, '{}'::jsonb) || jsonb_build_object('answer', r.answer)),
           updated_at = now()
     WHERE id = c_id
       AND answer = c_cs
       AND (translations -> r.lang ->> 'answer' IS NULL
            OR translations -> r.lang ->> 'answer' ~* 'facebook|firmy|tripadvisor');
    IF FOUND THEN n_tr := n_tr + 1; END IF;
  END LOOP;
  RAISE NOTICE 'faq_review: čeština upravena %, překladů upraveno %', n_cs, n_tr;
END $$;
