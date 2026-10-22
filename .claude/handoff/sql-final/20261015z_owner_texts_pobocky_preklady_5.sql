-- =============================================================================
-- 20261015z_owner_texts_pobocky_preklady_5.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 5/7).
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
    ('web.pobocky.branches.1.steps', 'pl', 'fill', NULL, $t$1. Rezerwujesz i płacisz online, wybierasz godzinę odbioru i przesyłasz dokumenty (dowód osobisty/paszport + prawo jazdy): w oddziale samoobsługowym to konieczne – bez zweryfikowanych dokumentów nie dostaniesz kodów i nie wejdziesz do oddziału. Po weryfikacji dokumentów dostaniesz w aplikacji, e-mailem i SMS-em kody w kolejności, w jakiej będziesz je wpisywać: <strong>1) kod skrytki z kluczem do bramy, 2) kod szatni</strong> (jeśli wypożyczasz wyposażenie) <strong>i 3) kod motocykla</strong>.<br>2. <strong>Jeśli brama wjazdowa jest zamknięta</strong>, otwórz kodem z aplikacji <strong>górną skrytkę na prawym słupku bramy</strong>: jest w niej klucz do kłódki. Otwórz bramę, wjedź do środka i zaparkuj na dowolnym miejscu <strong>1–7, po prawej przy ogrodzeniu</strong> (zobacz zdjęcie parkingu). Auto może tu stać za darmo przez cały czas wynajmu. Jeśli brama jest otwarta, kod skrytki nie jest potrzebny.<br>3. Na ekranie wpisujesz kod szatni: <strong>szatnia to drzwi nr 8</strong>. Bierzesz wyposażenie, przebierasz się i zamykasz drzwi szatni (z własnym wyposażeniem pomijasz szatnię). Jeśli masz zniżkę za odbiór od 12:00, kody działają dopiero od 12:00.<br>4. Na ekranie poprawiasz rozmiary w protokole przekazania, podpisujesz go i wpisujesz kod motocykla: otwiera się boks z twoim motocyklem. Zamykasz boks i ruszasz w drogę!<br>5. <strong>Jeśli brama była zamknięta, po wyjeździe znów ją zamknij, zapnij kłódkę, odłóż klucz do górnej skrytki i pomieszaj cyfry szyfru.</strong> Jeśli brama jest otwarta, zostaw ją otwartą: nigdy nie zmieniaj stanu bramy.<br>6. Po jeździe oddajesz motocykl do boksu, a wyposażenie do szatni, o dowolnej porze ostatniego dnia wynajmu, do 24:00. Oddaj motocykl umyty i bez świecącej kontrolki rezerwy (pełny bak nie jest potrzebny). Jeśli brama jest zamknięta, postępujesz tak samo: otwierasz ją kluczem ze skrytki, a po wyjeździe znów zamykasz na kłódkę i odkładasz klucz.$t$),
    ('web.pobocky.branches.1.steps', 'uk', 'fill', NULL, $t$1. Бронюєш і оплачуєш онлайн, обираєш час отримання й завантажуєш документи (ID-картка/паспорт + посвідчення водія) — у філії самообслуговування це обовʼязково: без перевірених документів ти не отримаєш коди й не потрапиш на територію філії. Після перевірки документів отримаєш у застосунку, e-mail і SMS коди в тому порядку, у якому їх вводитимеш: <strong>1) код скриньки з ключем від воріт, 2) код роздягальні</strong> (якщо орендуєш екіпірування) <strong>і 3) код мотоцикла</strong>.<br>2. <strong>Якщо вʼїзні ворота зачинені</strong>, відкрий кодом із застосунку <strong>верхню скриньку на правому стовпі воріт</strong> — у ній ключ від навісного замка. Відімкни ворота, заїдь усередину й припаркуйся на будь-якому з місць <strong>1–7 праворуч біля паркану</strong> (див. фото паркування). Авто може безкоштовно стояти тут весь час оренди. Якщо ворота відчинені, код скриньки не потрібен.<br>3. На екрані вводиш код роздягальні — <strong>роздягальня — це двері № 8</strong>. Береш екіпірування, перевдягаєшся й зачиняєш двері роздягальні (із власним екіпіруванням роздягальню пропускаєш). Якщо маєш знижку за отримання з 12:00, коди діють лише з 12:00.<br>4. На екрані в протоколі передачі коригуєш розміри, підписуєш протокол і вводиш код мотоцикла — відчиниться бокс із мотоциклом. Зачиняєш бокс і вирушаєш.<br>5. <strong>Якщо ворота були зачинені, після відʼїзду знову зачини їх, замкни навісним замком, поверни ключ у верхню скриньку й прокрути коліщата з цифрами.</strong> Відчинені ворота залиш відчиненими: ніколи не змінюй стан воріт.<br>6. Після поїздки повертаєш мотоцикл у бокс, а екіпірування в роздягальню — будь-коли в останній день оренди до 24:00. Поверни мотоцикл вимитим і так, щоб не світився індикатор резерву (повний бак не потрібен). Якщо ворота зачинені, дієш так само: відмикаєш їх ключем зі скриньки, а після відʼїзду знову замикаєш і повертаєш ключ.$t$),
    ('web.pobocky.branches.1.steps_title', 'en', 'fill', NULL, 'How it works'),
    ('web.pobocky.branches.1.steps_title', 'de', 'fill', NULL, $t$So läuft es ab$t$),
    ('web.pobocky.branches.1.steps_title', 'es', 'fill', NULL, $t$Cómo funciona$t$),
    ('web.pobocky.branches.1.steps_title', 'fr', 'fill', NULL, $t$Comment ça se passe$t$),
    ('web.pobocky.branches.1.steps_title', 'nl', 'fill', NULL, 'Zo werkt het'),
    ('web.pobocky.branches.1.steps_title', 'pl', 'fill', NULL, 'Jak to przebiega'),
    ('web.pobocky.branches.1.steps_title', 'uk', 'fill', NULL, $t$Як це відбувається$t$),
    ('web.pobocky.branches.1.text', 'en', 'fill', NULL, $t$A modern <strong>self-service branch</strong> south of Brno. There are no staff on site: you handle everything yourself on the touchscreen using <strong>codes from the app</strong>, which you receive after paying and completing your documents. Bikes from this branch are picked up and returned only at the branch itself: we don't offer delivery or collection for them. You can <strong>park for free</strong> by the branch for the whole rental.$t$),
    ('web.pobocky.branches.1.text', 'de', 'fill', NULL, $t$Moderne <strong>Selbstbedienungsfiliale</strong> südlich von Brno. Vor Ort gibt es kein Personal: Du erledigst alles selbst am Touchscreen mit den <strong>Codes aus der App</strong>, die du nach der Zahlung und dem Hochladen deiner Dokumente erhältst. Motorräder dieser Filiale werden nur direkt in der Filiale übernommen und zurückgegeben – Lieferung oder Abholung bieten wir für sie nicht an. An der Filiale kannst du während der gesamten Miete <strong>kostenlos parken</strong>.$t$),
    ('web.pobocky.branches.1.text', 'es', 'fill', NULL, $t$Moderna <strong>sucursal de autoservicio</strong> al sur de Brno. No hay personal: lo gestionas todo tú mismo en la pantalla táctil con los <strong>códigos de la app</strong>, que recibes después de pagar y completar tus documentos. Las motos de esta sucursal se recogen y se devuelven solo en la propia sucursal: no ofrecemos entrega ni recogida a domicilio. Junto a la sucursal puedes <strong>aparcar gratis</strong> durante todo el alquiler.$t$),
    ('web.pobocky.branches.1.text', 'fr', 'fill', NULL, $t$Une <strong>agence en libre-service</strong> moderne au sud de Brno. Pas de personnel sur place : tu fais tout toi-même sur l'écran tactile avec les <strong>codes de l'appli</strong>, que tu reçois après le paiement et l'ajout de tes documents. Les motos de cette agence se récupèrent et se rendent uniquement sur place : nous ne proposons ni livraison ni enlèvement à domicile. À côté de l'agence, tu peux <strong>te garer gratuitement</strong> pendant toute la location.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.1.steps', '55dacd7167a7f395dbf39a2a7593e705'),
    ('web.pobocky.branches.1.steps_title', '2b604146d19ca968abcf9824fd9b57b1'),
    ('web.pobocky.branches.1.text', 'bd1e887bcd97f780656e46be4c6baed2')
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
