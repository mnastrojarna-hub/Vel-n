-- =============================================================================
-- Feature flag `eshop_visible` — e-shop v menu webu i appky (DATOVÁ, bez schématu)
-- Migrace: 20261001_feature_flag_eshop_visible.sql
--
-- Zadání majitele 2026-10-01: e-shop dočasně NEukazovat v menu (web motogo24.cz
-- hlavní menu + patička, appka Profil → menu); na jeho místo přišla záložka
-- „Pobočky“ (Mezná + Velké Němčice). Vrátí se zapnutím flagu ve Velíně
-- (Web CMS → Feature flags). Web (layout.php → fetchFeatureFlag) i appka
-- (eshopVisibleProvider) berou chybějící řádek jako VYPNUTO.
-- Idempotentní: řádek se založí jen když neexistuje (ruční přepnutí nepřepíše).
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM feature_flags WHERE key = 'eshop_visible') THEN
    -- Živé schéma (REST 2026-10-01): id, key, enabled, description, conditions, created_at.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='feature_flags' AND column_name='description') THEN
      INSERT INTO feature_flags (key, enabled, description)
      VALUES ('eshop_visible', false, 'E-shop v menu webu a appky (vypnuto = skrytý, místo něj Pobočky)');
    ELSE
      INSERT INTO feature_flags (key, enabled) VALUES ('eshop_visible', false);
    END IF;
  END IF;
END $$;
