-- =============================================================================
-- 20261015u_owner_texts_pobocky_steps.sql
-- datová migrace (bez změn schématu): postup „Jak to probíhá“ obou poboček (web /pobocky a appka → Pobočky).
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- cms_variables web.pobocky.branches.0.steps (Mezná) a .1.steps (Velké Němčice) přebíjí výchozí texty webu
-- (data/pobocky.php) i appky (branches_info_provider.dart). Nový text = bajtově shodný s data/pobocky.php,
-- velin webTextsPobocky.js a oběma stromy appky: Mezná krok 4 „… mýt ani tankovat ji nemusíte, jen ať
-- nesvítí rezerva“, Velké Němčice krok 6 „Motorku vraťte umytou a bez svítící rezervy …“.
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
    ('web.pobocky.branches.0.steps', 'cs', 'full', 'c7b4ab055eeceeb4dc67a38becf0736d', $t$1. Rezervujete a zaplatíte online (web nebo aplikace) a nahrajete doklady (OP/pas + ŘP) — žádáme o to i na obslužné pobočce; pokud je nenahrajete, zkontrolujeme je při převzetí na místě.<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese) — mýt ani tankovat ji nemusíte, jen ať nesvítí rezerva.$t$),
    ('web.pobocky.branches.1.steps', 'cs', 'full', 'eecaac2d3812f72a14ffcb00f6a42d5b', $t$1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a nahrajete doklady (OP/pas + ŘP) — na samoobslužné pobočce je to nezbytné: bez ověřených dokladů kódy nedostanete a na pobočku se nedostanete. Po ověření dokladů dostanete v aplikaci, e-mailu a SMS kódy v pořadí, v jakém je budete zadávat: <strong>1) kód schránky s klíčem od brány, 2) kód šatny</strong> (máte-li zapůjčenou výbavu) <strong>a 3) kód motorky</strong>.<br>2. <strong>Je-li vjezdová brána zavřená</strong>, otevřete kódem z aplikace <strong>horní schránku na pravém sloupku vrat</strong> — je v ní klíč od visacího zámku. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě <strong>1–7 vpravo u plotu</strong> (viz fotka parkoviště). Auto tu může zdarma stát po celou dobu výpůjčky. Je-li brána otevřená, kód schránky nepotřebujete.<br>3. Na displeji zadáte kód šatny — <strong>šatna jsou dveře č. 8</strong>. Vezmete si výbavu, převléknete se a dveře šatny zavřete (s vlastní výbavou šatnu přeskočíte). Máte-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>4. Na displeji v předávacím protokolu upravíte velikosti, protokol podepíšete a zadáte kód motorky — otevře se kóje s motorkou. Kóji zavřete a vyrazíte.<br>5. <strong>Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník.</strong> Otevřenou bránu nechte otevřenou — stav brány nikdy neměňte.<br>6. Po jízdě motorku vrátíte do kóje a výbavu do šatny — kdykoliv poslední den výpůjčky do 24:00. Motorku vraťte umytou a bez svítící rezervy (plnou nádrž nepotřebujete). Je-li brána zavřená, postupujete stejně: odemknete ji klíčem ze schránky a po odjezdu ji zase zamknete a klíč vrátíte.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.0.steps', '79176a8fcb0144ea9ecff2e4e9a0e904'),
    ('web.pobocky.branches.1.steps', '55dacd7167a7f395dbf39a2a7593e705')
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
        RAISE NOTICE 'pobocky_steps: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'pobocky_steps: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'pobocky_steps: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
