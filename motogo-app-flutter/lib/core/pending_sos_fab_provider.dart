import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_client.dart';

/// Pending SOS replacement data — mirrors apiCheckPendingSosReplacement()
/// from api-core.js. Shows when incident has replacement_status
/// "selecting" or "pending_payment".
class PendingSosReplacement {
  final String id;
  final String type;
  final String status;
  final String? replacementStatus;
  final String? bookingId;
  final bool? customerFault;

  const PendingSosReplacement({
    required this.id,
    required this.type,
    required this.status,
    this.replacementStatus,
    this.bookingId,
    this.customerFault,
  });
}

/// Checks for pending SOS replacement — mirrors _checkAndShowSosFab().
/// Returns the incident if replacement is in progress, null otherwise.
final pendingSosFabProvider =
    StreamProvider.autoDispose<PendingSosReplacement?>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    yield null;
    return;
  }

  // Initial fetch
  yield await _fetchPending(user.id);

  // Realtime: re-check on sos_incidents changes
  try {
    await for (final _ in MotoGoSupabase.client
        .from('sos_incidents')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)) {
      yield await _fetchPending(user.id);
    }
  } catch (_) {
    // Non-critical FAB — silently ignore realtime errors
    return;
  }
});

Future<PendingSosReplacement?> _fetchPending(String userId) async {
  try {
    final res = await MotoGoSupabase.client
        .from('sos_incidents')
        .select(
            'id, type, status, replacement_status, booking_id, customer_fault')
        .eq('user_id', userId)
        .inFilter('replacement_status', ['selecting', 'pending_payment'])
        .not('status', 'in', '("resolved","closed")')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (res == null) return null;

    // Check localStorage dismissal (7-day expiry)
    final dismissed = await _isDismissed(res['id'] as String);
    if (dismissed) return null;

    return PendingSosReplacement(
      id: res['id'] as String,
      type: res['type'] as String? ?? 'other',
      status: res['status'] as String? ?? 'reported',
      replacementStatus: res['replacement_status'] as String?,
      bookingId: res['booking_id'] as String?,
      customerFault: res['customer_fault'] as bool?,
    );
  } catch (_) {
    return null;
  }
}

/// Check if this incident FAB was dismissed (stored in SharedPreferences).
/// Mirrors localStorage mg_sos_fab_dismissed with 7-day expiry.
Future<bool> _isDismissed(String incidentId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('sos_fab_dismissed_$incidentId');
    if (ts == null) return false;
    const sevenDays = 7 * 24 * 60 * 60 * 1000;
    if (DateTime.now().millisecondsSinceEpoch - ts > sevenDays) {
      await prefs.remove('sos_fab_dismissed_$incidentId');
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Dismiss SOS FAB — stores timestamp in SharedPreferences.
/// Mirrors dismissSosFab() from reservations-ui.js.
Future<void> dismissSosFab(String incidentId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'sos_fab_dismissed_$incidentId',
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {}
}
