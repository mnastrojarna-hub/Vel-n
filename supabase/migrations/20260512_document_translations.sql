-- 2026-05-12 — Překlady vlastních dokumentů (Velín → Dokumenty → Vlastní dokumenty)
-- do 6 cizích jazyků. JSONB sloupec `translations` na tabulce `custom_documents`;
-- naplňuje ho edge funkce `translate-document` (Anthropic Claude API).
-- Tvar: { "<lang>": { "title": ..., "description": ..., "content_html": ... }, ... }
-- (u typu PDF má překlad jen content_html — přeložený obsah PDF jako HTML; český
--  originál PDF zůstává a na české verzi se na něj /dokumenty/<slug> redirektuje).
--
-- Pevné smluvní šablony (`document_templates`) už mají `content_translations`
-- z migrace `supabase/functions/migrations/20260503_i18n_customer_comms.sql` (5.6);
-- edge fn `translate-document` u nich plní ten sloupec, nikoli `translations`.

alter table public.custom_documents
  add column if not exists translations jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
