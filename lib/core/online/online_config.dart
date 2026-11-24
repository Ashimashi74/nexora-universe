/// Online configuration injected at build time (never hard-coded secrets).
///
/// CI passes the public project URL + publishable (anon) key:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Without them the app runs fully offline exactly like before.
class OnlineConfig {
  const OnlineConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String liveKitUrl =
      String.fromEnvironment('LIVEKIT_URL', defaultValue: 'wss://nexora-space-xzjzlfyl.livekit.cloud');

  /// Region of the core project. Edge Functions are pinned to it so their DB / auth calls stay in-region
  /// (otherwise the nearest edge region answers and every DB read crosses continents).
  static const String functionsRegion = String.fromEnvironment('SUPABASE_FUNCTIONS_REGION', defaultValue: 'eu-central-1');

  /// Games project (rooms, matchmaking, matches, tournaments). It trusts this app's auth JWTs (Third-Party Auth),
  /// so the same signed-in user is `auth.uid()` on both projects.
  static const String gamesUrl = String.fromEnvironment('GAMES_SUPABASE_URL');
  static const String gamesAnonKey = String.fromEnvironment('GAMES_SUPABASE_ANON_KEY');

  static bool get enabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get gamesEnabled => gamesUrl.isNotEmpty && gamesAnonKey.isNotEmpty;
}
