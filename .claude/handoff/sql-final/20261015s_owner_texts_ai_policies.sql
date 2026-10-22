-- =============================================================================
-- 20261015s_owner_texts_ai_policies.sql
-- datová migrace (bez změn schématu): AI asistent webu (postup rezervace) a pravidlo paliva/mytí pro AI.
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- ai_public_agent_config.system_prompt: krok 4 nabízel převzetí jen v Mezné / přistavení → znění výchozí
-- hodnoty Velínu (WebAgentSettingsPanel.jsx, obě pobočky); krok 5: odvoz jen u motorek z Mezné.
-- site.policies.fuel (čte AI přes get_policies): k vašemu textu z 12. 10. doplněno, že na samoobsluze
-- rezerva svítit nesmí a že umytá se vrací jen ve Velkých Němčicích.
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
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- klíč app_settings, cesta k textovému listu JSON, how + old:
  --   'full'   = celý živý list má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --   'phrase' = věta old (v listu jednou) se nahradí new, zbytek listu zůstává
  FOR f IN
    SELECT * FROM (VALUES
    ('ai_public_agent_config', '{system_prompt}', 'phrase', $t$4. Vyzvednutí: na pobočce Mezná, nebo přistavení? (Pokud přistavení, zeptej se na adresu — jde do delivery_address.)$t$, $t$4. Vyzvednutí: kde? Obslužná pobočka Mezná u Pelhřimova (odtud i přistavení na adresu → delivery_address), nebo samoobslužná pobočka Velké Němčice u Brna (jen přímo na pobočce, bez přistavení). Pobočku určuje vybraná motorka (search_motorcycles / get_branches).$t$),
    ('ai_public_agent_config', '{system_prompt}', 'phrase', $t$5. Vrácení: stejně jako vyzvednutí, nebo jinak? (return_address jen pokud mimo provozovnu.)$t$, $t$5. Vrácení: stejně jako vyzvednutí, nebo jinak? (return_address jen pokud mimo provozovnu — jen u motorek z Mezné; motorky z Velkých Němčic se vracejí jen na tuto pobočku.)$t$),
    ('site.policies', '{fuel}', 'full', '997f14ddf71d7d97378e6e764210c66b', $t$Stav paliva neřešíme — nádrž nemusí být při převzetí plná, tankuješ si sám podle potřeby. Vracet natankovanou ji nemusíš, jen ať nesvítí kontrolka rezervy (na samoobslužné pobočce Velké Němčice svítit nesmí). Nic se nedoplácí. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích; v Mezné ani při vrácení jinde ji mýt nemusíš.$t$)
    ) AS x(k, path, how, old, new)
  LOOP
    UPDATE public.app_settings
       SET value = jsonb_set(value, f.path::text[], to_jsonb(CASE WHEN f.how = 'phrase'
                     THEN replace(value #>> f.path::text[], f.old, f.new) ELSE f.new END), false),
           updated_at = now()
     WHERE key = f.k AND jsonb_typeof(value) = 'object'
       AND jsonb_typeof(value #> f.path::text[]) = 'string'
       AND CASE WHEN f.how = 'phrase' THEN strpos(value #>> f.path::text[], f.old) > 0
                                       AND strpos(value #>> f.path::text[], f.new) = 0
                ELSE md5(value #>> f.path::text[]) = f.old END;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> f.path::text[] INTO v_cur FROM public.app_settings WHERE key = f.k;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'ai_policies: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'ai_policies: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
