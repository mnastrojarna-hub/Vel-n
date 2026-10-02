/// Pravidla rezervace sdílená napříč appkou — JEDEN zdroj pravdy.
///
/// Historie: okno na zaplacení bylo původně 10 minut, migrace
/// `20260904b_app_payment_window_30min.sql` ho prodloužila na 30. Hodnota
/// byla ale v appce zapsaná na několika místech zvlášť a dvě z nich zůstala
/// na deseti — appka pak mezi 10. a 30. minutou tvrdila „zrušeno“, zatímco
/// server rezervaci pořád držel. Proto je konstanta tady, sama.
library;

/// Kolik času má zákazník na zaplacení rezervace z aplikace.
/// MUSÍ sedět se serverovým cronem `auto_cancel_expired_pending()`
/// (app = 30 min, web = 4 h). Odpočítává se od VZNIKU rezervace.
const paymentTimeoutDuration = Duration(minutes: 30);

/// Typ samoobslužné pobočky v `branches.type` (obslužná = 'obslužná';
/// NULL/neznámý typ = chovat se jako obslužná).
const selfServiceBranchType = 'samoobslužná';

/// Samoobslužná pobočka (zadání majitele 2026-10-01 večer, ruší ranní
/// „bez času převzetí i vrácení“): čas VYZVEDNUTÍ zákazník volí vždy — řídí
/// slevu 50 % na 1. den (vyzvednutí od 12:00, výpůjčka 2+ dny) a kiosk
/// rezervaci s touto slevou vydá až od 12:00 ([selfServiceLateGate]). Čas
/// VRÁCENÍ na pobočku se nevolí — do rezervace jde 23:59 (smlouva do 24:00).
/// `pickup_time` 00:01 = STARÁ hodnota „bez času, kdykoliv 1. den“ (ranní
/// pravidlo 2026-10-01 a AI 2026-09-23) — jen se čte, nikdy nezapisuje.
const selfServicePickupTime = '00:01';
const selfServiceReturnTime = '23:59';

/// Uložený čas vyzvednutí je stará značka „bez času“ (00:01) — zobrazit jako
/// „kdykoliv během prvního dne“, bez slevy i hradla kiosku; formulář úprav
/// ho NEpřepisuje, dokud zákazník výběr času sám nezmění.
bool isLegacyAllDayPickupTime(String? time) =>
    (time ?? '').startsWith(selfServicePickupTime);

/// Stará rezervace „bez času“ s vyzvednutím NA samoobslužné pobočce.
bool isLegacySelfServiceAllDay(
        {String? branchType, required String pickupMethod, String? time}) =>
    branchType == selfServiceBranchType &&
    pickupMethod != 'delivery' &&
    isLegacyAllDayPickupTime(time);

/// Hradlo výdeje kiosku (zrcadlo SQL `_kiosk_release_at`, migrace
/// 20261001h): rezervaci se slevou za vyzvednutí od 12:00 (samoobslužná
/// pobočka motorky, převzetí na pobočce, ještě nevyzvednutá, reserved/active,
/// ne SOS náhrada) vydá kiosk — šatnu i motorku — až od 12:00 Europe/Prague
/// dne začátku ([kioskReleaseAtUtc]).
bool selfServiceLateGate({
  String? branchType,
  String? pickupMethod,
  String? pickupAddress,
  double? lateDiscount,
  DateTime? pickedUpAt,
  String? status,
  bool sosReplacement = false,
}) =>
    branchType == selfServiceBranchType &&
    pickupMethod != 'delivery' &&
    (pickupAddress ?? '').trim().isEmpty &&
    (lateDiscount ?? 0) > 0 &&
    pickedUpAt == null &&
    (status == 'reserved' || status == 'active') &&
    !sosReplacement;

