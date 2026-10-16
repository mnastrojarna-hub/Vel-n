-- =============================================================================
-- 20261016h_qa_uk_texts.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- Čeština na cizojazyčných stránkách webu (QA crawl uk/pl/fr/nl 2026-10-16):
--  • uk: 23 textů CMS bez ukrajinského překladu – závěrečné bloky stránek Blog, Mapa stránek, Katalog,
--    Detail motorky, E-shop (+ detail), Koupit dárkový poukaz, Detail dokumentu; H1 katalogu. Bez uk
--    překladu web bere český výchozí text z PHP → na uk stránce česky.
--  • nadpis „O našem blogu“ (web.blog.outro.title) bez překladu do všech jazyků;
--  • pl: nadpis „Co k motorce obdarovaný dostane v ceně nájmu?“ zůstal česky v pl překladu;
--  • názvy vlastních dokumentů (custom_documents): uk chybí, pl cookies „Zasady cookies_MotoGo24“;
--    obsah dokumentů zůstává závazný česky (překlad ve Velínu „Přeložit“);
--  • e-shop uk: produkty „Kukla reflexní“ a „Letní motorkářské rukavice“ bez ukrajinštiny.
-- Bezpečnost: překlad se doplní jen když chybí a česká předloha má přesně znění, ze kterého se
-- překládalo (md5); jinak NOTICE a beze změny. Idempotentní. Bez BEGIN/COMMIT.
-- Pozn.: věty „na telefonu 24/7“ / „dostupní nonstop“ přeloženy věrně podle češtiny – podle faktů majitele
-- je telefon Po–Pá 8–17 (viz zpráva QA); opravit případně češtinu ve Velínu a pak „Přeložit“.
-- =============================================================================
DO $$
DECLARE
  r record;
  n integer;
  n_uk integer := 0; n_bt integer := 0; n_doc integer := 0; n_pr integer := 0; n_pl integer := 0;
