import 'package:shared_preferences/shared_preferences.dart';

class VisitorFavoritesStorage {
  static String _key(String eventId) => 'visitor_favorites_$eventId';

  Future<Set<String>> load(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(eventId)) ?? const [];
    return raw.toSet();
  }

  Future<void> save(String eventId, Set<String> poiIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(eventId), poiIds.toList());
  }

  Future<bool> toggle(String eventId, String poiId) async {
    final current = await load(eventId);
    if (current.contains(poiId)) {
      current.remove(poiId);
    } else {
      current.add(poiId);
    }
    await save(eventId, current);
    return current.contains(poiId);
  }
}
