-- 2026-09-26: vzdálené příkazy Velín → řídicí jednotka přidané v software (raspberry/motogo-box), které CHECK
-- z 20260925b odmítal, takže je Velín nemohl vůbec vložit:
--   contact_test {zone, seconds}    — test dveřního kontaktu (BranchRpiZones „Test kontaktu“)
--   lte_mode     {mode: rndis|qmi}  — přepnutí režimu modemu SIM7600 (karta jednotky „Modem → RNDIS/QMI“)
-- Idempotentní: DROP IF EXISTS + ADD.
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system','shell_unlock','protocol_signed',
    'contact_test','lte_mode'
  ));
