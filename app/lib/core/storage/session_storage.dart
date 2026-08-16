import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OrganizerSession {
  const OrganizerSession({
    required this.eventId,
    required this.eventName,
    this.publicSlug,
  });

  final String eventId;
  final String eventName;
  final String? publicSlug;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'eventName': eventName,
        'publicSlug': publicSlug,
      };

  factory OrganizerSession.fromJson(Map<String, dynamic> json) {
    return OrganizerSession(
      eventId: json['eventId'] as String,
      eventName: json['eventName'] as String,
      publicSlug: json['publicSlug'] as String?,
    );
  }
}

class SessionStorage {
  static const _sessionsKey = 'organizer_sessions';

  Future<List<OrganizerSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_sessionsKey) ?? const [];
    return raw
        .map((item) => OrganizerSession.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSession(OrganizerSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSessions();
    final updated = [
      session,
      ...existing.where((s) => s.eventId != session.eventId),
    ].take(10);
    await prefs.setStringList(
      _sessionsKey,
      updated.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<void> removeSession(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSessions();
    final updated = existing.where((s) => s.eventId != eventId).toList();
    await prefs.setStringList(
      _sessionsKey,
      updated.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }
}
