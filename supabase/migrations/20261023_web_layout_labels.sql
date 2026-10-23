-- =============================================================================
-- 2026-10-23: Texty webu (cms_variables web.layout.*) — oprava živých překladů
--  • Zkratky dnů v kalendáři rezervace (rez.cal.dayShort.0–6) a úpravy rezervace
--    (editRez.cal.dow.1–7): strojový překlad z 2026-05-10 přeložil zkratky jako
--    slova („Po“ → After/Nach, „So“ → Also/Donc, „Ne“ → No/Nein) a přebíjel správné
--    texty z lang/*.php (i18n.php _i18nCmsOverlay) — v en/de/es/fr/nl/pl kalendář
--    ukazoval „After Tue Wed Thu Fri So No“.
--  • Tlačítko formuláře rez.cta.continue: majitel chce jen „Pokračovat“ (commit
--    ffc41541 změnil lang soubory, živý řádek CMS je ale přebíjel starým
--    „Pokračovat v rezervaci →“).
-- Hodnoty = lang/*.php webu (cs + en, de, es, fr, nl, pl, uk). Jen existující
-- řádky, jen když se liší → idempotentní, opakovaný běh nic nemění. value je jsonb (řetězec).
-- =============================================================================
UPDATE public.cms_variables c
   SET value = to_jsonb(v.val::text), translations = v.tr, updated_at = now()
  FROM (VALUES
  ('web.layout.rez.cal.dayShort.0', 'Po', '{"en":{"value":"Mon"},"de":{"value":"Mo"},"es":{"value":"lun"},"fr":{"value":"Lun"},"nl":{"value":"Ma"},"pl":{"value":"Pon"},"uk":{"value":"Пн"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.1', 'Út', '{"en":{"value":"Tue"},"de":{"value":"Di"},"es":{"value":"mar"},"fr":{"value":"Mar"},"nl":{"value":"Di"},"pl":{"value":"Wt"},"uk":{"value":"Вт"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.2', 'St', '{"en":{"value":"Wed"},"de":{"value":"Mi"},"es":{"value":"mié"},"fr":{"value":"Mer"},"nl":{"value":"Wo"},"pl":{"value":"Śr"},"uk":{"value":"Ср"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.3', 'Čt', '{"en":{"value":"Thu"},"de":{"value":"Do"},"es":{"value":"jue"},"fr":{"value":"Jeu"},"nl":{"value":"Do"},"pl":{"value":"Czw"},"uk":{"value":"Чт"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.4', 'Pá', '{"en":{"value":"Fri"},"de":{"value":"Fr"},"es":{"value":"vie"},"fr":{"value":"Ven"},"nl":{"value":"Vr"},"pl":{"value":"Pt"},"uk":{"value":"Пт"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.5', 'So', '{"en":{"value":"Sat"},"de":{"value":"Sa"},"es":{"value":"sáb"},"fr":{"value":"Sam"},"nl":{"value":"Za"},"pl":{"value":"Sob"},"uk":{"value":"Сб"}}'::jsonb),
  ('web.layout.rez.cal.dayShort.6', 'Ne', '{"en":{"value":"Sun"},"de":{"value":"So"},"es":{"value":"dom"},"fr":{"value":"Dim"},"nl":{"value":"Zo"},"pl":{"value":"Nd"},"uk":{"value":"Нд"}}'::jsonb),
  ('web.layout.editRez.cal.dow.1', 'Po', '{"en":{"value":"Mon"},"de":{"value":"Mo"},"es":{"value":"lu"},"fr":{"value":"Lu"},"nl":{"value":"Ma"},"pl":{"value":"Pn"},"uk":{"value":"Пн"}}'::jsonb),
  ('web.layout.editRez.cal.dow.2', 'Út', '{"en":{"value":"Tue"},"de":{"value":"Di"},"es":{"value":"ma"},"fr":{"value":"Ma"},"nl":{"value":"Di"},"pl":{"value":"Wt"},"uk":{"value":"Вт"}}'::jsonb),
  ('web.layout.editRez.cal.dow.3', 'St', '{"en":{"value":"Wed"},"de":{"value":"Mi"},"es":{"value":"mi"},"fr":{"value":"Me"},"nl":{"value":"Wo"},"pl":{"value":"Śr"},"uk":{"value":"Ср"}}'::jsonb),
  ('web.layout.editRez.cal.dow.4', 'Čt', '{"en":{"value":"Thu"},"de":{"value":"Do"},"es":{"value":"ju"},"fr":{"value":"Je"},"nl":{"value":"Do"},"pl":{"value":"Cz"},"uk":{"value":"Чт"}}'::jsonb),
  ('web.layout.editRez.cal.dow.5', 'Pá', '{"en":{"value":"Fri"},"de":{"value":"Fr"},"es":{"value":"vi"},"fr":{"value":"Ve"},"nl":{"value":"Vr"},"pl":{"value":"Pt"},"uk":{"value":"Пт"}}'::jsonb),
  ('web.layout.editRez.cal.dow.6', 'So', '{"en":{"value":"Sat"},"de":{"value":"Sa"},"es":{"value":"sá"},"fr":{"value":"Sa"},"nl":{"value":"Za"},"pl":{"value":"So"},"uk":{"value":"Сб"}}'::jsonb),
  ('web.layout.editRez.cal.dow.7', 'Ne', '{"en":{"value":"Sun"},"de":{"value":"So"},"es":{"value":"do"},"fr":{"value":"Di"},"nl":{"value":"Zo"},"pl":{"value":"Nd"},"uk":{"value":"Нд"}}'::jsonb),
  ('web.layout.rez.cta.continue', 'Pokračovat →', '{"en":{"value":"Continue →"},"de":{"value":"Weiter →"},"es":{"value":"Continuar →"},"fr":{"value":"Continuer →"},"nl":{"value":"Doorgaan →"},"pl":{"value":"Dalej →"},"uk":{"value":"Продовжити →"}}'::jsonb)
  ) AS v(key, val, tr)
 WHERE c.key = v.key
   AND (c.value IS DISTINCT FROM to_jsonb(v.val::text) OR c.translations IS DISTINCT FROM v.tr);
