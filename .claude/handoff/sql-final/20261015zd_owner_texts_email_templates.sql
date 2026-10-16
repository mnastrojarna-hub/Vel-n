-- =============================================================================
-- 20261015zd_owner_texts_email_templates.sql
-- datová migrace (bez změn schématu): e-mailové šablony Velínu: odstavec o vrácení + aplikace v obou obchodech.
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- Šablony e-mailů z Velína mají přednost před záložním textem v edge send-booking-email/i18n.ts. Kdyby
-- některá ještě obsahovala starý odstavec („… Mytí ani úklid neřešte … Při vrácení s prázdnou nádrží
-- účtujeme dotankování + servisní poplatek dle VOP.“ – poplatek NEEXISTUJE) nebo znění z 2026-10-11,
-- nahradí se (každý výskyt) odstavcem shodným s i18n.ts; potvrzení rezervace dostane před „Vrácení motorky“
-- i řádek s aplikací na Google Play i v App Store (= i18n.ts). Změněné šabloně se vynuluje cache překladů.
-- Šablony nejsou čitelné anon klíčem → nelze ověřit předem; bez shody nic nemění; NOTICE vypíše šablony
-- k ruční kontrole ve Velínu.
--
-- Bezpečnost: mění jen šablony, ve kterých najde starý odstavec (vzory snášejí &nbsp; a &mdash; z editoru
-- Velínu); ostatní šablony nechá být. Idempotentní (2. běh nic nezmění). Bez BEGIN/COMMIT – deploy-sql.yml
-- pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

DO $$
DECLARE
  c_new_formal constant text := $t$Tankovat při vrácení nemusíte (plná nádrž není potřeba) — jen ať nesvítí kontrolka rezervy. Umytou motorku vracejte jen na samoobslužné pobočce ve Velkých Němčicích; na obslužné pobočce v Mezné (i při vrácení na jiném sjednaném místě) ji mýt nemusíte.$t$;
  c_new_informal constant text := $t$Tankovat při vrácení nemusíš (plná nádrž není potřeba) — jen ať nesvítí kontrolka rezervy. Umytou motorku vracej jen na samoobslužné pobočce ve Velkých Němčicích; na obslužné pobočce v Mezné (i při vrácení na jiném sjednaném místě) ji mýt nemusíš.$t$;
  c_app constant text := $t$<p>Aplikaci MotoGo24 stáhnete zdarma pro Android na <a href="https://play.google.com/store/apps/details?id=com.motogo24.app" style="color:#2563eb">Google Play</a> i pro iPhone v <a href="https://apps.apple.com/cz/app/id6806045151" style="color:#2563eb">App Store</a>.</p>$t$;
  c_app_informal constant text := $t$<p>Aplikaci MotoGo24 stáhneš zdarma pro Android na <a href="https://play.google.com/store/apps/details?id=com.motogo24.app" style="color:#2563eb">Google Play</a> i pro iPhone v <a href="https://apps.apple.com/cz/app/id6806045151" style="color:#2563eb">App Store</a>.</p>$t$;
  -- staré odstavce jako regulární výrazy: mezera = libovolné bílé místo i &nbsp; (editor Velínu), — = i &mdash;/&ndash;
  c_ws constant text := '(?:\s|\u00a0|&nbsp;|&#160;)+';
  c_dash constant text := '(?:—|–|&mdash;|&ndash;|&#8212;|&#8211;)';
  c_rx_formal constant text := replace(replace($t$Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřešte — to je naše práce\.(?: Při vrácení s prázdnou nádrží účtujeme dotankování \+ servisní poplatek dle VOP\.)?$t$, ' ', c_ws), '—', c_dash);
  c_rx_informal constant text := replace(replace($t$Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřeš(?: — to je naše práce)?\.(?: Při vrácení s prázdnou nádrží účtujeme dotankování \+ servisní poplatek dle VOP\.)?$t$, ' ', c_ws), '—', c_dash);
  c_rx_1011_formal constant text := replace(replace($t$Na obslužné pobočce v Mezné \(i při vrácení na jiném sjednaném místě\) motorku nemusíte tankovat ani mýt — to je naše práce\. Na samoobslužné pobočce ve Velkých Němčicích ji prosím vraťte umytou a tak, aby nesvítila kontrolka rezervy; plná nádrž není potřeba\.$t$, ' ', c_ws), '—', c_dash);
  c_rx_1011_informal constant text := replace(replace($t$Na obslužné pobočce v Mezné \(i při vrácení na jiném sjednaném místě\) motorku nemusíš tankovat ani mýt — to je naše práce\. Na samoobslužné pobočce ve Velkých Němčicích ji prosím vrať umytou a tak, aby nesvítila kontrolka rezervy; plná nádrž není potřeba\.$t$, ' ', c_ws), '—', c_dash);
  r record;
  v_body text;
  v_h3 text;
  v_left text;
  n_upd integer := 0;
