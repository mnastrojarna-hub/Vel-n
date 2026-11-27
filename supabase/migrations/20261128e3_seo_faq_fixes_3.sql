-- =============================================================================
-- 20261128e3_seo_faq_fixes_3.sql
-- datová migrace (bez změn schématu): časté dotazy (faq_items) – gramatika, překlepy, tykání, formátování; skrytí jedné zastaralé a jedné duplicitní otázky (část 3/3).
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
    -- „Jak se počítá den nájmu?“ · Nadbytečné „h“ za časy a lomítkový tvar „sjednal/a“; upřesněno, že příklad platí pro jednodenní výpůjčku.
    (1, 'a38702a7-013a-470e-a890-3499277ecb06', 'answer', 'full', $o$Platí od 0:00 h do 24:00 h téhož dne, na který sis sjednal/a rezervaci. Pokud si vyzvedneš motorku např. v 15:00 h, musíš ji vrátit nejpozději do 24:00 h toho samého dne.&nbsp;$o$,
      $n$Den nájmu trvá od 0:00 do 24:00 dne, na který máš rezervaci. Když si motorku na jeden den vyzvedneš třeba v 15:00, vrátíš ji nejpozději do 24:00 téhož dne.$n$),
    -- „Poskytujete slevy na týdenní nebo několikatýdenní pronájmy?“ · Překlep „Nesposkytujeme“ a věta bez hlavní věty; doplněno, že věrnostní sleva je v aplikaci.
    (2, '7c27d75f-25f8-45ff-a2ea-34c6a176ad55', 'answer', 'phrase', $o$Nesposkytujeme. Poskytujeme věrnostní slevy. Protože chceme odměňovat naše stálé zákazníky.$o$,
      $n$Neposkytujeme. Místo toho odměňujeme stálé zákazníky věrnostní slevou v aplikaci.$n$),
    -- „Jak probíhá převzetí motorky v půjčovně?“ · Překlep „ve skřínce“.
    (3, '333ae882-1e32-4d8e-818e-027e48af5c35', 'answer', 'phrase', $o$ve skřínce$o$,
      $n$ve skříňce$n$),
    -- „Půjčujete také tankvaky?“ · Překlep „na zdarma“.
    (4, '3dd75843-9961-4509-9386-2921ece7587a', 'answer', 'phrase', $o$Půjčíme je na zdarma$o$,
      $n$Půjčíme je zdarma$n$),
    -- „Můžete motorku přistavit k hotelu/na nádraží?“ · Pád: „skládá se z poplatku … a sazby“.
    (5, 'd2051db9-f4d6-4d24-9009-c3df6be6fd45', 'answer', 'phrase', $o$(2 × 500 Kč) a sazba 20 Kč/km$o$,
      $n$(2 × 500 Kč) a sazby 20 Kč/km$n$),
    -- „Půjčujete také nepromoky?“ · Tykání.
    (6, '16fde840-124b-4d9b-9b28-8fef51f6cd63', 'answer', 'phrase', $o$Výbavu do deště vám rádi zapůjčíme$o$,
      $n$Výbavu do deště ti rádi zapůjčíme$n$),
    -- „Půjčujete také nepromoky?“ · Tykání.
    (7, '16fde840-124b-4d9b-9b28-8fef51f6cd63', 'answer', 'phrase', $o$tam si můžete půjčit jen$o$,
      $n$tam si můžeš půjčit jen$n$),
    -- „Nabízíte slevu při odpoledním vyzvednutí?“ · Tykání.
    (8, '822fd461-7ba5-44ee-84c8-c728cf085656', 'answer', 'phrase', $o$nemůžete vyzvednout ráno$o$,
      $n$nemůžeš vyzvednout ráno$n$),
    -- „Mají vaše motorky držák na telefon?“ · Tykání.
    (9, '40352c8d-4080-42a0-bc8a-77264c850d7e', 'answer', 'phrase', $o$nic za něj neplatíte$o$,
      $n$nic za něj neplatíš$n$),
    -- „Můžu si vybrat motorku z Mezné a nechat si ji přistavit do Velkých Němčic?“ · Tykání.
    (10, '5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c05', 'answer', 'phrase', $o$si můžete půjčit jen motorky$o$,
      $n$si můžeš půjčit jen motorky$n$),
    -- „Můžu si vybrat motorku z Mezné a nechat si ji přistavit do Velkých Němčic?“ · Tykání.
    (11, '5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c05', 'answer', 'phrase', $o$uvidíte v rezervaci$o$,
      $n$uvidíš v rezervaci$n$),
    -- „Jakým způsobem se vyčísluje škoda u drobných poškození? Pokud by došlo např. k poškrábání plastů, vycházíte z ceníku dílů, nebo z faktury z autorizovaného servisu? Jak se vyčíslují spoluúčasti?“ · Pryč prázdná odrážka na konci odpovědi (text beze změny).
    (12, 'b27221f5-dc55-4bf7-b320-c70b267c6a76', 'answer', 'full', $o$<p>Díky našemu <strong>100% smluvnímu krytí škod je spoluúčast 0 Kč.</strong> Pokud tedy motorku poškodíš vlastní vinou (včetně drobností jako poškrábané plasty), za běžných okolností <strong>neplatíš nic</strong> — náklady nese půjčovna.</p>
<p>Náhradu škody bys hradil/a jen ve výjimečných případech, kdy se krytí neuplatní — tedy když poškození vznikne porušením podmínek (jízda pod vlivem, bez oprávnění, úmyslné poškození) nebo u odcizení motorky. Dále se smluvní krytí nevztahuje na ztrátu nebo nadměrné poničení zapůjčené výbavy (např. bunda, kalhoty, nepromoky apod.).</p>
<ul>
<li><br></li></ul>$o$,
      $n$<p>Díky našemu <strong>100% smluvnímu krytí škod je spoluúčast 0 Kč.</strong> Pokud tedy motorku poškodíš vlastní vinou (včetně drobností jako poškrábané plasty), za běžných okolností <strong>neplatíš nic</strong> — náklady nese půjčovna.</p>
<p>Náhradu škody bys hradil/a jen ve výjimečných případech, kdy se krytí neuplatní — tedy když poškození vznikne porušením podmínek (jízda pod vlivem, bez oprávnění, úmyslné poškození) nebo u odcizení motorky. Dále se smluvní krytí nevztahuje na ztrátu nebo nadměrné poničení zapůjčené výbavy (např. bunda, kalhoty, nepromoky apod.).</p>$n$),
    -- „Jak se počítá den nájmu?“ · Otázka: pryč neviditelná mezera na konci.
    (13, 'a38702a7-013a-470e-a890-3499277ecb06', 'question', 'full', $o$Jak se počítá den nájmu?&nbsp;$o$,
      $n$Jak se počítá den nájmu?$n$),
    -- „Jaká je minimální doba výpůjčky?“ · Otázka: pryč neviditelná mezera na konci.
    (14, '76ac05d1-65d6-426b-a8c3-da192e7fb82f', 'question', 'full', $o$Jaká je minimální doba výpůjčky?&nbsp;$o$,
      $n$Jaká je minimální doba výpůjčky?$n$),
    -- „Půjčujete také nepromoky?“ · Otázka: pryč neviditelná mezera na konci.
    (15, '16fde840-124b-4d9b-9b28-8fef51f6cd63', 'question', 'full', $o$Půjčujete také nepromoky?&nbsp;$o$,
      $n$Půjčujete také nepromoky?$n$),
    -- „Půjčujete také tankvaky?“ · Otázka: pryč neviditelná mezera na konci.
    (16, '3dd75843-9961-4509-9386-2921ece7587a', 'question', 'full', $o$Půjčujete také tankvaky?&nbsp;$o$,
      $n$Půjčujete také tankvaky?$n$),
    -- „Můžu s vaší motorkou absolvovat základní kurz motoškoly?“ · Otázka: pryč neviditelná mezera na konci.
    (17, '7d72e4b0-e2ff-4713-99a7-6bdaf44d924b', 'question', 'full', $o$Můžu s vaší motorkou absolvovat základní kurz motoškoly?&nbsp;$o$,
      $n$Můžu s vaší motorkou absolvovat základní kurz motoškoly?$n$),
    -- „Můžu vzít spolujezdce?“ · Otázka: pryč neviditelná mezera na konci.
    (18, '92fb7f7a-f82b-415c-8d8f-0dc012899b73', 'question', 'full', $o$Můžu vzít spolujezdce?&nbsp;$o$,
      $n$Můžu vzít spolujezdce?$n$),
    -- „Máte nějaký limit km na den?“ · Otázka: pryč neviditelná mezera na konci.
    (19, 'a2e964db-1263-40cb-86ff-6420c0841e56', 'question', 'full', $o$Máte nějaký limit km na den?&nbsp;$o$,
      $n$Máte nějaký limit km na den?$n$),
    -- „Lze poukaz objednat i na firmu?“ · Otázka: pryč neviditelná mezera na konci.
    (20, '780628c8-34ab-4a86-96da-2b46f5529594', 'question', 'full', $o$Lze poukaz objednat i na firmu?&nbsp;$o$,
      $n$Lze poukaz objednat i na firmu?$n$)
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
        RAISE NOTICE 'faq_fixes_3: faq % PŘESKOČENO – otázka v faq_items neexistuje', r.id;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_fixes_3: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.id, r.field, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_fixes_3: faq_items změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- Zastaralá / duplicitní otázka: jen skrýt (published = false), řádek zůstává a ve Velínu jde znovu