/// Posun Europe/Prague vůči UTC v daném okamžiku — pravidla EU: letní čas
/// (UTC+2) od poslední neděle v březnu 01:00 UTC do poslední neděle v říjnu
/// 01:00 UTC, jinak UTC+1. Bez balíčku časových zón; zařízení může být
/// v jiném pásmu, proto se nikdy nebere jeho lokální čas.
Duration pragueOffsetAt(DateTime instant) {
  final u = instant.toUtc();
  DateTime lastSundayUtc(int month) {
    // Den 0 následujícího měsíce = poslední den měsíce (Dart normalizuje).
    final last = DateTime.utc(u.year, month + 1, 0);
    return DateTime.utc(u.year, month, last.day - (last.weekday % 7), 1);
  }
  final summer =
      !u.isBefore(lastSundayUtc(3)) && u.isBefore(lastSundayUtc(10));
  return Duration(hours: summer ? 2 : 1);
}

/// Pražský „nástěnný“ čas okamžiku jako UTC-DateTime (pole year/month/day/
/// hour = čas v Praze) — jen pro formátování a kalendářní porovnání.
DateTime pragueWallClock(DateTime instant) {
  final u = instant.toUtc();
  return u.add(pragueOffsetAt(u));
}

/// Okamžik (UTC) zadaného pražského data a času.
DateTime pragueToUtc(int year, int month, int day, [int hour = 0, int minute = 0]) {
  final wall = DateTime.utc(year, month, day, hour, minute);
  final guess = wall.subtract(pragueOffsetAt(wall));
  return wall.subtract(pragueOffsetAt(guess));
}

/// Výdej rezervace se slevou za pozdní vyzvednutí: 12:00 Europe/Prague dne
/// začátku ([startDate] = kalendářní datum rezervace) jako UTC okamžik.
DateTime kioskReleaseAtUtc(DateTime startDate) =>
    pragueToUtc(startDate.year, startDate.month, startDate.day, 12);

/// Datum pro texty „{datum} od 12:00“ (např. „5. 10. 2026“).
String fmtReleaseDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

/// Popisek volby „Na pobočce“: u SAMOOBSLUŽNÉ pobočky adresa + město z DB
/// (Brno Velké Němčice → „Boudky, Velké Němčice“); u obslužné / neznámé
/// pobočky null = volající nechá dosavadní text (UI obslužné beze změny).
String? selfServiceBranchLabel({
  String? branchType,
  String? name,
  String? address,
  String? city,
}) {
  if (branchType != selfServiceBranchType) return null;
  final parts = [address, city]
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isNotEmpty) return parts.join(', ');
  final n = (name ?? '').trim();
  return n.isEmpty ? null : n;
}

/// Rezervace z webu / AI (RPC create_web_booking) pickup_method/return_method
/// nevyplňují — přistavení/odvoz tam zůstává DEFAULT 'store' s vyplněnou
/// adresou. U ULOŽENÉ rezervace se proto bere v potaz i adresa (shodně
/// s generate-document), jinak by se skryl skutečný čas přistavení.
String bookingMethodWithAddress(String? method, String? address) =>
    method == 'delivery' || (address ?? '').trim().isNotEmpty
        ? 'delivery'
        : (method ?? 'store');

/// Samoobslužná pobočka: přistavení na adresu ani odvoz z adresy zatím
/// nelze (rozhodnutí majitele 2026-09-28) — dokud není zapnutý feature flag
/// `self_service_delivery` (Velín → Texty webu → Feature flags). Formulář i
/// úprava rezervace pak nabízí jen pobočku; volby zůstávají vidět zabalené
/// s vysvětlením. Obslužná / neznámá pobočka beze změny.
bool selfServiceDeliveryBlocked(
        {String? branchType, required bool flagEnabled}) =>
    branchType == selfServiceBranchType && !flagEnabled;

/// Čas návratu se skrývá jen při vrácení NA samoobslužnou pobočku.
bool selfServiceHidesReturnTime(
        {String? branchType, required String returnMethod}) =>
    branchType == selfServiceBranchType && returnMethod != 'delivery';