BEGIN
  FOR r IN SELECT id, slug, body_html FROM public.email_templates ORDER BY slug LOOP
    v_body := r.body_html;
    -- (1) původní odstavec – vykání / tykání, s větou o „poplatku za dotankování“ i bez ní; (2) znění
    --     z 2026-10-11 (rezerva jen na samoobsluze), kdyby ho někdo vložil do Velínu.
    --     Vzory snášejí mezery z editoru Velínu (&nbsp; / U+00A0 / zalomení) a pomlčku jako &mdash; / &ndash;;
    --     příznak 'g' nahradí VŠECHNY výskyty (2. běh už nic nenajde).
    v_body := regexp_replace(v_body, c_rx_formal, c_new_formal, 'g');
    v_body := regexp_replace(v_body, c_rx_informal, c_new_informal, 'g');
    v_body := regexp_replace(v_body, c_rx_1011_formal, c_new_formal, 'g');
    v_body := regexp_replace(v_body, c_rx_1011_informal, c_new_informal, 'g');
    -- (3) potvrzení rezervace: řádek „aplikace na Google Play i v App Store“ před nadpis „Vrácení motorky“
    --     (= i18n.ts), jen když šablona aplikaci ještě vůbec nezmiňuje a nadpis je v ní právě jednou
    --     (šablona jen s Google Play se nemění – vypíše se níže k ruční úpravě)
    IF r.slug IN ('booking_reserved', 'web_booking_reserved')
       AND strpos(v_body, 'App Store') = 0 AND strpos(v_body, 'apps.apple.com') = 0
       AND strpos(v_body, 'Google Play') = 0 AND strpos(v_body, 'play.google.com') = 0
       AND (SELECT count(*) FROM regexp_matches(v_body, '<h3[^>]*>Vrácení motorky</h3>', 'g')) = 1 THEN
      v_h3 := substring(v_body FROM '<h3[^>]*>Vrácení motorky</h3>');
      v_body := replace(v_body, v_h3, CASE WHEN strpos(v_body, c_new_informal) > 0 THEN c_app_informal ELSE c_app END
                                      || E'\n' || v_h3);
    END IF;
    IF v_body IS DISTINCT FROM r.body_html THEN
      UPDATE public.email_templates SET body_html = v_body, body_translations = '{}'::jsonb WHERE id = r.id;
      n_upd := n_upd + 1;
      RAISE NOTICE 'email_templates %: text upraven, cache překladů vynulována', r.slug;
    END IF;
  END LOOP;
  RAISE NOTICE 'email_templates: upraveno % šablon', n_upd;
  -- jen informace do logu (ruční kontrola ve Velínu): šablony, které o palivu / mytí píší jinak než
  -- novým odstavcem, a šablony s Google Play bez App Store
  SELECT string_agg(slug, ', ' ORDER BY slug) INTO v_left FROM public.email_templates
   WHERE (subject || ' ' || replace(replace(body_html, c_new_formal, ''), c_new_informal, ''))
         ~* '(tankov|natank|nádrž|nad rezervou|kontrolk[ay] rezervy|mytí|umyt|nemyj|úklid)';
  RAISE NOTICE 'email_templates s textem o palivu/mytí (zkontrolovat ve Velínu): %', coalesce(v_left, '—');
  SELECT string_agg(slug, ', ' ORDER BY slug) INTO v_left FROM public.email_templates
   WHERE body_html ILIKE '%Google Play%' AND body_html NOT ILIKE '%App Store%';
  RAISE NOTICE 'email_templates s Google Play bez App Store (zkontrolovat ve Velínu): %', coalesce(v_left, '—');
END $$;
