-- =============================================================================
-- KIOSK: předávací protokol po zavření šatny 10 min (dřív 120 s) + zámek přejímky 10 min
-- Migrace: 20260929b_kiosk_handover_10min.sql (DATOVÁ, bez změn schématu)
--
-- Zadání majitele 2026-09-29: „Na kiosku protokol musí být 10 min po zavření
-- dveří, ne zmizet za 3 min.“ Velín ukládal do branch_kiosk_config.hardware
-- (tlačítko „Načíst výchozí mapu“ / editor HW) timings.handover_idle_s = 120 —
-- ten přebíjí výchozí hodnotu jednotky, proto nestačí nový software. Zároveň
-- zámek přejímky (handover_lock_s, dosud výchozí 300 s) na 600 s — jinak by po
-- 5 min mohl zadat kód další zákazník, zatímco první ještě podepisuje.
--
-- Jen NEPRÁZDNÉ mapy: hardware = '{}' znamená „lokální výchozí mapa“ a jakýkoli
-- klíč by jednotce vypnul venek ze šablony (merge_hardware) — tam platí nový
-- výchozí software (600 s). Hodnoty ≥ 600 (ručně nastavené delší) se nemění;
-- nečíselné hodnoty se berou jako chybějící (bez pádu migrace).
-- Jednotka si změnu vezme při dalším syncu (≤ 60 s), bez restartu.
-- Idempotentní (2. běh = 0 řádků).
-- =============================================================================

UPDATE public.branch_kiosk_config c
   SET hardware = c.hardware || jsonb_build_object('timings',
         COALESCE(c.hardware->'timings', '{}'::jsonb)
         || jsonb_build_object(
              'handover_idle_s', GREATEST(CASE WHEN c.hardware->'timings'->>'handover_idle_s' ~ '^[0-9]{1,6}$'
                                               THEN (c.hardware->'timings'->>'handover_idle_s')::int ELSE 0 END, 600),
              'handover_lock_s', GREATEST(CASE WHEN c.hardware->'timings'->>'handover_lock_s' ~ '^[0-9]{1,6}$'
                                               THEN (c.hardware->'timings'->>'handover_lock_s')::int ELSE 0 END, 600)))
 WHERE jsonb_typeof(c.hardware) = 'object'
   AND c.hardware <> '{}'::jsonb
   AND jsonb_typeof(COALESCE(c.hardware->'timings', '{}'::jsonb)) = 'object'
   AND (CASE WHEN c.hardware->'timings'->>'handover_idle_s' ~ '^[0-9]{1,6}$'
             THEN (c.hardware->'timings'->>'handover_idle_s')::int ELSE 0 END < 600
     OR CASE WHEN c.hardware->'timings'->>'handover_lock_s' ~ '^[0-9]{1,6}$'
             THEN (c.hardware->'timings'->>'handover_lock_s')::int ELSE 0 END < 600);
