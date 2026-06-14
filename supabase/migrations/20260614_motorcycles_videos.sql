-- 2026-06-14 — MP4 videa motorky (Velín upload + web hero/detail/rezervace + app detail)
-- Aplikováno + ověřeno v živé DB 2026-06-14.
--
-- Pole veřejných URL MP4 videí motorky (bucket `media`, složka motos/<id>/videos/).
-- Pořadí prvků = pořadí přehrávání. Mirror existujícího `images text[]`.
-- Bez změny RLS/Realtime: `motorcycles` má public read + admin write a je již
-- v supabase_realtime publication; videa jdou do existujícího public bucketu `media`.

ALTER TABLE public.motorcycles
  ADD COLUMN IF NOT EXISTS videos text[] NOT NULL DEFAULT '{}'::text[];

COMMENT ON COLUMN public.motorcycles.videos IS
  'Pole veřejných URL MP4 videí motorky (bucket media). Web: hero banner + detail + rezervace krok 2. App: detail. Přehled/seznam vždy fotka.';

NOTIFY pgrst, 'reload schema';
