-- 2026-05-12 — Překlad NÁZVŮ smluvních šablon do 6 jazyků.
-- `document_templates.content_translations` (z mig. 20260503) drží přeložený OBSAH
-- (`{lang:"<html>"}` — čte ho RPC get_document_translation). Tahle migrace přidává
-- vedle toho `name_translations` (`{lang:"<přeložený název>"}`); plní ho edge fn
-- `translate-document` zároveň s obsahem. Web (dokumenty-detail.php) ho použije jako
-- nadpis dokumentu na cizojazyčné verzi (jinak fallback na i18n název z mgPublicDocuments()).

alter table public.document_templates
  add column if not exists name_translations jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
