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