-- zapnout. Skryje se jen otázka, která má dosud přesně toto znění a je zveřejněná.
DO $$
DECLARE
  r record;
  n integer;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
    -- Yamaha Niken už v nabídce není (motorka je vyřazená a v katalogu se nezobrazuje).
    ('06e44d78-8b32-4b96-9f54-339ad771f754', $q$Mohu Yamahu Niken řídit s řidičským oprávněním sk. B?$q$),
    -- Stejná otázka jinými slovy jako „Mohu vrátit motorku jinde, než byla převzata?“ – odpověď tam je celá.
    ('19b96b98-8f06-485b-9748-b196de636132', $q$Co když chci motorku vyzvednout v motopůjčovně, ale vrátit jinde – jde to?$q$)
    ) AS x(id, question)
  LOOP
    UPDATE public.faq_items SET published = false
     WHERE id = r.id::uuid AND published = true AND question = r.question;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSIF EXISTS (SELECT 1 FROM public.faq_items WHERE id = r.id::uuid AND published = false) THEN
      n_done := n_done + 1;
    ELSE
      n_skip := n_skip + 1;
      RAISE NOTICE 'faq_fixes_3: faq % PŘESKOČENO – otázka neexistuje nebo ji někdo mezitím přepsal', r.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_fixes_3: skryto otázek %, už skryto %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
