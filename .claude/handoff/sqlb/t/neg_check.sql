SELECT n.what FROM public.t_neg n WHERE n.val IS DISTINCT FROM (
 CASE n.what
  WHEN 'cms12' THEN (SELECT value #>> '{}' FROM cms_variables WHERE key = 'web.jak_pujcit_postup.process.steps.11.text')
  WHEN 'cms12_de' THEN (SELECT translations -> 'de' ->> 'value' FROM cms_variables WHERE key = 'web.jak_pujcit_postup.process.steps.11.text')
  WHEN 'cta_en' THEN (SELECT translations -> 'en' ->> 'value' FROM cms_variables WHERE key = 'web.jak_pujcit_vraceni_pujcovna.cta.text')
  WHEN 'footer_de' THEN (SELECT translations -> 'de' ->> 'value' FROM cms_variables WHERE key = 'web.layout.footer.aboutText')
  WHEN 'overlay_en' THEN (SELECT value #>> '{handover,items,0}' FROM app_settings WHERE key = 'pages_overlay.jak_pujcit_dokumenty.en')
  WHEN 'faq_cs' THEN (SELECT answer FROM faq_items WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e')
  WHEN 'faq_en' THEN (SELECT translations -> 'en' ->> 'answer' FROM faq_items WHERE id = 'dac51062-20c0-4ea9-8422-54720f27b87e')
  WHEN 'faq_uk' THEN (SELECT (translations -> 'uk')::text FROM faq_items WHERE id = '57912624-b5dd-4412-bbcc-e20d9c7a5938')
  WHEN 'blog_ex' THEN (SELECT excerpt FROM cms_pages WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7')
  WHEN 'blog_ex_en' THEN (SELECT translations -> 'en' ->> 'excerpt' FROM cms_pages WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7')
  WHEN 'banner' THEN (SELECT value::text FROM app_settings WHERE key = 'header_banner') END);
