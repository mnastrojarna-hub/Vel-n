-- 2026-10-05: texty webu ve Velín CMS (cms_variables) ke kroku Výbava — srovnání s pravidlem „kód šatny jen při
-- vybrané výbavě“ (20261005g) a s webem, který u zaškrtnuté výbavy nově vyžaduje velikost (lang/*.php):
--  - „Pokud velikost nezvolíte, vyzkoušíte ji na místě“ / „velikost si vyberete v motopůjčovně / na místě“ pryč —
--    na samoobslužné pobočce bez vybrané velikosti zákazník kód šatny nedostane;
--  - „přístupové kódy k motorce i výbavě“ → kód k motorce + kód šatny jen při zapůjčené výbavě.
-- CMS (web.layout.* a web.<stránka>.*) má přednost před lang/*.php, takže bez téhle migrace by web dál ukazoval
-- staré věty. Mění se JEN existující řádky, a jen když obsahují původní větu (ruční úpravy z Velína zůstanou);
-- změněnému řádku se smažou překlady → cizí jazyky vezmou nový text z lang/<jazyk>.php (web nahrát na hosting),
-- případně nový auto-překlad z Velína. Idempotentní.
DO $$
DECLARE
  v_pairs constant text[][] := ARRAY[
    ['web.layout.rez.intro.benefits', ' · velikost si vyberete v motopůjčovně', ' (zaškrtněte ji a vyberte velikost)'],
    ['web.layout.rez.gear.intro', ' Pokud velikost nezvolíte, vyzkoušíte ji na místě.', ''],
    ['web.layout.rez.gear.intro', ' Pokud velikost nezvolíte, vyzkoušíme ji na místě.', ''],
    ['web.layout.rez.gear.passengerTip', ' Velikost si vyberete kliknutím níže nebo na místě.', ' Velikost si vyberete kliknutím níže.'],
    ['web.layout.rez.gear.sizeHintGear', ' (jinak se vyzkouší na místě)', ''],
    ['web.layout.confirm.success.nextBookingCodes', '6místné přístupové kódy k motorce i výbavě',
       '6místný přístupový kód k motorce a – máte-li zapůjčenou výbavu – kód šatny'],
    ['web.layout.confirm.success.nextBookingCodesDone', '6místné přístupové kódy k motorce i výbavě vám pošleme',
       '6místný přístupový kód k motorce a – máte-li zapůjčenou výbavu – kód šatny vám pošleme'],
    ['web.layout.confirm.qrdocs.codesInfo', 'přístupové kódy k motorce a výbavě.',
       'přístupový kód k motorce (máte-li zapůjčenou výbavu, i kód šatny).'],
    ['web.layout.confirm.paydocs.step3', 'přístupové kódy k motorce a výbavě.',
       'přístupový kód k motorce (máš-li zapůjčenou výbavu, i kód šatny).'],
    ['web.pujcovna.process.steps.2.text', 'Velikost si můžeš zvolit až na místě.',
       'Velikost vybereš při rezervaci — výbavu stačí zaškrtnout.']
  ];
  i integer;
  v_val text;
  v_n integer := 0;
BEGIN
  FOR i IN 1..array_length(v_pairs, 1) LOOP
    SELECT value #>> '{}' INTO v_val FROM public.cms_variables
     WHERE key = v_pairs[i][1] AND jsonb_typeof(value) = 'string';
    IF v_val IS NOT NULL AND position(v_pairs[i][2] IN v_val) > 0 THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(replace(v_val, v_pairs[i][2], v_pairs[i][3])),
             translations = '{}'::jsonb, updated_at = now()
       WHERE key = v_pairs[i][1];
      v_n := v_n + 1;
      RAISE NOTICE '20261005l: cms_variables % — text výbavy upraven', v_pairs[i][1];
    END IF;
  END LOOP;
  RAISE NOTICE '20261005l: upraveno % textů CMS', v_n;
END $$;
