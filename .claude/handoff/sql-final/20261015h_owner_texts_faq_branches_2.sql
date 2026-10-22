-- =============================================================================
-- 20261015h_owner_texts_faq_branches_2.sql
-- datová migrace (bez změn schématu): FAQ – vrácení jinde / osobní převzetí: co platí na samoobslužné pobočce (část 2/3).
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
    ('19b96b98-8f06-485b-9748-b196de636132', 'question', 'uk', 'fill', NULL, $t$Що, як я хочу забрати мотоцикл у прокаті, а повернути деінде – це можливо?$t$),
    ('19b96b98-8f06-485b-9748-b196de636132', 'answer', 'uk', 'fill', NULL, $t$Так, можеш забрати мотоцикл у нашій філії й повернути його там, де тобі зручно. Проте повернення в іншому місці не стосується мотоциклів із філії самообслуговування Velké Němčice – їх отримують і повертають лише безпосередньо в цій філії.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'cs', 'full', '36488d57497d576c5294c75799d59768', $t$Ano, přijedeme si pro motorku kamkoliv v České republice. Místo vrácení zadáš při rezervaci – může to být hotel, parkoviště, nádraží nebo jakákoliv jiná adresa. Vrácení jinde ale neplatí pro motorky ze samoobslužné pobočky ve Velkých Němčicích – ty se přebírají i vracejí jen přímo na této pobočce.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'de', 'full', '854f263392ab002dc911a785d47a3221', $t$Ja, wir holen das Motorrad überall in der Tschechischen Republik ab. Den Rückgabeort gibst du bei der Reservierung an – das kann ein Hotel, ein Parkplatz, ein Bahnhof oder eine beliebige andere Adresse sein. Die Rückgabe an einem anderen Ort gilt jedoch nicht für Motorräder der Selbstbedienungsfiliale in Velké Němčice – sie werden nur direkt in dieser Filiale übernommen und zurückgegeben.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'en', 'full', '85bd05f02251e8b56dcc15e075a90938', $t$Yes, we will pick up the motorcycle anywhere in the Czech Republic. You specify the return location during booking – it can be a hotel, parking lot, train station, or any other address. Returning the bike elsewhere is not possible for bikes from the self-service branch in Velké Němčice – they are picked up and returned only at that branch.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'es', 'full', 'fd4ef499d76fb7677b780dc227ff1c34', $t$Sí, vendremos a recoger la moto a cualquier lugar de la República Checa. Especificas el lugar de devolución durante la reserva – puede ser un hotel, un aparcamiento, una estación de tren o cualquier otra dirección. La devolución en otro lugar no es posible para las motos de la sucursal de autoservicio de Velké Němčice: se recogen y se devuelven solo en esa sucursal.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'fr', 'full', '39a54e3bb7f86409980580f437a92a64', $t$Oui, nous venons chercher la moto partout en République tchèque. Vous indiquez le lieu de retour lors de la réservation – cela peut être un hôtel, un parking, une gare ou n'importe quelle autre adresse. La restitution ailleurs ne s'applique pas aux motos de l'agence en libre-service de Velké Němčice : elles se retirent et se restituent uniquement dans cette agence.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'nl', 'full', 'de55cb10439456fc782c197d6a5be0dc', $t$Ja, we halen de motorfiets overal in de Tsjechische Republiek op. Je geeft de afleveringslocatie op bij de boeking – het kan een hotel, parkeerplaats, station of elk ander adres zijn. Terugbrengen op een andere plek geldt niet voor motoren van de zelfbedieningsvestiging in Velké Němčice – die worden alleen bij die vestiging opgehaald en teruggebracht.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'pl', 'full', 'ecf82d354e8677f71abd6e09e57ef6a0', $t$Tak, przyjdziemy po motocykl gdziekolwiek w Republice Czeskiej. Miejsce zwrotu podajesz podczas rezerwacji – może to być hotel, parking, dworzec lub jakikolwiek inny adres. Zwrot w innym miejscu nie dotyczy jednak motocykli z samoobsługowego oddziału Velké Němčice – odbiera się je i zwraca wyłącznie w tym oddziale.$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'question', 'uk', 'fill', NULL, $t$Чи можна повернути мотоцикл справді будь-де в Чехії?$t$),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', 'answer', 'uk', 'fill', NULL, $t$Так, ми приїдемо по мотоцикл будь-куди в Чеській Республіці. Місце повернення вкажеш під час бронювання – це може бути готель, парковка, вокзал чи будь-яка інша адреса. Проте повернення в іншому місці не стосується мотоциклів із філії самообслуговування Velké Němčice – їх отримують і повертають лише безпосередньо в цій філії.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'cs', 'full', 'a9e7cfce4513f9ac56fc6718320ea8e2', $t$Ano, při převzetí motorky je nutná osobní přítomnost – ověříme tvé doklady (ŘP a OP nebo PAS), předáme motorku a případnou výbavu a podepíšeme předávací protokol. Tak to probíhá na obslužné pobočce v Mezné. Na samoobslužné pobočce ve Velkých Němčicích si motorku převezmeš sám pomocí kódů z aplikace nebo e-mailu a předávací protokol podepíšeš na displeji – doklady musíš mít předem nahrané a ověřené online.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'de', 'full', 'af966962782fac2ed7a6c1450565e14b', $t$Ja, bei der Übernahme des Motorrads ist deine persönliche Anwesenheit erforderlich – wir überprüfen deine Dokumente (Führerschein und Personalausweis oder Reisepass), übergeben das Motorrad und eventuelle Ausrüstung und unterzeichnen das Übergabeprotokoll. So läuft es in unserer Filiale mit Personal in Mezná. An der Selbstbedienungsfiliale in Velké Němčice übernimmst du das Motorrad selbst mit den Codes aus der App oder E-Mail und unterschreibst das Übergabeprotokoll am Display – deine Dokumente müssen vorab online hochgeladen und geprüft sein.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'en', 'full', '49bc52764914a9b69c57071bb6cf7684', $t$Yes, when picking up the motorcycle, your personal presence is required – we will verify your documents (driving licence and ID card or passport), hand over the motorcycle and any equipment, and sign a handover protocol. That is how it works at our staffed branch in Mezná. At the self-service branch in Velké Němčice you pick up the bike yourself with codes from the app or e-mail and sign the handover protocol on the display – your documents must be uploaded and verified online in advance.$t$),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'answer', 'es', 'full', 'f6f536261ee95a47c8657c3c1a918247', $t$Sí, al recoger la moto es necesaria tu presencia personal – verificaremos tus documentos (licencia de conducir y documento de identidad o pasaporte), entregaremos la moto y el equipo correspondiente, y firmaremos el protocolo de entrega. Así funciona en nuestra sucursal con personal de Mezná. En la sucursal de autoservicio de Velké Němčice recoges la moto tú mismo con los códigos de la aplicación o del correo electrónico y firmas el protocolo de entrega en la pantalla; tus documentos deben estar subidos y verificados online con antelación.$t$)
    ) AS x(id, field, lang, how, old, new)
    JOIN (VALUES
    ('19b96b98-8f06-485b-9748-b196de636132', 'b28e50a0099f466fe7c286ccaac5e4ab'),
    ('dd9c3286-142c-4601-9060-f7bb1f78f4a7', '1aeae393dace31b97e26f904e9080436'),
    ('5c385d19-7c6e-4f43-9645-bdc163424371', 'be28a39605eac5b7f5984b23e494547d')
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
