-- =============================================================================
-- 20261112c04_feature_flag_app_v2_ui.sql — DATOVÁ migrace (bez změn schématu)
-- Feature flag `app_v2_ui` — přepínač nového vzhledu mobilní appky (kill-switch).
--
-- Zadání majitele (2026-10-16, 2026-11-05): nový vzhled appky (v2) je v obou
-- stromech (Android i iOS) za přepínačem — chybějící řádek / true = nový vzhled,
-- false = návrat ke starému vzhledu bez vydání nové verze (CLAUDE.md, bod 6).
-- Appka řádek jen čte (appV2UiProvider v core/feature_flags.dart). Velín
-- (Web CMS → Feature flags) umí přepnout JEN existující řádek, takže bez něj by
-- přepínač nešel použít (nález závěrečné kontroly funkcí 2026-11-12).
--
-- Zakládá řádek ve stavu ZAPNUTO (= stejné chování jako bez řádku). Idempotentní:
-- existující řádek (i ručně vypnutý) se NEPŘEPISUJE. Starší appka 4.1.3 řádek nečte.
-- =============================================================================

insert into public.feature_flags (key, enabled, description)
values ('app_v2_ui', true,
        'Nový vzhled mobilní appky (od verze 5.0.0, Android i iOS). Vypnutí = appka se vrátí ke starému vzhledu bez vydání nové verze; přepne se v bezpečný okamžik, nikdy uprostřed rezervace, úpravy nebo platby.')
on conflict (key) do nothing;
