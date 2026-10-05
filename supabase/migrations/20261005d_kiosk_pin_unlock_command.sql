-- 2026-10-05 — vzdálené zrušení blokace zadávání kódů (PIN lockout) z Velína.
-- Hlášení majitele s fotkou displeje (Velké Němčice): „Zadávání dočasně zablokováno“ — po 5 neplatných pokusech
-- nešlo zadat nic, ani servisní heslo. Jednotka ≥ 1.2.5: servisní přístup projde i během lockoutu a lockout zruší,
-- stav hlásí ve `status.pin_locked_until` a nový příkaz `pin_unlock` (params {}) lockout zruší na dálku
-- (Velín → Pobočky → Samoobsluha → karta jednotky → „Zrušit blokaci zadávání“).
-- Nový vzdálený příkaz = vždy i CHECK (CLAUDE.md). DROP + ADD, idempotentní; seznam = živý CHECK + pin_unlock.
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system','shell_unlock','protocol_signed',
    'contact_test','lte_mode',
    'screen_mirror','screen_input',
    'pin_unlock'
  ));
