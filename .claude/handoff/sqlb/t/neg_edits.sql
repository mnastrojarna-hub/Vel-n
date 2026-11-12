-- Simulované úpravy ve Velínu po 2026-10-15 (jen test): po balíku musí zůstat beze změny.
CREATE TABLE IF NOT EXISTS public.t_neg(what text PRIMARY KEY, val text);
TRUNCATE public.t_neg;
UPDATE cms_variables SET value = to_jsonb('VELIN cs krok 12'::text) WHERE key = 'web.jak_pujcit_postup.process.steps.11.text';
UPDATE cms_variables SET translations = jsonb_set(translations, '{en,value}', '"VELIN en CTA"') WHERE key = 'web.jak_pujcit_vraceni_pujcovna.cta.text';
UPDATE cms_variables SET translations = jsonb_set(translations, '{de,value}', '"VELIN de footer"') WHERE key = 'web.layout.footer.aboutText';
UPDATE app_settings SET value = jsonb_set(value, '{handover,items,0}', '"VELIN overlay en"') WHERE key = 'pages_overlay.jak_pujcit_dokumenty.en';
UPDATE faq_items SET answer = 'VELIN cs FAQ' WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e';
UPDATE faq_items SET translations = jsonb_set(translations, '{uk}', '{"question":"VELIN uk q","answer":"VELIN uk a"}') WHERE id = '57912624-b5dd-4412-bbcc-e20d9c7a5938';
UPDATE cms_pages SET excerpt = 'VELIN perex' WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7';
UPDATE app_settings SET value = value || '{"text":"VELIN banner"}' WHERE key = 'header_banner';
INSERT INTO public.t_neg
SELECT 'cms12', value #>> '{}' FROM cms_variables WHERE key = 'web.jak_pujcit_postup.process.steps.11.text'
UNION ALL SELECT 'cms12_de', translations -> 'de' ->> 'value' FROM cms_variables WHERE key = 'web.jak_pujcit_postup.process.steps.11.text'
UNION ALL SELECT 'cta_en', translations -> 'en' ->> 'value' FROM cms_variables WHERE key = 'web.jak_pujcit_vraceni_pujcovna.cta.text'
UNION ALL SELECT 'footer_de', translations -> 'de' ->> 'value' FROM cms_variables WHERE key = 'web.layout.footer.aboutText'
UNION ALL SELECT 'overlay_en', value #>> '{handover,items,0}' FROM app_settings WHERE key = 'pages_overlay.jak_pujcit_dokumenty.en'
UNION ALL SELECT 'faq_cs', answer FROM faq_items WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e'
UNION ALL SELECT 'faq_en', translations -> 'en' ->> 'answer' FROM faq_items WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e'
UNION ALL SELECT 'faq_uk', (translations -> 'uk')::text FROM faq_items WHERE id = '57912624-b5dd-4412-bbcc-e20d9c7a5938'
UNION ALL SELECT 'blog_ex', excerpt FROM cms_pages WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7'
UNION ALL SELECT 'blog_ex_en', translations -> 'en' ->> 'excerpt' FROM cms_pages WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7'
UNION ALL SELECT 'banner', value::text FROM app_settings WHERE key = 'header_banner';
