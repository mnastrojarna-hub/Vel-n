-- =============================================================================
-- profiles.app_permissions — zrcadlení OS oprávnění z appky do Velínu
-- =============================================================================
-- Appka (motogo-app-flutter PermissionService.reportToProfile) zapisuje poslední
-- snapshot udělených OS oprávnění telefonu. Velín → detail zákazníka
-- (CustomerProfileTab.jsx) je zobrazuje read-only v sekci „Oprávnění aplikace".
-- Informativní (device-level), nezasahuje do business logiky.
-- Tvar: {"location":bool,"camera":bool,"notification":bool,"photos":bool,
--        "platform":"android|ios","reported_at":"<iso>"}
-- =============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS app_permissions jsonb;

COMMENT ON COLUMN profiles.app_permissions IS
  'Poslední snapshot OS oprávnění z appky (location/camera/notification/photos bool + platform + reported_at). Plní appka PermissionService.reportToProfile, čte Velín detail zákazníka. Informativní, device-level.';
