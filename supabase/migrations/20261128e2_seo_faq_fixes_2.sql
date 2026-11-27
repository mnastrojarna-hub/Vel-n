-- =============================================================================
-- 20261128e2_seo_faq_fixes_2.sql
-- datová migrace (bez změn schématu): časté dotazy (faq_items) – doklady, řidičský průkaz, policie při nehodě, velikosti – soulad se systémem a obchodními podmínkami (část 2/3).
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
-- Skupina B u skútrů se do odpovědí NEDOPLŇUJE: živá funkce create_web_booking ji na webu odmítá
-- (kontroluje jen license_required = A1); nejdřív je potřeba opravit tuto funkci.
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
    -- „Co mám dělat, když má motorka cestou poruchu, nebo se mi stane nehoda?“ · Obchodní podmínky (čl. 6 e) i smlouva říkají, že policii je nutné přivolat vždy, a je to podmínka krytí škod. Rada „u drobných škod stačí zavolat nám“ by zákazníka mohla o krytí připravit.
    (1, 'a278501f-331d-4b53-a298-22eba57451ea', 'answer', 'phrase', $o$Policii volej vždy, když to vyžaduje zákon – tedy zejména při zranění, škodě nad 100 000 Kč, škodě na cizím majetku nebo když se účastníci nedohodnou. U drobných škod, které nejsou nehodou podle zákona, stačí ozvat se nám a postupovat podle dohody.$o$,
      $n$Policii volej vždy – je to i podmínka 100% smluvního krytí škod (obchodní podmínky, čl. 6 a 7).$n$),
    -- „Jaký řidičský průkaz potřebuji?“ · Chyběly skútry 125 ccm (skupina A1).
    (2, '9446abc2-3308-484f-b255-bc425f3d3d52', 'answer', 'full', $o$Záleží na tom, jakou motorku si vybereš – u každého modelu je přímo v nabídce uvedeno, jaké řidičské oprávnění je potřeba. Silnější stroje vyžadují skupinu A, slabší skupinu A2. Na dětské motorky řidičský průkaz nepotřebuješ.$o$,
      $n$Záleží na motorce – potřebnou skupinu najdeš u každého modelu v katalogu. Silnější motorky vyžadují skupinu A, slabší A2 a na skútry 125 ccm stačí A1. Na dětské motorky řidičský průkaz nepotřebuješ.$n$),
    -- „Od kolika let a s jakou praxí si u vás můžu půjčit motorku?“ · Chyběla skupina A1 (skútry 125 ccm).
    (3, '753cbff4-046c-4807-abf3-018a1e201766', 'answer', 'phrase', $o$(A2 nebo A podle motorky)$o$,
      $n$(A, A2 nebo A1 podle motorky)$n$),
    -- „Jaké doklady potřebuji?“ · Chyběla skupina A1 (skútry 125 ccm).
    (4, '732b6abe-a788-4fa5-b3a2-bd0ddfc371f0', 'answer', 'phrase', $o$(A/A2 dle motorky)$o$,
      $n$(A, A2 nebo A1 podle motorky)$n$),
    -- „Můžu si půjčit motorku i se zahraničním řidičským průkazem?“ · Výčet „A/A2“ byl neúplný (skútry jsou na A1); pryč prázdný nadpis na konci odpovědi.
    (5, 'e18a59ca-f1f5-42ff-9f06-522af9b08b65', 'answer', 'full', $o$<p>Ano, to není problém. Potřebuješ jen platný řidičský průkaz odpovídající skupiny (A/A2) a doklad totožnosti (OP nebo cestovní pas).&nbsp;</p>
<h3></h3>$o$,
      $n$<p>Ano, to není problém. Potřebuješ jen platný řidičský průkaz skupiny, kterou vybraná motorka vyžaduje (najdeš ji v katalogu), a doklad totožnosti (OP nebo cestovní pas).</p>$n$),
    -- „Jaké velikosti výbavy nabízíte?“ · Na samoobslužné pobočce se helmy půjčují od velikosti S (pravidlo z 10. 10., drží ho web, aplikace i kiosk).
    (6, 'ee1a5c2f-6eea-4db3-b012-b4d3d01ce0b6', 'answer', 'phrase', $o$<div>Helma - XS-3XL</div>$o$,
      $n$<div>Helma - XS-3XL (samoobslužná pobočka Velké Němčice: od S)</div>$n$)
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
        RAISE NOTICE 'faq_fixes_2: faq % PŘESKOČENO – otázka v faq_items neexistuje', r.id;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_fixes_2: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.id, r.field, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_fixes_2: faq_items změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
