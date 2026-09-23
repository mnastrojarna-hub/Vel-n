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

/// Samoobslužná pobočka vrací 24/7 kódem — čas VRÁCENÍ na pobočku zákazník
/// nevolí, do rezervace (a smlouvy) se zapíše 23:59 (zadání 2026-09-23).
/// Čas VYZVEDNUTÍ se volí vždy — řídí slevu za pozdní vyzvednutí (upřesnění
/// zadání 2026-09-23); 00:01 je jen stará hodnota z krátkého období, kdy se
/// skrýval i ten (rezervace přes AI) → všude se bere jako „bez času“.
const selfServicePickupTime = '00:01';
const selfServiceReturnTime = '23:59';

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

/// Čas návratu se skrývá jen při vrácení NA samoobslužnou pobočku.
bool selfServiceHidesReturnTime(
        {String? branchType, required String returnMethod}) =>
    branchType == selfServiceBranchType && returnMethod != 'delivery';
