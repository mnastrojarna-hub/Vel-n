import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Patterns in error messages that indicate an expired / invalid token.
///
/// IMPORTANT: keep this list tight — anything matched here triggers a forced
/// sign-out. Transport-level errors from Supabase Realtime (ChannelError,
/// RealtimeSubscribeException) are NOT auth errors and must not be listed
/// here, otherwise a transient network blip right after login will kick the
/// user back to the login screen.
const _authErrorPatterns = [
  'jwt expired',
  'jwt_expired',
  'token is expired',
  'token has expired',
  'invalid jwt',
  'invalid_jwt',
  'invalidjwttoken',
  'refresh_token_not_found',
  'invalid refresh token',
  'not_authenticated',
];

/// Returns `true` when [error] looks like an authentication / token error.
bool isAuthError(Object error) {
  final msg = error.toString().toLowerCase();

  if (error is AuthException) return true;
  if (error is PostgrestException && error.code == '401') return true;

  return _authErrorPatterns.any(msg.contains);
}

/// Call this whenever a Supabase API call fails.
/// If the error is auth-related, forces sign-out (which triggers the router
/// redirect to login) and returns `true`.
/// Otherwise returns `false` so the caller can handle the error normally.
Future<bool> handleAuthError(Object error) async {
  if (!isAuthError(error)) return false;

  try {
    await MotoGoSupabase.client.auth.signOut();
  } catch (_) {
    // sign-out itself may fail if the session is already gone — that's OK,
    // the authStateProvider will still emit null session.
  }
  return true;
}
