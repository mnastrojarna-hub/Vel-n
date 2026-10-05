-- =============================================================================
-- Živé šablony e-mailů z Velína (App i Web): texty univerzálně pro obslužnou i
-- samoobslužnou pobočku + proměnná {{door_codes_block}} místo napevno vepsaných kódů
-- Migrace: 20261005a_velin_templates_universal_codes.sql (DATA — bez změn schématu)
--
-- Zadání majitele 2026-10-05: „maily jsou jak pro app tak pro web — všech, kterých se to
-- týká (kódy, obsluha, samoobsluha), musí být univerzálně napsané, a pokud obsahují kódy
-- a motorka je na samoobsluze, musí tam být kód brány s popisem postupu.“
-- Majitel poslal živá těla šablon (texty psané ve Velínu, tykání) — náhrady jsou proto
-- CÍLENÉ na jeho přesné věty; jiný text se nemění (pokyn „jen doplň větu nebo proměnnou“).
-- Řádek, kde věta chybí, zůstane netknutý (NOTICE).
--
-- booking_missing_docs (chodí JEN zákazníkům samoobsluhy — send_abandoned_booking_emails
--   Path C): „nepovinný krok … V opačném případě ověříme doklady až na místě“ říkalo opak
--   pravidla → nahrání nutné, bez dokladů kódy ani vstup; obslužná = ověříme na místě.
-- booking_reserved (App) / web_booking_reserved (Web): „doklady ti zkontrolujeme přímo na
--   místě“, „při převzetí ověříme pouze kódy“ / „stačí nahlásit kódy“, „Předáme ti motorku …
--   v kabince … společně podepíšeme protokol“, „uložíme … do uzamykatelné skříňky“ = jen
--   Mezná → věty pro obě pobočky. Místo prázdného seznamu (App) / neznámé proměnné
--   {{pickup_code}} (Web; vykreslovala se jako nic) proměnná {{door_codes_block}}: vydané
--   kódy (u pobočky s bránou brána → šatna (dveře č. 8) → motorka + postup), nebo výzva
--   k nahrání dokladů — stejný blok, jaký do mailů dává edge send-booking-email.
-- door_codes / web_door_codes: dva napevno vepsané boxy „Kód k motorce / Kód k výbavě“
--   → {{door_codes_block}} (dřív edge u pobočky s bránou blok připojil na konec a kódy
--   motorky/šatny byly v mailu dvakrát); věta „stačí nahlásit na pobočce“ univerzálně.
-- Změněným šablonám se vynuluje cache překladů body_translations (AI překlad znovu,
-- placeholdery zachovává). Idempotentní (po nahrazení se vzory už nevyskytují).
-- =============================================================================

DO $$
DECLARE
  v_slug text;
  rr record;
  v_body text;
  v_new text;
  v_hits integer;
