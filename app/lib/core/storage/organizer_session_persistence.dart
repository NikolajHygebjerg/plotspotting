import 'session_storage.dart';

Future<void> persistOrganizerSession({
  required String eventId,
  required String eventName,
  String? publicSlug,
}) async {
  await SessionStorage().saveSession(
    OrganizerSession(
      eventId: eventId,
      eventName: eventName,
      publicSlug: publicSlug,
    ),
  );
}
