// Úklid cache (CacheCleanupService.run při každém startu a při každé pauze
// appky) NESMÍ mazat záznamy, které mají přežít odskok do bankovní appky
// (3-D Secure) i restart: značku odeslané platby, frontu zaplacených změn,
// stav kill-switche nového vzhledu, App funnel a skrytí v2 nápověd.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/cache_cleanup_service.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/paid_change_queue.dart';
import 'package:motogo_app/core/payment_pending_marker.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_coach.dart';
import 'package:motogo_app/features/home/v2/home_review_card_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keep-list covers every record that must survive a pause / restart', () {
    for (final k in [
      PaidChangeQueue.storeKey,
      AppV2UiNotifier.prefKey,
      MgAiCoach.prefKey,
      '${HomeHiddenReviews.prefix}b1',
      'mg_payment_submitted_v2',
      'mg_engage_token',
      'mg_engage_sent',
      // 4.1.3 keys stay kept
      'mg_bio_enabled',
      'mg_ride_rec_id',
      'mg_loyalty_last_level_u1',
      'sb-xyz-auth-token',
    ]) {
      expect(CacheCleanupService.keeps(k), isTrue, reason: k);
    }
    expect(CacheCleanupService.keeps('mg_something_transient'), isFalse);
    expect(CacheCleanupService.keeps('flutter.random'), isFalse);
  });

  test('clearing transient prefs keeps the payment marker, the paid-change queue and the kill-switch', () async {
    SharedPreferences.setMockInitialValues({AppV2UiNotifier.prefKey: false, 'mg_something_transient': 'x'});
    PaidChangeQueue.resetForTest();
    PaidChangeQueue.autoSchedule = false;
    await PaymentPendingMarker.set('b1', clientSecret: 'pi_b1_secret_x', fresh: true);
    await PaidChangeQueue.enqueue(
        const PaidChangeEntry(key: 'pi_1', bookingId: 'b1', kind: 'swap', charge: 15, paid: true),
        delay: const Duration(hours: 1));
    expect(await PaymentPendingMarker.isPending('b1'), isTrue);

    await CacheCleanupService.clearTransientPrefs();

    final p = await SharedPreferences.getInstance();
    expect(p.containsKey('mg_something_transient'), isFalse, reason: 'the cleanup still runs');
    expect(await PaymentPendingMarker.isPending('b1'), isTrue);
    PaidChangeQueue.resetForTest(); // „restart" — stav jen v úložišti
    final all = await PaidChangeQueue.all();
    expect(all.map((e) => e.key), ['pi_1']);
    AppV2UiNotifier.bootValue = true;
    await AppV2UiNotifier.preload();
    expect(AppV2UiNotifier.bootValue, isFalse);
    AppV2UiNotifier.bootValue = true;
  });
}
