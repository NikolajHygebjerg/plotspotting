import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App config loaded at startup from --dart-define (CI/Vercel) or assets/env.json.
abstract final class AppConfig {
  static String supabaseUrl = '';
  static String supabaseAnonKey = '';
  static String publicWebBaseUrl = 'https://plotspotting.vercel.app';
  static bool _loaded = false;

  static bool get isSupabaseConfigured =>
      _loaded &&
      supabaseUrl.isNotEmpty &&
      _looksLikeSupabaseAnonKey(supabaseAnonKey);

  /// Supabase anon keys are JWTs (eyJ…) — reject placeholders like "test".
  static bool _looksLikeSupabaseAnonKey(String key) {
    const placeholders = {
      'REPLACE_WITH_ANON_KEY',
      'test',
      'your-anon-key',
      'YOUR_ANON_KEY',
    };
    if (key.isEmpty || placeholders.contains(key)) return false;
    return key.startsWith('eyJ') && key.length > 80;
  }

  /// Canonical base for published map links, e.g. https://plotspotting.vercel.app/e
  static String get publicEventBaseUrl {
    final trimmed = publicWebBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return trimmed.endsWith('/e') ? trimmed : '$trimmed/e';
  }

  static Future<void> load() async {
    if (_loaded) return;

    const envUrl = String.fromEnvironment('SUPABASE_URL');
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const envPublicBase = String.fromEnvironment('PUBLIC_WEB_BASE_URL');
    if (envUrl.isNotEmpty && envKey.isNotEmpty) {
      supabaseUrl = envUrl;
      supabaseAnonKey = envKey;
      if (envPublicBase.isNotEmpty) {
        publicWebBaseUrl = envPublicBase;
      }
      _applyWebOriginOverride();
      _loaded = true;
      return;
    }

    try {
      final raw = await rootBundle.loadString('assets/env.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      supabaseUrl = json['SUPABASE_URL'] as String? ?? '';
      supabaseAnonKey = json['SUPABASE_ANON_KEY'] as String? ?? '';
      publicWebBaseUrl =
          json['PUBLIC_WEB_BASE_URL'] as String? ?? publicWebBaseUrl;
    } on Object {
      supabaseUrl = '';
      supabaseAnonKey = '';
    }

    _applyWebOriginOverride();
    _loaded = true;
  }

  /// På web bruger vi den aktuelle Vercel-URL som public base (prod eller preview).
  static void _applyWebOriginOverride() {
    if (!kIsWeb) return;
    final origin = Uri.base.origin;
    if (origin.isEmpty || origin.contains('localhost')) return;
    publicWebBaseUrl = origin;
  }
}
