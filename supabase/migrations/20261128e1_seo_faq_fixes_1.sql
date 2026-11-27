-- =============================================================================
-- 20261128e1_seo_faq_fixes_1.sql
-- datová migrace (bez změn schématu): časté dotazy (faq_items) – rezervace, ceny a platby uvedené do souladu s tím, co systém dělá (část 1/3).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: opravy textů; „časté dotazy musí odpovídat realitě“.
-- Každá změna je ověřená proti tomu, co systém opravdu dělá (živé schéma a data 2026-11-27, kód
-- rezervace na webu a v aplikaci) a proti závazným dokumentům (obchodní podmínky v15, smlouva v11).
-- Důkazy ke každé otázce jsou v auditu častých dotazů z 2026-11-27 (podklad mimo repozitář).
-- Co ověřit nešlo, se NEMĚNÍ – otázky k tomu dostal majitel.
-- Mění se JEN české texty (sloupce question / answer). Sloupec translations (cizí jazyky) se nemění –
-- cizojazyčné verze ukazují dál dosavadní překlad, dokud se otázka ve Velínu znovu neuloží / nepřeloží.
-- Nic se nemaže ani nepřidává (žádný INSERT / DELETE).
--
-- Bezpečnost: každý text se změní jen tehdy, když má v databázi PŘESNĚ znění ověřené proti
-- živé DB 2026-11-27 ('full' = celý text; 'phrase' = uvedená část textu, zbytek zůstává).
-- Co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění).
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- updated_at nastaví trigger faq_items_set_updated_at. ai_kb_version se nemění (KB AI agenta má TTL 5 min).
-- POZOR u otázky o e-shopu (78d4791f): věta „slevový kód nelze uplatnit na nákup poukazu“ se vypouští,
-- protože 20261127a1–a3 (schváleno 27. 11.) slevové kódy u nákupu poukazu zavádí.
-- =============================================================================

