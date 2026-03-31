import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase configuration — mirrors MOTOGO_CONFIG from index.html.
class MotoGoSupabase {
  MotoGoSupabase._();

  static const String url = 'https://vnwnqteskbykeucanlhk.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwi'
      'cm9sZSI6ImFub24iLCJpYXQiOjE3NzI0OTEzNjMsImV4cCI6MjA4ODA2NzM2M30.'
      'AiHfmfEQK9KD9TvxX5XLWVGaOhEV7kiMwwMwMWp0Ruo';

  static const String stripePublishableKey =
      'pk_live_51TBLTTRzZyjABDj9Xdv63ZdDXqMylQsv6QNjkGIphIuztdDaHC2GyL4e'
      'MzAYMMVeyY2qAHtdo86bA2ro5INkFpVV00EK7Vy0Fj';

  /// Shorthand for the global Supabase client instance.
  static SupabaseClient get client => Supabase.instance.client;

  /// Current authenticated user or null.
  static User? get currentUser => client.auth.currentUser;

  /// Current session or null.
  static Session? get currentSession => client.auth.currentSession;
}
