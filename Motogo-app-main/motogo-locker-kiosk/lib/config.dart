/// Centrální konfigurace kiosku — zrcadlí MotoGoSupabase z hlavní appky.
class KioskConfig {
  KioskConfig._();

  static const String supabaseUrl = 'https://vnwnqteskbykeucanlhk.supabase.co';

  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwi'
      'cm9sZSI6ImFub24iLCJpYXQiOjE3NzI0OTEzNjMsImV4cCI6MjA4ODA2NzM2M30.'
      'AiHfmfEQK9KD9TvxX5XLWVGaOhEV7kiMwwMwMWp0Ruo';

  /// Po kolika sekundách nečinnosti se zpráva o úspěchu/chybě schová.
  static const Duration statusAutoHide = Duration(seconds: 6);

  /// Timeout HTTP volání na relé (LAN).
  static const Duration relayTimeout = Duration(seconds: 6);
}
