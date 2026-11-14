// verify:render — Profil sub-screens: messages, thread, AI, documents,
// invoices, contracts (large text + reduced motion, 8 languages ×
// 320/360/412).
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/supabase_stub.dart';
import 'cases_profile_sub.dart';
import 'render_harness.dart';

void main() => renderMatrix(profileSubRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      await stubSupabase();
    });
