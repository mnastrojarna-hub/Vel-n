-- ─────────────────────────────────────────────────────────────────────────
-- Servisní terminál na displeji pobočky (raspberry/motogo-box CONTRACT §27)
-- ─────────────────────────────────────────────────────────────────────────
-- Velín (Pobočky → Samoobsluha → „⌨ Terminál na displeji") posílá jednotce příkaz
-- `shell_unlock` s `params {minutes}` (0 = zamknout), kterým na 30 minut povolí psaní
-- libovolných příkazů technikovi, jenž má u sebe jen DIAGNOSTICKÝ kód.
--
-- Servisní heslo volné psaní nepotřebuje odemykat — má ho samo, aby terminál fungoval
-- i na OFFLINE pobočce, kam by tenhle příkaz stejně nedorazil (Pohořelice 2026-09-19/20).
--
-- Jediná změna je rozšíření CHECK o nový název příkazu; bez ní PostgREST insert z Velína
-- odmítne. Idempotentní (DROP IF EXISTS + ADD), aplikované ručně 2026-09-20 a ověřené.
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system','shell_unlock'
  ));
