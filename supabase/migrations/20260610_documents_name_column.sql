-- 2026-06-10 — FIX: tabulka `documents` postrádala sloupec `name`.
--
-- Edge fn `save-verification-document` (i web fallback v pages-rezervace-scan.js)
-- vkládá do `documents` sloupec `name` (popisek řádku, např. „Doklad totožnosti
-- — líc (web sken)"). Sloupec v reálné DB chyběl → insert padal na
--   "Could not find the 'name' column of 'documents' in the schema cache"
-- a funkce dělala early-return PŘED zápisem profiles.*_verified_at → naskenované
-- doklady zůstávaly „Neověřeno" (fotka i čísla se uložily jinou cestou, jen
-- verified_at ne). Přidáním sloupce se opravily všechny scan cesty.

ALTER TABLE public.documents ADD COLUMN IF NOT EXISTS name text;

-- Obnov PostgREST schema cache, ať změnu chytne okamžitě.
NOTIFY pgrst, 'reload schema';