BEGIN
  FOR v_slug IN SELECT DISTINCT t.slug FROM (VALUES
    ('booking_missing_docs','lit','můžeš ještě nahrát své doklady (občanku/pas + řidičský průkaz). Jedná se o nepovinný krok, ale zabere jen chvilku.','nahraj prosím své doklady (občanku/pas + řidičský průkaz). Zabere to jen chvilku.'),
    ('booking_missing_docs','lit','V opačném případě ověříme doklady až na místě.','Na samoobslužné pobočce je nahrání dokladů nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak ověříme až na místě.'),
    ('booking_reserved','lit','(pokud už máš ověřené doklady) ti dorazí v dalším e-mailu.','(pokud už máš ověřené doklady) najdeš níže a dorazí ti i samostatným e-mailem.'),
    ('booking_reserved','lit','Pokud jsi ověření přeskočil/a, doklady ti zkontrolujeme přímo na místě, nebo je ještě můžeš nahrát v menu Moje doklady.','Pokud jsi ověření přeskočil/a, nahraj doklady ještě v menu Moje doklady. Na samoobslužné pobočce je to nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak zkontrolujeme přímo na místě.'),
    ('booking_reserved','lit','Jestli jsi doklady nahrál/a, při převzetí motorky ověříme pouze kódy. V opačném případě si připrav:','Jestli jsi doklady nahrál/a, při převzetí stačí kódy — na obslužné pobočce je nahlásíš obsluze, na samoobslužné je zadáš na displeji. Bez nahraných dokladů si na obslužnou pobočku připrav:'),
    ('booking_reserved','lit','<h4><ul><ul><li><br></li></ul></ul></h4>','{{door_codes_block}}'),
    ('booking_reserved','rx','Předáme ti motorku a objednanou výbavu \(obléknout se můžeš u nás v kabince\) a(?:&nbsp;|\s|\u00a0)*společně podepíšeme předávací protokol\. Celé to zabere pár minut\.','Na obslužné pobočce ti motorku a objednanou výbavu předáme osobně (obléknout se můžeš u nás v kabince) a společně podepíšeme předávací protokol. Na samoobslužné pobočce si motorku i výbavu převezmeš sám/sama pomocí kódů — výbava je v šatně (dveře č. 8) a předávací protokol podepíšeš na dotykovém displeji. Celé to zabere pár minut.'),
    ('booking_reserved','lit','uložíme ti je u nás zdarma do uzamykatelné skříňky.','na obslužné pobočce v Mezné ti je u nás zdarma uložíme do uzamykatelné skříňky.'),
    ('web_booking_reserved','lit','(pokud jsi nahrál/a doklady) ti dorazí v dalším e-mailu.','(pokud jsi nahrál/a doklady) najdeš níže a dorazí ti i samostatným e-mailem.'),
    ('web_booking_reserved','lit','Pokud jsi nahrání dokladů přeskočil/a, doklady ti zkontrolujeme přímo na místě nebo je ještě můžeš nahrát v sekci Upravit rezervaci.','Pokud jsi nahrání dokladů přeskočil/a, nahraj je ještě v sekci Upravit rezervaci. Na samoobslužné pobočce je to nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak zkontrolujeme přímo na místě.'),
    ('web_booking_reserved','lit','Pro převzetí motorky na pobočce si připrav: (pokud jsi doklady nenahrál/a ani dodatečně):','Pro převzetí motorky na obslužné pobočce si připrav (pokud jsi doklady nenahrál/a ani dodatečně):'),
    ('web_booking_reserved','lit','V případě, že jsi doklady nahrál/a, převzetí motorky bude opravdu rychlé. Stačí, když nám nahlásíš kódy.','V případě, že jsi doklady nahrál/a, převzetí motorky bude opravdu rychlé: na obslužné pobočce stačí nahlásit kódy obsluze, na samoobslužné je zadáš na dotykovém displeji.'),
    ('web_booking_reserved','lit','<h3><strong>{{pickup_code}}</strong></h3>','{{door_codes_block}}'),
    ('web_booking_reserved','lit','{{pickup_code}}','{{door_codes_block}}'),
    ('door_codes','lit','jsou nyní k dispozici přístupové kódy. Při převzetí motorky je stačí nahlásit na pobočce.','jsou nyní k dispozici přístupové kódy. Na obslužné pobočce je při převzetí stačí nahlásit obsluze, na samoobslužné pobočce je zadáš na dotykovém displeji.'),
    ('door_codes','rx','<div style="background:#dcfce7[^>]*?>.*?\{\{door_code_gear\}\}</div>(?:\s|<br>)*</div>','{{door_codes_block}}'),
    ('web_door_codes','rx','<div style="background:#dcfce7[^>]*?>.*?\{\{door_code_gear\}\}</div>(?:\s|<br>)*</div>','{{door_codes_block}}')
  ) AS t(slug, kind, old, new) ORDER BY 1 LOOP
    SELECT body_html INTO v_body FROM public.email_templates WHERE slug = v_slug;
    IF v_body IS NULL THEN
      RAISE NOTICE '20261005a: % — šablona neexistuje, přeskočeno', v_slug;
      CONTINUE;
    END IF;
    v_new := v_body; v_hits := 0;
    FOR rr IN SELECT * FROM (VALUES
    ('booking_missing_docs','lit','můžeš ještě nahrát své doklady (občanku/pas + řidičský průkaz). Jedná se o nepovinný krok, ale zabere jen chvilku.','nahraj prosím své doklady (občanku/pas + řidičský průkaz). Zabere to jen chvilku.'),
    ('booking_missing_docs','lit','V opačném případě ověříme doklady až na místě.','Na samoobslužné pobočce je nahrání dokladů nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak ověříme až na místě.'),
    ('booking_reserved','lit','(pokud už máš ověřené doklady) ti dorazí v dalším e-mailu.','(pokud už máš ověřené doklady) najdeš níže a dorazí ti i samostatným e-mailem.'),
    ('booking_reserved','lit','Pokud jsi ověření přeskočil/a, doklady ti zkontrolujeme přímo na místě, nebo je ještě můžeš nahrát v menu Moje doklady.','Pokud jsi ověření přeskočil/a, nahraj doklady ještě v menu Moje doklady. Na samoobslužné pobočce je to nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak zkontrolujeme přímo na místě.'),
    ('booking_reserved','lit','Jestli jsi doklady nahrál/a, při převzetí motorky ověříme pouze kódy. V opačném případě si připrav:','Jestli jsi doklady nahrál/a, při převzetí stačí kódy — na obslužné pobočce je nahlásíš obsluze, na samoobslužné je zadáš na displeji. Bez nahraných dokladů si na obslužnou pobočku připrav:'),
    ('booking_reserved','lit','<h4><ul><ul><li><br></li></ul></ul></h4>','{{door_codes_block}}'),
    ('booking_reserved','rx','Předáme ti motorku a objednanou výbavu \(obléknout se můžeš u nás v kabince\) a(?:&nbsp;|\s|\u00a0)*společně podepíšeme předávací protokol\. Celé to zabere pár minut\.','Na obslužné pobočce ti motorku a objednanou výbavu předáme osobně (obléknout se můžeš u nás v kabince) a společně podepíšeme předávací protokol. Na samoobslužné pobočce si motorku i výbavu převezmeš sám/sama pomocí kódů — výbava je v šatně (dveře č. 8) a předávací protokol podepíšeš na dotykovém displeji. Celé to zabere pár minut.'),
    ('booking_reserved','lit','uložíme ti je u nás zdarma do uzamykatelné skříňky.','na obslužné pobočce v Mezné ti je u nás zdarma uložíme do uzamykatelné skříňky.'),
    ('web_booking_reserved','lit','(pokud jsi nahrál/a doklady) ti dorazí v dalším e-mailu.','(pokud jsi nahrál/a doklady) najdeš níže a dorazí ti i samostatným e-mailem.'),
    ('web_booking_reserved','lit','Pokud jsi nahrání dokladů přeskočil/a, doklady ti zkontrolujeme přímo na místě nebo je ještě můžeš nahrát v sekci Upravit rezervaci.','Pokud jsi nahrání dokladů přeskočil/a, nahraj je ještě v sekci Upravit rezervaci. Na samoobslužné pobočce je to nutné — bez ověřených dokladů ti kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti je jinak zkontrolujeme přímo na místě.'),
    ('web_booking_reserved','lit','Pro převzetí motorky na pobočce si připrav: (pokud jsi doklady nenahrál/a ani dodatečně):','Pro převzetí motorky na obslužné pobočce si připrav (pokud jsi doklady nenahrál/a ani dodatečně):'),
    ('web_booking_reserved','lit','V případě, že jsi doklady nahrál/a, převzetí motorky bude opravdu rychlé. Stačí, když nám nahlásíš kódy.','V případě, že jsi doklady nahrál/a, převzetí motorky bude opravdu rychlé: na obslužné pobočce stačí nahlásit kódy obsluze, na samoobslužné je zadáš na dotykovém displeji.'),
    ('web_booking_reserved','lit','<h3><strong>{{pickup_code}}</strong></h3>','{{door_codes_block}}'),
    ('web_booking_reserved','lit','{{pickup_code}}','{{door_codes_block}}'),
    ('door_codes','lit','jsou nyní k dispozici přístupové kódy. Při převzetí motorky je stačí nahlásit na pobočce.','jsou nyní k dispozici přístupové kódy. Na obslužné pobočce je při převzetí stačí nahlásit obsluze, na samoobslužné pobočce je zadáš na dotykovém displeji.'),
    ('door_codes','rx','<div style="background:#dcfce7[^>]*?>.*?\{\{door_code_gear\}\}</div>(?:\s|<br>)*</div>','{{door_codes_block}}'),
    ('web_door_codes','rx','<div style="background:#dcfce7[^>]*?>.*?\{\{door_code_gear\}\}</div>(?:\s|<br>)*</div>','{{door_codes_block}}')
    ) AS t(slug, kind, old, new) WHERE t.slug = v_slug LOOP
      -- placeholder bloku kódů vkládat jen jednou (šablona už ho může mít)
      IF rr.new = '{{door_codes_block}}' AND position('{{door_codes_block}}' IN v_new) > 0 THEN CONTINUE; END IF;
      IF rr.kind = 'lit' THEN
        IF position(rr.old IN v_new) > 0 THEN
          v_new := replace(v_new, rr.old, rr.new); v_hits := v_hits + 1;
        END IF;
      ELSE
        IF v_new ~ rr.old THEN
          v_new := regexp_replace(v_new, rr.old, rr.new); v_hits := v_hits + 1;
        END IF;
      END IF;
    END LOOP;
    IF v_hits > 0 THEN
      UPDATE public.email_templates
         SET body_html = v_new, body_translations = '{}'::jsonb, updated_at = now()
       WHERE slug = v_slug;
      RAISE NOTICE '20261005a: % — nahrazeno % míst', v_slug, v_hits;
    ELSE
      RAISE NOTICE '20261005a: % — nic k nahrazení (text už univerzální nebo jiný než zadaný)', v_slug;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