BEGIN
  -- 1) uk překlady CMS (jen chybějící, česká předloha beze změny)
  FOR r IN SELECT * FROM (VALUES
    ($q$web.blog.outro.body1$q$, '45462523b8465607d3ac10e2214b4a94', $q$<p>У цьому блозі ми пишемо не для того, щоб наші сторінки бачив Google. Ми пишемо для тебе — мотоциклістів, майбутніх мотоциклістів і всіх, хто хоче отримати від орендованого мотоцикла <strong>враження, а не стрес</strong>.</p>
<p>Що ти тут знайдеш:</p><ul><li><strong>Поради для мотоциклістів</strong> — від новачків зі свіжими правами до найдосвідченіших;</li><li><strong>Натхнення для маршрутів</strong> — Височина, Чехія, а також закордон;</li><li><strong>Практичні поради</strong> — як вибрати мотоцикл в оренду, що робити з подарунковим сертифікатом, що подарувати мотоциклісту тощо;</li><li><strong>Усе про наш прокат</strong> — чому і як ми виникли, чому в нас <strong>не потрібна застава</strong>, що входить у вартість оренди, як працює онлайн-реєстрація та багато іншого.</li></ul>$q$),
    ($q$web.blog.outro.body2$q$, 'dc38934a0cffff0d5215d21cfb3c6e72', $q$<p>Ми поступово додаємо нові статті. Буде на що чекати — ми <strong>сімейний прокат</strong> і так само й пишемо — без зайвої води, ніби сидимо поруч із тобою за кавою. Якщо тебе цікавить конкретна тема про мототуризм, спорядження або про те, як усе в нас насправді працює, ти в правильному місці.</p>
<p><strong>Маєш ідею статті, якої тут бракує?</strong> <a href="https://www.motogo24.cz/kontakt" rel="noopener" target="_blank">Напиши нам</a> — із запитань читачів часто виходять найкращі тексти.</p>$q$),
    ($q$web.blog.outro.title$q$, 'e7cd3832d9b6a24376926413d43f5127', $q$Про наш блог$q$),
    ($q$web.dokumenty_detail.outro.body1$q$, '8a4b46cb84c56313d5a0e9ae5a68a79c', $q$Усі договірні документи та протоколи MotoGo24 завжди в <strong>актуальній версії</strong> — ми регулярно переглядаємо їх з огляду на зміни в законодавстві та відгуки клієнтів. Ти знайдеш їх у текстовому й друкованому вигляді, можеш завантажити у форматі PDF і роздрукувати або переглянути прямо тут, на сайті. Повний текст умов надання послуг, договору оренди та політики захисту персональних даних доступний у розділі <a href="/jak-pujcit/dokumenty">Документи та інструкції</a>.$q$),
    ($q$web.dokumenty_detail.outro.body2$q$, '4e4c8c760c89d50dbcf8e4eb55b581c6', $q$Якщо в тебе є будь-яке запитання, наприклад, щодо договірних умов, порядку отримання чи повернення мотоцикла, не вагайся й зв’яжися з нами. Наші договори ми свідомо пишемо так, щоб вони були <strong>зрозумілими</strong> — без дрібного шрифту та прихованих умов.&nbsp;$q$),
    ($q$web.dokumenty_detail.outro.title$q$, 'b2d519173580dbd3d29d7b715a43ddec', $q$<span style="font-weight: bold;">Про наші документи</span>$q$),
    ($q$web.eshop.outro.body1$q$, '98d93fecbfd820fa7350d45b1dcb7dd2', $q$В інтернет-магазині MotoGo24 ти знайдеш <strong>мотоаксесуари, одяг і мерч</strong> для будь-якого стилю їзди. Зараз у нас можна вибрати <strong>кепки, футболки, рукавиці й балаклави</strong> — і асортимент ми <strong>постійно розширюємо</strong> новими речами, які порадують тебе в дорозі, у місті й поза мотоциклом. Більшість товарів є <strong>на складі в нас у Mezná біля Пельгржимова</strong>, і ми відправляємо їх <strong>до другого робочого дня</strong>.$q$),
    ($q$web.eshop.outro.title$q$, '2f54877ab1df8a0e834d1dc4de431b1a', $q$<span style="font-weight: bold;">Мотоаксесуари для кожного райдера</span>$q$),
    ($q$web.eshop_detail.outro.body1$q$, '9d10781bf05105c12e89a8509c12c4c9', $q$В інтернет-магазині MotoGo24 ти знайдеш <strong>ретельно дібраний мотоодяг і аксесуари</strong> у звичайних і нестандартних розмірах. Асортимент поповнюємо відповідно до потреб <strong>клієнтів нашого прокату та постійних райдерів</strong>, яким потрібні дрібниці — від <strong>кепок, футболок і рукавиць до балаклав під шолом</strong>. Усе є <strong>фізично на складі в нас у Mezná біля Пельгржимова.</strong>$q$),
    ($q$web.eshop_detail.outro.body2$q$, '1feacf79dbd229c5aa17302d50ad7898', $q$Доставляємо <strong>по всій Чеській Республіці</strong> — можеш вибрати <strong>безкоштовне особисте отримання в прокаті&nbsp;</strong>або <strong>Чеську пошту</strong>. Після замовлення тобі надійде <strong>автоматичний лист-підтвердження</strong>, а товар можеш очікувати протягом 1–3 робочих днів.&nbsp;Якщо потрібна порада (розмір, матеріал, поєднання з мотоспорядженням), напиши нам e-mail або зателефонуй. Намагаємося відповідати якнайшвидше.$q$),
    ($q$web.eshop_detail.outro.title$q$, 'e518ebe755f184180b0cb121186ba0d0', $q$<span style="font-weight: bold;">Купівля мотоаксесуарів у MotoGo24</span>$q$),
    ($q$web.katalog.h1$q$, 'de8401c577571b16ba9e51f8a9204c17', $q$Каталог мотоциклів$q$),
    ($q$web.katalog.outro.title$q$, '637d20128e74143da6884bd8ce579fef', $q$Категорії мотоциклів і скутерів у нашому прокаті$q$),
    ($q$web.katalog_detail.outro.body1$q$, '798978a4df6597a036879021774e17db', $q$Усі мотоцикли нашого автопарку ми ретельно доглядаємо — регулярне обслуговування, перевірка шин, гальм і загального стану техніки є само собою зрозумілими. Перед кожною видачею ми мотоцикл готуємо, перевіряємо&nbsp;його стан, фотографуємо й оформлюємо акт приймання-передачі.<div>Мотоцикли <span style="font-weight: bold;">здаємо в оренду&nbsp;</span><strong>без застави (навіть під час першого бронювання), а check-in </strong>ти легко зробиш <span style="font-weight: bold;">онлайн </span>самостійно, не виходячи з дому.<strong>&nbsp;</strong><span style="font-weight: bold;">Бронюванням можна керувати й після оплати.</span> Потрібно змінити дату? Замінити мотоцикл? Продовжити оренду? Без проблем. Зміни можна вносити неодноразово на сайті в розділі <span style="font-weight: bold;">Змінити бронювання </span>або у своєму <span style="font-weight: bold;">застосунку </span>MotoGo24 — і навіть за 1 день до початку оренди згідно з Умовами надання послуг.&nbsp;</div>$q$),
    ($q$web.katalog_detail.outro.body2$q$, 'eafd11bee012edc87aa73db7d765bb3d', $q$<span style="font-weight: 700;">З нашими мотоциклами можна без побоювань вирушати за кордон — навіть за межі ЄС! </span>Достатньо дотримуватися вказівок у зеленій карті.<span style="font-weight: 700;"> Ми також не обмежуємо пробіг, </span>тож не доведеться боятися доплат за перевищення лімітів — у нас їх немає.&nbsp;<div>Якщо дорогою виникне будь-яка проблема, просто зв’яжися з нами. <span style="font-weight: 700;">Для наших клієнтів ми на телефоні 24/7.&nbsp;</span></div>$q$),
    ($q$web.katalog_detail.outro.title$q$, 'bb0836f208eb7a79a7a581677b9bba34', $q$<span style="font-weight: bold;">Оренда мотоцикла без хвилювань і стресу</span>$q$),
    ($q$web.koupit_darkovy_poukaz.outro.body1$q$, 'f2ec29971bb68000c81aa28c0dfb2b4a', $q$<p><strong>Подарунковий сертифікат на оренду мотоцикла — це оригінальний подарунок</strong>, який порадує партнера, друга чи, наприклад, колегу — і підійде на день народження, річницю, Різдво, на честь складеного іспиту на права або з будь-якої нагоди, коли хочеш потішити того, <strong>хто любить враження більше, ніж речі</strong>. Замість ще однієї чашки, краватки чи светра ти подаруєш справжнє <strong>мотоциклетне враження</strong>, яке згадуватимуть ще роками.</p><h4>Ідеальний подарунок і для компаній</h4><p>
</p><p>Шукаєш оригінальний <strong>подарунок для працівників, клієнтів чи бізнес-партнерів</strong>? Подарунковий сертифікат на мотоцикл — саме те, що справді потішить: замість чергової ручки з логотипом чи ваучера до супермаркету, який опиниться в шухляді, людина отримає <strong>конкретне враження</strong>, яке запам’ятає. Підійде для <strong>різдвяних подарунків, річних бонусів, відзнак за результати, ювілеїв компанії та тимбілдингів</strong> — щоразу, коли хочеш справити враження. <strong>Якщо замовляєш кілька сертифікатів одразу, усі деталі домовимося разом</strong> — однакові або різні номінали залежно від посад, масова доставка до визначеного терміну, подарункове пакування та знижка за кількість. Просто напиши нам, і ми охоче підготуємо пропозицію саме для тебе.</p>
<h4>Як це працює</h4>
<p><strong>Сертифікат дійсний 3 роки</strong> з дати видачі — обдарований має достатньо часу, щоб спланувати поїздку на ідеальний термін і погоду. <strong>Дату й конкретний мотоцикл він вибирає сам</strong> у нашому каталозі відповідно до номіналу сертифіката — від <strong>туристичних мотоциклів</strong> для багатоденних поїздок через <strong>спритні нейкеди</strong> й <strong>гострі супермото</strong> аж до <strong>дитячих мотоциклів</strong> для маленьких райдерів.&nbsp;</p>
<h4>Як ми доставимо сертифікат</h4>
<p>Після оплати сертифікат <strong>одразу надійде тобі на e-mail</strong> — достатньо його роздрукувати або переслати обдарованому електронною поштою. Якщо хочеш <strong>друкований подарунковий варіант,</strong>&nbsp;можеш доплатити за нього прямо в замовленні, і ми його або підготуємо до отримання в нас у Mezná біля Пельгржимова, або надішлемо поштою.</p>$q$),
    ($q$web.koupit_darkovy_poukaz.outro.body2$q$, '80371c3ac70a51e257295f3a5a2a0480', $q$<h4>Що обдарований отримає разом із мотоциклом у ціні оренди?</h4><div><br></div><h4>
<ul>
<li>Повне спорядження для водія <span style="font-weight: normal;">— шолом, куртка, штани, рукавиці.</span></li>
<li>Оренда без застави <span style="font-weight: normal;">— жодного блокування грошей на картці.</span></li>
<li>Зелену карту й документи&nbsp;<span style="font-weight: normal;">— передусім для можливих поїздок за кордон.</span></li>
<li>Зручне облаштування під час отримання <span style="font-weight: normal;">— кабінка для перевдягання, WC, Wi-Fi, шафки із замком.</span></li>
<li>Гнучке отримання й повернення <span style="font-weight: normal;">— у нас обдарований може забрати мотоцикл хоч опівночі.</span></li>
<li>Жодних обмежень щодо досвіду <span style="font-weight: normal;">— подарунок у MotoGo24 використає навіть свіжоспечений випускник мотошколи.</span></li><li><span style="font-weight: normal;"><br></span></li>
</ul>
<p><span style="font-weight: normal;">Усе бронювання разом з оплатою відбувається зручно онлайн, тож обдарований спокійно вибере термін удома, а в бронюванні може будь-коли сам змінити все, що буде потрібно.&nbsp;</span></p></h4>$q$),
    ($q$web.koupit_darkovy_poukaz.outro.title$q$, '4f16abd55a7f367da416ff4bdedd109d', $q$<span style="font-weight: bold;">Що варто знати про подарунковий сертифікат MotoGo24</span>$q$),
    ($q$web.mapa_stranek.intro$q$, 'f568e9da01c56b1b9140007eb7468351', $q$Ця мапа сайту — огляд <strong>усього сайту MotoGo24</strong>: тут ти знайдеш посилання на каталог мотоциклів в оренду, покроковий порядок оренди, ціни, подарункові сертифікати, блог із порадами для мотоциклістів, інтернет-магазин з мотоаксесуарами та юридичні документи.$q$),
    ($q$web.mapa_stranek.outro.body1$q$, 'eb164fb516caca6195b4325fd8301607', $q$Якщо не можеш знайти те, що шукаєш, почни з <strong>головної сторінки</strong> або переглянь розділ <a href="/jak-pujcit">Як орендувати мотоцикл</a>, де є вся інформація про бронювання, отримання, повернення та про те, що входить у вартість оренди. Для швидкої орієнтації пропонуємо також <a href="/jak-pujcit/faq">часті запитання</a> й докладний опис кожного мотоцикла в <a href="/katalog">каталозі</a>.$q$),
    ($q$web.mapa_stranek.outro.body2$q$, 'c9f0b223fb6fa1ceb5ed3d6465fcac54', $q$Досі не можеш зорієнтуватися? Зв’яжися з нами телефоном, електронною поштою або через наші соцмережі — знайдеш їх у розділі <a href="/kontakt">Контакти</a>. Ми на зв’язку нонстоп і охоче допоможемо з вибором мотоцикла, терміном або замовленням подарункового сертифіката.$q$),
    ($q$web.mapa_stranek.outro.title$q$, '5922f3739c1a07d4adfffb28efa39574', $q$<span style="font-weight: bold;">Шукаєш щось конкретне?</span>$q$)
  ) AS v(key, cs_md5, uk) LOOP
    UPDATE public.cms_variables
       SET translations = COALESCE(translations, '{}'::jsonb) || jsonb_build_object('uk', jsonb_build_object('value', r.uk)),
           updated_at = now()
     WHERE key = r.key AND jsonb_typeof(value) = 'string' AND md5(value #>> '{}') = r.cs_md5
       AND NOT (COALESCE(translations, '{}'::jsonb) ? 'uk');
    GET DIAGNOSTICS n = ROW_COUNT; n_uk := n_uk + n;
    IF n = 0 THEN RAISE NOTICE 'uk: beze změny % (překlad už je, nebo se čeština změnila)', r.key; END IF;
  END LOOP;
  -- 2) „O našem blogu“ – ostatní jazyky
  FOR r IN SELECT * FROM (VALUES
    ('en', $q$About our blog$q$),
    ('de', $q$Über unseren Blog$q$),
    ('es', $q$Sobre nuestro blog$q$),
    ('fr', $q$À propos de notre blog$q$),
    ('nl', $q$Over onze blog$q$),
    ('pl', $q$O naszym blogu$q$)
  ) AS v(lang, t) LOOP
    UPDATE public.cms_variables
       SET translations = COALESCE(translations, '{}'::jsonb) || jsonb_build_object(r.lang, jsonb_build_object('value', r.t)),
           updated_at = now()
     WHERE key = 'web.blog.outro.title' AND value #>> '{}' = 'O našem blogu'
       AND NOT (COALESCE(translations, '{}'::jsonb) ? r.lang);
    GET DIAGNOSTICS n = ROW_COUNT; n_bt := n_bt + n;
  END LOOP;
  -- 3) pl: český nadpis v překladu bloku dárkového poukazu
  UPDATE public.cms_variables
     SET translations = jsonb_set(translations, '{pl,value}', to_jsonb(replace(translations -> 'pl' ->> 'value', $q$<h4>Co k motorce obdarovaný dostane v ceně nájmu?</h4>$q$, $q$<h4>Co obdarowany otrzyma razem z motocyklem w cenie wynajmu?</h4>$q$))),
         updated_at = now()
   WHERE key = 'web.koupit_darkovy_poukaz.outro.body2'
     AND strpos(translations -> 'pl' ->> 'value', $q$<h4>Co k motorce obdarovaný dostane v ceně nájmu?</h4>$q$) > 0;
  GET DIAGNOSTICS n_pl = ROW_COUNT;
  -- 4) názvy vlastních dokumentů
  FOR r IN SELECT * FROM (VALUES
    ($q$reklamacni-rad-e-shop-motogo24$q$, 'uk', $q$Порядок розгляду рекламацій — інтернет-магазин MotoGo24$q$),
    ($q$obchodni-podminky-pro-e-shop-motogo24$q$, 'uk', $q$Умови продажу в інтернет-магазині MotoGo24$q$),
    ($q$zasady-cookies-motogo24$q$, 'uk', $q$Політика використання файлів cookie — MotoGo24$q$),
    ($q$zasady-cookies-motogo24$q$, 'pl', $q$Polityka plików cookie — MotoGo24$q$)
  ) AS v(slug, lang, t) LOOP
    UPDATE public.custom_documents
       SET translations = jsonb_set(COALESCE(translations, '{}'::jsonb), ARRAY[r.lang],
             COALESCE(translations -> r.lang, '{}'::jsonb) || jsonb_build_object('title', r.t))
     WHERE slug = r.slug
       AND (NOT (COALESCE(translations, '{}'::jsonb) ? r.lang)
            OR translations -> r.lang ->> 'title' IS NULL
            OR translations -> r.lang ->> 'title' = 'Zasady cookies_MotoGo24');
    GET DIAGNOSTICS n = ROW_COUNT; n_doc := n_doc + n;
  END LOOP;
  -- 5) e-shop: produkty bez ukrajinštiny
  FOR r IN SELECT * FROM (VALUES
    ('0551496d-77a4-4f51-bc23-9196b3440f14', $q${"name": "Рефлективна балаклава", "color": "Зелена рефлективна", "material": "85% поліамід, 15% спандекс", "description": "М’яка рефлективна балаклава, що підходить під будь-який мотошолом."}$q$::jsonb),
    ('86616309-d992-443d-8d70-07183b7788cf', $q${"name": "Літні мотоциклетні рукавиці", "material": "Поліестер", "description": "Легкі, зручні й готові до кожної літньої поїздки. Ці моторукавиці поєднують комфорт, надійний хват і захист там, де він найпотрібніший.\nЗавдяки ергономічному крою рукавиці чудово сидять на руці, не заважають керуванню й приємно підлаштовуються під хват керма. Захисні елементи в зоні суглобів допомагають підвищити безпеку під час їзди, а застібка-липучка тримає рукавиці на місці, щоб не розслаблялися.\nДихаючий матеріал особливо оціниш у теплі дні, під час коротших поїздок і довших роудтріпів."}$q$::jsonb)
  ) AS v(id, tr) LOOP
    UPDATE public.products
       SET translations = COALESCE(translations, '{}'::jsonb) || jsonb_build_object('uk', r.tr)
     WHERE id = r.id::uuid AND NOT (COALESCE(translations, '{}'::jsonb) ? 'uk');
    GET DIAGNOSTICS n = ROW_COUNT; n_pr := n_pr + n;
  END LOOP;
  RAISE NOTICE 'qa_uk_texts: uk CMS %, nadpis blogu %, pl poukaz %, dokumenty %, produkty %', n_uk, n_bt, n_pl, n_doc, n_pr;
END $$;
