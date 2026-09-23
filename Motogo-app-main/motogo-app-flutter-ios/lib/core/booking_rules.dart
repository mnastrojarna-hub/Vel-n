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

/// Samoobslužná pobočka vydává 24/7 kódem — zákazník čas nevolí, do rezervace
/// (a smlouvy) se zapíše celý den 00:01–23:59 (zadání 2026-09-23).
const selfServicePickupTime = '00:01';
const selfServiceReturnTime = '23:59';

/// Čas vyzvednutí se skrývá jen při vyzvednutí NA samoobslužné pobočce;
/// přistavení (delivery) čas potřebuje vždy (min. teď + 6 h).
bool selfServiceHidesPickupTime(
        {String? branchType, required String pickupMethod}) =>
    branchType == selfServiceBranchType && pickupMethod != 'delivery';

/// Čas návratu se skrývá jen při vrácení NA samoobslužnou pobočku.
bool selfServiceHidesReturnTime(
        {String? branchType, required String returnMethod}) =>
    branchType == selfServiceBranchType && returnMethod != 'delivery';