DO $$
DECLARE
  r record;
  n integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: pořadí, id, pole (question / answer), how ('full' = old je celé dosavadní znění; 'phrase' = část textu), old, new
  FOR r IN
    SELECT * FROM (VALUES
    -- „Můžu kvůli špatnému počasí posunout rezervaci na další den?“ · Odpověď tvrdila, že změny jdou jen do půlnoci dne před výpůjčkou. Web i aplikace ale posun zdarma dovolí až do převzetí motorky. Doplněno pravidlo, které systém opravdu uplatňuje: po posunu se při stornu vrací nejvýš 50 %.
    (1, 'b80783b1-780c-4482-b53e-f4e019a92ed5', 'answer', 'full', $o$Rádi ti vyjdeme vstříc, ale záleží na aktuální dostupnosti dané motorky. Přesun na další den nemůžeme garantovat vždy. Změnu si můžeš spravovat sám/sama v sekci Upravit rezervaci přímo na našem webu nebo v aplikaci. POZOR - jakékoliv změny v rezervaci je možné provádět nejpozději 1 den před začátkem nájemní doby (tzn. max. do půlnoci dne před nájemním dnem).$o$,
      $n$Ano. Celou rezervaci si můžeš zdarma posunout na jiný termín až do začátku výpůjčky (dokud motorku nepřevezmeš) – přímo v sekci Upravit rezervaci na webu nebo v aplikaci, pokud je motorka v novém termínu volná. Počet dní i cena zůstávají stejné. Jen počítej s tím, že po posunu termínu ti při pozdějším stornu nebo zkrácení vrátíme nejvýš 50 % (při posunu méně než 7 dní před původním začátkem už nic). Kdyby ti posun nešel, ozvi se nám.$n$),
    -- „Můžu si u vás půjčit jen výbavu, když mám motorku svoji?“ · Odpověď uváděla 500 Kč za set, v ceníku je ale komplet za 490 Kč (s botami 890 Kč) na den. Zároveň říkala „ozvi se a zaplať na místě“ i „objednej online“ – oblečení se objednává a platí online. Sekce se v menu jmenuje Půjčení oblečení. Část o doplňkové výbavě za 100 Kč zůstává, jak ji máš.
    (2, '77557a0b-8c40-431e-a966-34848e738b7b', 'answer', 'full', $o$Ano, rádi ti vyjdeme vstříc. Můžeš si u nás zapůjčit helmu, bundu, kalhoty, rukavice, kuklu i boty. Cena je 500 Kč za celý set/1 den.&nbsp;<div><br></div><div>Rádi ti zapůjčíme také nepromoky, kotoučový zámek, síťku, tankvak apod. Cena je 100 Kč za celý set/den (je jedno, jestli si chceš půjčit vše nebo jen něco z toho).&nbsp;</div><div><br><div>Pokud máš o samostatnou výpůjčku výbavy zájem, ozvi se nám, dohodneme se.</div><div>Výpůjčka motooblečení případně další výbavy se platí na místě při převzetí QR kódem (platbu v hotovosti nepřijímáme).&nbsp;</div></div><div><br></div><div>Samostatnou výpůjčku výbavy bez motorky (helma, bunda, kalhoty, rukavice, boty) objednáte online v sekci Půjčení výbavy — je tam aktuální ceník i pobočky, na kterých je výpůjčka dostupná. Nepromoky a další doplňkovou výbavu půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova.</div>$o$,
      $n$Ano. Helmu, bundu, kalhoty, rukavice i boty si bez motorky objednáš a zaplatíš online v sekci <a href="/pujceni-obleceni">Půjčení oblečení</a> – najdeš tam aktuální ceník i pobočky, na kterých je výpůjčka dostupná.<div><br></div><div>Rádi ti zapůjčíme také nepromoky, kotoučový zámek, síťku, tankvak apod. Cena je 100 Kč za celý set/den (je jedno, jestli si chceš půjčit vše nebo jen něco z toho). Tuhle doplňkovou výbavu půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova – ozvi se nám, dohodneme se. Platí se na místě při převzetí QR kódem (platbu v hotovosti nepřijímáme).</div>$n$),
    -- „Půjčujete také přívěsný vozík, když si chci motorku sám dopravit na místo?“ · Odpověď říkala, že při rezervaci na webu stojí vozík 900 Kč/den. Rezervační formulář na webu ho ale k motorce účtuje za 400 Kč/den; 900 Kč/den stojí jen samostatně. Doplněno, že vozík jde přidat jen k motorce z Mezné.
    (3, '95e0adda-55d9-4bfb-a13c-97e6ae04581e', 'answer', 'full', $o$Ano, máme k dispozici i přívěsný vozík zn. Temared na 3 motorky.&nbsp;<div>V případě, že si u nás půjčíš i motorku a rezervaci provedeš přes naši aplikaci, přívěs si můžeš vypůjčit zadarmo. Pokud si chceš půjčit čistě jen přívěs a nebo rezervuješ přes web, můžeš, cena za 1 den výpůjčky je pak 900 Kč.&nbsp;</div>$o$,
      $n$Ano, máme k dispozici přívěsný vozík zn. Temared na 3 motorky. K motorce z obslužné pobočky v Mezné si ho při rezervaci v aplikaci přidáš zdarma, při rezervaci na webu stojí 400 Kč za den. Samotný vozík bez motorky si půjčíš za 900 Kč za den.$n$),
    -- „Vyplatí se rezervovat přes appku?“ · Vozík je v aplikaci zdarma ke každé rezervaci motorky z Mezné, ne až „od vyšších ranků“. Od vyššího ranku jsou zdarma výbava spolujezdce a boty.
    (4, 'c81ffa71-82fb-4ee9-9171-9447d199583b', 'answer', 'full', $o$Ano, rozhodně. Už při první rezervaci máš přes aplikaci věrnostní slevu. Ta postupně narůstá - s každou další výpůjčkou u MotoGo24 jezdíš levněji. Navíc aplikace nabízí různé benefity. Od vyšších ranků budeš mít např. i zapůjčení výbavy pro spolujezdce zadarmo nebo si můžeš k motorce zapůjčit přívěs na 3 motorky - také zadarmo.&nbsp;$o$,
      $n$Ano, rozhodně. V aplikaci máš věrnostní slevu už při první rezervaci a s dalšími výpůjčkami postupně roste. Od vyšších ranků máš navíc zdarma výbavu pro spolujezdce i boty. A k motorce z obslužné pobočky v Mezné si v aplikaci zdarma přidáš přívěsný vozík na 3 motorky.$n$),
    -- „Mohu vrátit motorku jinde, než byla převzata?“ · „500 Kč za nakládku/vykládku a 20 Kč/km“ vypadalo jako 500 Kč + 20 Kč/km. Systém počítá 1 000 Kč + 40 Kč za každý km trasy z Mezné (= 500 + 500 + 20 Kč/km tam i zpět).
    (5, 'dac51062-20c0-4ea9-8422-54720f27b87e', 'answer', 'full', $o$Ano, vrácení na jiném místě je možné v rámci celé ČR. Cena se řídí stejným ceníkem jako přistavení – 500 Kč za nakládku/vykládku a 20 Kč/km od Mezné u Pelhřimova. Nebo můžeš motorku vrátit přímo u nás na pobočce. Vrácení jinde ale neplatí pro motorky ze samoobslužné pobočky ve Velkých Němčicích – ty se přebírají i vracejí jen přímo na této pobočce.&nbsp;$o$,
      $n$Ano, motorky z obslužné pobočky v Mezné u Pelhřimova si od tebe vyzvedneme kdekoli v ČR. Cena je stejná jako u přistavení: 500 Kč za naložení, 500 Kč za vyložení a 20 Kč za každý kilometr z Mezné na místo vrácení a zpět (v rezervaci to uvidíš jako 1 000 Kč + 40 Kč za km trasy). Motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají i vracejí jen přímo na této pobočce.$n$),
    -- „Můžu dárkový poukaz uplatnit na nákup ve vašem e-shopu?“ · Slevový kód půjde nově uplatnit i při nákupu dárkového poukazu (schváleno 27. 11.) – věta, že to nejde, by přestala platit.
    (6, '78d4791f-d161-41eb-b754-6a3c732f2ea6', 'answer', 'phrase', $o$V e-shopu lze použít pouze slevový (promo) kód a ten nelze uplatnit na nákup dárkového poukazu.$o$,
      $n$V e-shopu lze použít pouze slevový (promo) kód.$n$)
    ) AS x(ord, id, field, how, old, new)
    ORDER BY ord
  LOOP
    UPDATE public.faq_items
       SET answer = CASE WHEN r.field <> 'answer' THEN answer
                         WHEN r.how = 'phrase' THEN replace(answer, r.old, r.new) ELSE r.new END,
           question = CASE WHEN r.field <> 'question' THEN question
                           WHEN r.how = 'phrase' THEN replace(question, r.old, r.new) ELSE r.new END
     WHERE id = r.id::uuid
       AND CASE WHEN r.how = 'phrase'
                THEN strpos(CASE WHEN r.field = 'answer' THEN answer ELSE question END, r.old) > 0
                 AND strpos(CASE WHEN r.field = 'answer' THEN answer ELSE question END, r.new) = 0
                ELSE (CASE WHEN r.field = 'answer' THEN answer ELSE question END) = r.old END;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSE
      SELECT CASE WHEN r.field = 'answer' THEN answer ELSE question END INTO v_cur FROM public.faq_items WHERE id = r.id::uuid;
      IF NOT FOUND THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_fixes_1: faq % PŘESKOČENO – otázka v faq_items neexistuje', r.id;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_fixes_1: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.id, r.field, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_fixes_1: faq_items změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
