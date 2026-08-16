import 'app_config.dart';

/// Supabase config loaded at startup from assets/env.json.
abstract final class SupabaseConfig {
  static String get url => AppConfig.supabaseUrl;
  static set url(String value) => AppConfig.supabaseUrl = value;

  static String get anonKey => AppConfig.supabaseAnonKey;
  static set anonKey(String value) => AppConfig.supabaseAnonKey = value;

  static bool get isConfigured => AppConfig.isSupabaseConfigured;

  static Future<void> load() => AppConfig.load();
}
