// Supabase for widget tests that do not exercise the backend: some screens
// (POI sheet, document scanner) log through DebugLogger, whose flush reads
// `MotoGoSupabase.currentUser` → "You must initialize the supabase instance"
// on the first test of an isolate. Initialised once, with a mock HTTP
// client (every request answers an empty list) and no stored session.
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _done = false;

Future<void> stubSupabase() async {
  if (_done) return;
  _done = true;
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: MotoGoSupabase.url,
    publishableKey: 'test-anon',
    httpClient: MockClient((_) async => http.Response('[]', 200, headers: {'content-type': 'application/json'})),
    authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
    debug: false,
  );
}
