-- 2026-06-21 — Ruční pořadí zobrazení motorek (Velín → web)
-- POZOR: PENDING — nejdřív spustit v Supabase SQL editoru, teprve pak nasadit frontend.
--
-- Ruční číslo pořadí (1-X), které admin nastaví ve Velíně (Fleet detail / nová motorka).
-- Řídí pořadí na webu: krok „Vyber stroj" v rezervaci, katalog (výchozí řazení) a
-- pořadí fotek/videí v hero banneru na home (hero čte $motos = fetchMotos v pořadí).
-- NULL = neočíslováno → řadí se až ZA očíslované motorky podle modelu (nullslast).
-- Bez změny RLS/Realtime: `motorcycles` má public read + admin write.

ALTER TABLE public.motorcycles
  ADD COLUMN IF NOT EXISTS sort_order integer;

COMMENT ON COLUMN public.motorcycles.sort_order IS
  'Ruční pořadí zobrazení (1-X) na webu: vyber stroj, katalog, hero banner. NULL = neřazeno (řadí se za očíslované dle modelu, nullslast).';

CREATE INDEX IF NOT EXISTS idx_motorcycles_sort_order ON public.motorcycles (sort_order);

NOTIFY pgrst, 'reload schema';
