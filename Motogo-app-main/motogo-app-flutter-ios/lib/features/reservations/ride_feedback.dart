import 'package:url_launcher/url_launcher.dart';

import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../messages/messages_provider.dart' show createThread, sendMessage;

/// Přímá zpětná vazba k jízdě („Napiš nám přímo, co máme zlepšit“, zadání
/// majitele 2026-10-15) — jde do VLASTNÍ konverzace zákazníka (`message_threads`
/// + `messages`), kterou Velín čte v reálném čase (Zprávy → Chat i záložka
/// Hodnocení, odznak nepřečtených). Nikdy do tabulky `reviews` — ta je veřejná
/// (RLS SELECT pro všechny, web ji vykresluje).
///
/// Konvence pro Velín: předmět konverzace = `<lokalizovaný název> #XXXXXXXX`
/// (`Reservation.shortId`, posledních 8 znaků id rezervace velkými písmeny);
/// Velín páruje značku s rezervací a hlídá `customer_id == bookings.user_id`.
/// Zpráva začíná řádkem `★★☆☆☆ 2/5` (hodnocení v okamžiku odeslání), pak text.
///
/// Bez nové SQL: zákazník smí INSERT do `message_threads` (customer_id = uid)
/// i `messages` (direction 'customer', vlastní vlákno). Odpověď obsluhy přijde
/// do appky pushem přes `trg_bridge_admin_message`.
const int kRideFeedbackMaxLen = 2000;

/// Výsledek odeslání — [threadId] při úspěchu, jinak [error].
class RideFeedbackResult {
  final String? threadId;
  final String? error;
  const RideFeedbackResult.ok(String this.threadId) : error = null;
  const RideFeedbackResult.fail(String this.error) : threadId = null;
  bool get ok => threadId != null;
}

/// `★★★★☆ 4/5` — jazykově neutrální kontext hodnocení pro obsluhu.
String rideFeedbackStars(int rating) {
  final r = rating.clamp(0, 5);
  return '${'★' * r}${'☆' * (5 - r)} $r/5';
}

/// Vlastní NEuzavřená konverzace k rezervaci (opakované odeslání ji použije
/// znovu). Uzavřené vlákno appka neumí doplnit (skryté pole) → nové vlákno.
Future<String?> _findOpenFeedbackThread(String userId, String marker) async {
  final rows = await MotoGoSupabase.client
      .from('message_threads')
      .select('id')
      .eq('customer_id', userId)
      .ilike('subject', '%$marker%')
      .neq('status', 'closed')
      .order('created_at', ascending: false)
      .limit(1);
  final list = rows as List;
  return list.isEmpty ? null : list.first['id'] as String?;
}

/// Odešle text obsluze. [shortId] je `Reservation.shortId` (`#XXXXXXXX`),
/// [subjectPrefix] lokalizovaný název konverzace (`rfThreadSubject`).
Future<RideFeedbackResult> sendRideFeedback({
  required String shortId,
  required String subjectPrefix,
  required int rating,
  required String text,
}) async {
  final user = MotoGoSupabase.currentUser;
  final body = text.trim();
  if (user == null) return const RideFeedbackResult.fail('not_signed_in');
  if (body.isEmpty) return const RideFeedbackResult.fail('empty');
  try {
    var threadId = await _findOpenFeedbackThread(user.id, shortId);
    threadId ??= await createThread('$subjectPrefix $shortId');
    if (threadId == null) return const RideFeedbackResult.fail('thread');
    final content = rating > 0 ? '${rideFeedbackStars(rating)}\n\n$body' : body;
    final err = await sendMessage(threadId, content);
    if (err != null) return RideFeedbackResult.fail(err);
    return RideFeedbackResult.ok(threadId);
  } catch (e) {
    if (await handleAuthError(e)) return const RideFeedbackResult.fail('auth');
    return RideFeedbackResult.fail(e.toString());
  }
}

/// Otevře Google recenzi externě (prohlížeč / Mapy Google). Vrací false,
/// když odkaz nejde otevřít.
Future<bool> openGoogleReview(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
