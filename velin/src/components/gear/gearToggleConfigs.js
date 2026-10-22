// MotoGo24 — Velín: konfigurace přepínačů výpůjčky výbavy (props pro GearSettingToggle).
// Sdílí je Flotila → Půjčení oblečení (GearSettingsCard) i hlavička Logistiky zboží,
// aby obě místa ovládala STEJNÉ nastavení se stejným vysvětlením.
import { STOCK_KEY, STOCK_DEFAULTS } from './gearSettingsApi'
import { SETTINGS_KEY, DEFAULT_SETTINGS } from './gearShared'

// app_settings.gear_stock_check.gear_rental — kontrolu dělá DB (create_web_gear_booking,
// quote_gear_booking, get_gear_rental_availability; Velín admin_create_gear_booking jen varuje).
export const STOCK_TOGGLE = {
  settingKey: STOCK_KEY,
  field: 'gear_rental',
  defaults: STOCK_DEFAULTS,
  title: 'Kontrolovat sklad',
  auditAction: 'gear_stock_check_updated',
  help: 'Zapnuto = web výpůjčku výbavy odmítne (a velikost nenabídne), když na pobočce v daném termínu nezbývá volný kus — '
    + 'podle Logistiky zboží: sklad pobočky minus výbava už rezervovaná k motorkám i k jiným výpůjčkám. '
    + 'Typ výbavy, který pobočka na skladě vůbec neeviduje, se nehlídá. Velín při ručním zadání jen upozorní. '
    + 'Rezervace motorek se tím neblokují.',
  // viditelná jednořádková nápověda u kompaktního přepínače (hlavička Logistiky)
  hint: 'Zapnuto = web odmítne výpůjčku výbavy, když na pobočce v termínu není volný kus.',
}

// app_settings.gear_rental.app_visible — RESTRICTIVE RLS: dokud je vypnuto, zákazník gear
// rezervace přímou čtecí cestou z tabulky bookings nevidí (stará appka by je vykreslila špatně).
export const APP_VISIBLE_TOGGLE = {
  settingKey: SETTINGS_KEY,
  field: 'app_visible',
  defaults: { ...DEFAULT_SETTINGS, app_visible: false },
  title: 'Zobrazit v aplikaci',
  auditAction: 'gear_rental_app_visible_updated',
  help: 'Zapnuto = zákaznická aplikace uvidí výpůjčky výbavy mezi svými rezervacemi. Zapni AŽ po vydání verze aplikace '
    + 's podporou výpůjček výbavy (Android i iOS) — starší verze by výpůjčku ukázaly jako rozbitou rezervaci motorky. '
    + 'Web, e-maily, kódy a Velín fungují bez ohledu na tento přepínač.',
  confirmOn: {
    title: 'Zobrazit výpůjčky výbavy v aplikaci?',
    message: 'Zapni jen tehdy, když je v App Storu i Google Play vydaná verze aplikace s podporou výpůjček výbavy. '
      + 'Zákazníci se starší verzí by výpůjčku viděli jako rezervaci motorky bez motorky.',
  },
}
