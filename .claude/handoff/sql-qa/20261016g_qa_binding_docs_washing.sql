-- =============================================================================
-- 20261016g_qa_binding_docs_washing.sql — NÁVRH, ZÁVAZNÉ TEXTY: NEAPLIKOVAT bez výslovného souhlasu majitele
-- VOP v14 čl. 5 l) a nájemní smlouva v11 („Vrácení předmětu nájmu“) dnes říkají, že motorku nikdy není
-- třeba mýt – v rozporu s pravidlem majitele (2026-10-11): na samoobslužné pobočce Velké Němčice musí být
-- motorka vrácena umytá; Mezná a vrácení jinde bez mytí; tankovat nikde, jen nesmí svítit rezerva.
-- Web, e-maily, appka i AI už pravidlo uvádějí – rozpor je jen v závazných dokumentech.
--
-- Nové znění (= návrh v sql/final/PREHLED.md):
--   VOP 5 l): l) Nájemce nemusí předmět nájmu vracet s plnou nádrží, nesmí však svítit kontrolka rezervy paliva. Při vrácení v provozovně pronajímatele s obsluhou (Mezná u Pelhřimova) nebo na jiném sjednaném místě nemusí nájemce předmět nájmu mýt; při vrácení na samoobslužné pobočce (Velké Němčice u Brna) je povinen jej vrátit umytý.
--   Smlouva:  Pronajímatel nevyžaduje, aby byl předmět nájmu vrácen s plnou nádrží; nájemce se však zavazuje vrátit jej alespoň s množstvím paliva mimo režim rezervy (tj. aby nesvítila kontrolka rezervy). Při vrácení v provozovně s obsluhou nebo na jiném sjednaném místě pronajímatel nevyžaduje, aby byl předmět nájmu umytý; při vrácení na samoobslužné pobočce se nájemce zavazuje vrátit předmět nájmu umytý.
-- Změna = nová verze šablony (version + 1, stejně jako uložení ve Velínu). Platí pro nové rezervace;
-- již vygenerované smlouvy/PDF se nemění. Překlady se tím stanou zastaralými (translation_src) → cizí jazyky
-- zobrazí závaznou češtinu, dokud se ve Velínu nespustí „Přeložit chybějící a zastaralé“.
-- Patičku VOP „Mezná 9, 393 01 Mezná“ → „Mezná 9, 393 01 Pelhřimov“ opravuje už samostatně 20261016f
-- (běží dřív, nezávisle na schválení g); náhrada patičky zde zůstává jen jako záloha (po f je bez účinku).
-- Zastaralé překlady smlouvy („nevyžaduje … čistý“) maže navazující 20261016ga (lze i bez tohoto souboru).
-- Bezpečnost: mění se jen když text obsahuje PŘESNĚ původní větu (bílé znaky libovolné) právě jednou.
-- Idempotentní. Bez BEGIN/COMMIT.
-- =============================================================================
DO $$
DECLARE
  c_vop_re constant text := $q$l\)\s+Nájemce\s+nemusí\s+předmět\s+nájmu\s+předávat\s+umytý\s+ani\s+s\s+plnou\s+nádrží,\s+ale\s+nesmí\s+svítit\s+kontrolka\s+rezervy\.$q$;
  c_sml_re constant text := $q$Pronajímatel\s+nevyžaduje,\s+aby\s+byl\s+předmět\s+nájmu\s+vrácen\s+ve\s+stavu\s+čistoty\s+nebo\s+s\s+plnou\s+nádrží\.\s+Nájemce\s+se\s+však\s+zavazuje\s+vrátit\s+předmět\s+nájmu\s+alespoň\s+s\s+množstvím\s+paliva\s+mimo\s+režim\s+rezervy\s+\(tj\.\s+aby\s+nesvítila\s+kontrolka\s+rezervy\)\.$q$;
  c_foot_re constant text := $q$Mezná\s+9,\s+393\s+01\s+Mezná(\s*·)$q$;
  n integer;
  nf integer;
BEGIN
  UPDATE public.document_templates
     SET content_html = regexp_replace(
           regexp_replace(content_html, c_vop_re, $q$l) Nájemce nemusí předmět nájmu vracet s plnou nádrží, nesmí však svítit kontrolka rezervy paliva. Při vrácení v provozovně pronajímatele s obsluhou (Mezná u Pelhřimova) nebo na jiném sjednaném místě nemusí nájemce předmět nájmu mýt; při vrácení na samoobslužné pobočce (Velké Němčice u Brna) je povinen jej vrátit umytý.$q$),
           c_foot_re, $q$Mezná 9, 393 01 Pelhřimov\1$q$),
         version = coalesce(version, 1) + 1
   WHERE type = 'vop' AND active
     AND (SELECT count(*) FROM regexp_matches(content_html, c_vop_re, 'g')) = 1;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'VOP čl. 5 l): upraveno %', n;
  SELECT count(*) INTO nf FROM public.document_templates WHERE type = 'vop' AND active AND content_html ~ c_foot_re;
  IF nf > 0 THEN RAISE NOTICE 'VOP patička: stále „393 01 Mezná“ (% řádků) – 20261016f neproběhl a čl. 5 l) neodpovídal', nf; END IF;
  UPDATE public.document_templates
     SET content_html = regexp_replace(content_html, c_sml_re, $q$Pronajímatel nevyžaduje, aby byl předmět nájmu vrácen s plnou nádrží; nájemce se však zavazuje vrátit jej alespoň s množstvím paliva mimo režim rezervy (tj. aby nesvítila kontrolka rezervy). Při vrácení v provozovně s obsluhou nebo na jiném sjednaném místě pronajímatel nevyžaduje, aby byl předmět nájmu umytý; při vrácení na samoobslužné pobočce se nájemce zavazuje vrátit předmět nájmu umytý.$q$),
         version = coalesce(version, 1) + 1
   WHERE type = 'rental_contract' AND active
     AND (SELECT count(*) FROM regexp_matches(content_html, c_sml_re, 'g')) = 1;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'Smlouva – vrácení předmětu nájmu: upraveno %', n;
END $$;
