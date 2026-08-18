import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';

/// Converts technical errors into short Danish messages for UI.
String friendlyApiError(Object error) {
  final text = error.toString();

  if (text.contains('Failed host lookup') ||
      text.contains('SocketException') ||
      text.contains('Network is unreachable')) {
    final debugUrl = kDebugMode && SupabaseConfig.url.isNotEmpty
        ? '\nURL i app: ${SupabaseConfig.url}\n'
        : '';
    final debugDetail = kDebugMode ? '\nTeknisk: $text\n' : '';
    return 'Kan ikke oprette forbindelse til Supabase.$debugUrl$debugDetail\n'
        '• Tjek at telefonen har internet (WiFi/mobil)\n'
        '• Åbn Safari og test: supabase.com\n'
        '• Tjek at Project URL i assets/env.json matcher Supabase dashboard\n'
        '• Slet appen på telefonen, kør: flutter clean && flutter run';
  }

  if (text.contains('PGRST202') ||
      text.contains('create_outdoor_event') && text.contains('404')) {
    return 'Database er ikke sat op endnu.\n\n'
        'Kør migrationerne i Supabase SQL Editor (001 → 004).';
  }

  if (text.contains('Invalid API key') ||
      text.contains('invalid api key') ||
      (text.contains('401') && text.toLowerCase().contains('api key'))) {
    return 'Supabase anon key er ugyldig.\n\n'
        '1. Gå til Supabase → Project Settings → API\n'
        '2. Kopiér **anon public** key\n'
        '3. Indsæt i app/assets/env.json\n'
        '4. Kør flutter run igen (hot reload er ikke nok)';
  }

  if (text.contains('forbidden') || text.contains('not_authenticated')) {
    return 'Du har ikke adgang til dette kort. Log ind med den rigtige konto.';
  }

  if (text.contains('event_in_other_workspace')) {
    return 'Kortet tilhører allerede et andet workspace.';
  }

  if (text.contains('event_not_found')) {
    return 'Kortet findes ikke længere på serveren.';
  }

  if (text.contains('publish_not_allowed')) {
    return 'Publicering kræver udgivelsesadgang på workspace. '
        'Kontakt os for at aktivere dit kort.';
  }

  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
