import 'package:shared_preferences/shared_preferences.dart';

const _legacyProfileAvatarKey = 'profile.avatar.base64';
const _notificationPreferenceKeys = [
  'notify.tournament_deadline',
  'notify.club_updates',
  'notify.coachbot_replies',
  'notify.sound',
];

String profileAvatarKeyForUser(String userId) {
  if (userId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must not be empty');
  }
  return 'profile.avatar.base64.$userId';
}

/// Removes device-local data that must not survive an account boundary.
Future<void> clearLocalUserPreferences(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(profileAvatarKeyForUser(userId));
  await prefs.remove(_legacyProfileAvatarKey);
  for (final key in _notificationPreferenceKeys) {
    await prefs.remove(key);
  }
}

/// The old avatar key was shared by every account on the device. Never migrate
/// it into a user-scoped key because ownership cannot be proven.
Future<void> removeLegacyUnscopedProfileAvatar(
  SharedPreferences prefs,
) async {
  await prefs.remove(_legacyProfileAvatarKey);
}
