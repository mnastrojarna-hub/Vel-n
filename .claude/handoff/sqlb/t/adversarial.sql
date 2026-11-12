-- Zničené tvary dat pro test robustnosti (jen test).
SET session_replication_role = replica;
-- cms_variables: hodnota číslo / objekt / null, překlady pole / null / jazyk jako řetězec, chybějící řádek
UPDATE cms_variables SET value = '42' WHERE key = 'web.jak_pujcit_dokumenty.payments.rows.2.1';
UPDATE cms_variables SET value = '{"a":1}' WHERE key = 'web.jak_pujcit_postup.process.steps.11.text';
UPDATE cms_variables SET value = 'null' WHERE key = 'web.home.process.steps.2.text';
UPDATE cms_variables SET translations = '[]' WHERE key = 'web.jak_pujcit_vraceni_pujcovna.intro';
UPDATE cms_variables SET translations = 'null' WHERE key LIKE 'web.pobocky.branches.0.%';
UPDATE cms_variables SET translations = jsonb_build_object('de','text','en',jsonb_build_object('value',5),'fr','null'::jsonb) WHERE key LIKE 'web.pobocky.branches.1.%';
UPDATE cms_variables SET translations = '{"en":[1,2]}' WHERE key LIKE 'web.layout.%';
DELETE FROM cms_variables WHERE key LIKE 'web.jak_pujcit_vyzvednuti%' OR key LIKE 'web.jak_pujcit_pristaveni%';
-- faq_items: překlady null / pole / jazyk řetězec, prázdná odpověď, smazaný řádek
UPDATE faq_items SET translations = 'null' WHERE id = 'e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63';
UPDATE faq_items SET translations = '[]' WHERE id = '02b6cfc8-83af-4887-8f5f-a62214f64f2a';
UPDATE faq_items SET translations = jsonb_build_object('uk','x','fr',jsonb_build_object('answer',7)) WHERE id = '77557a0b-8c40-431e-a966-34848e738b7b';
UPDATE faq_items SET answer = '' WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e';
DELETE FROM faq_items WHERE id IN ('5c385d19-7c6e-4f43-9645-bdc163424371','9eb4103e-9c51-4813-bc5e-73e5d2ba990d');
-- app_settings: overlay jako pole, řetězec, chybějící cesta, smazaný klíč, banner bez textu, AI config null
UPDATE app_settings SET value = '[1,2]' WHERE key = 'pages_overlay.jak_pujcit_dokumenty.en';
UPDATE app_settings SET value = '"x"' WHERE key = 'pages_overlay.jak_pujcit_dokumenty.de';
UPDATE app_settings SET value = '{}' WHERE key LIKE 'pages_overlay.jak_pujcit_postup.%';
UPDATE app_settings SET value = 'null' WHERE key = 'ai_public_agent_config';
UPDATE app_settings SET value = '{"enabled":true}' WHERE key = 'header_banner';
DELETE FROM app_settings WHERE key = 'site.policies' OR key LIKE 'pages_overlay.home.%';
-- cms_pages: obsah NULL, překlady null
UPDATE cms_pages SET content = NULL, excerpt = NULL WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7';
UPDATE cms_pages SET translations = 'null' WHERE id <> '4185202a-9c04-4101-a098-423b7cd3ade7';
-- email_templates: prázdné tělo
UPDATE email_templates SET body_html = '', subject = '' WHERE slug = 'reminder';
SET session_replication_role = origin;
-- ručně změněné tělo funkce (jako zásah mimo git) – soubor t31 ho nesmí přepsat
CREATE OR REPLACE FUNCTION public._gate_procedure_msg(p_gate text, p_locker_door integer, p_has_gear boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT 'ručně'::text $$;
