-- 2026-05-12 — Překlady dokumentů (Velín → Dokumenty) do 6 cizích jazyků.
-- JSONB sloupec `translations` na obou tabulkách dokumentů; naplňuje ho edge
-- funkce `translate-document` (Anthropic Claude API). Čeština = vždy originální
-- sloupce, cizojazyčné verze webu čtou translations[lang].
--
-- Tvar:
--   custom_documents.translations  = { "en": { "title": ..., "description": ..., "content_html": ... }, "de": {...}, ... }
--   document_templates.translations = { "en": { "name": ..., "content_html": ... }, "de": {...}, ... }
--   (u custom_documents typu PDF má překlad jen content_html — přeložený obsah
--    PDF jako HTML; český originál PDF zůstává.)

alter table public.custom_documents
  add column if not exists translations jsonb not null default '{}'::jsonb;

alter table public.document_templates
  add column if not exists translations jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
