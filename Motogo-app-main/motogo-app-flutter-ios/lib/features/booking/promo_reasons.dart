// Proč slevový kód / poukaz neplatí → i18n klíč (2026-10-16).
//
// RPC `validate_promo_code` / `validate_voucher_code` vracejí důvod jen jako
// český text (`error`) a edge `slevomat-voucher` číselný kód Slevomatu —
// dřív appka KAŽDÝ neúspěch hlásila jako „Neplatný kód", i když kód
// vypršel, byl vyčerpaný nebo jen nešlo internet.

/// Důvod z `validate_promo_code` / `validate_voucher_code` (null = „neexistuje").
String? promoReasonKey(Map? res) {
  if (res == null) return null;
  if (res['rate_limited'] == true) return 'psCodeRateLimited';
  final e = '${res['error'] ?? ''}'.toLowerCase();
  if (e.contains('není platn')) return 'psCodeNotYet';
  if (e.contains('vypršel')) return 'psCodeExpired';
  if (e.contains('vyčerpán')) return 'psCodeUsedUp';
  if (e.contains('příliš mnoho')) return 'psCodeRateLimited';
  return null;
}

/// Důvod z edge `slevomat-voucher` (action check); null = kód neexistuje.
String? slevomatReasonKey(Map? d) {
  if (d == null) return null;
  final code = (d['slevomat_error_code'] as num?)?.toInt() ?? 0;
  final status = '${d['status'] ?? ''}';
  if (status == 'redeemed' || code == 1105 || code == 1205) return 'psVoucherRedeemed';
  if (status == 'cancelled' || code == 1106 || code == 1107 || code == 1206 || code == 1207) {
    return 'psVoucherCancelled';
  }
  if (status == 'expired') return 'psCodeExpired';
  if (code == 1104 || code == 1204) return 'psSlevomatUnpaid';
  if (code == 1109 || code == 1209) return 'psSlevomatNotStarted';
  if (code == 1103 || code == 1203 || code == 0) {
    // 0 bez kódu = buď „neexistuje", nebo nenamapovaná hodnota / výpadek.
    final err = '${d['error'] ?? ''}';
    if (code == 0 && err.isNotEmpty && !err.contains('neexistuje')) {
      return 'pdSlevomatUnverified';
    }
    return null;
  }
  return 'pdSlevomatUnverified';
}
