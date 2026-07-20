import 'package:allround/services/local_user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('profile avatar storage is scoped to the authenticated user', () {
    expect(
      profileAvatarKeyForUser('user-a'),
      isNot(profileAvatarKeyForUser('user-b')),
    );
    expect(() => profileAvatarKeyForUser(''), throwsArgumentError);
  });

  test('account boundary removes private and legacy local values', () async {
    SharedPreferences.setMockInitialValues({
      profileAvatarKeyForUser('user-a'): 'private-a',
      profileAvatarKeyForUser('user-b'): 'private-b',
      'profile.avatar.base64': 'legacy-owner-unknown',
      'notify.sound': false,
    });

    await clearLocalUserPreferences('user-a');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(profileAvatarKeyForUser('user-a')), isNull);
    expect(prefs.getString(profileAvatarKeyForUser('user-b')), 'private-b');
    expect(prefs.getString('profile.avatar.base64'), isNull);
    expect(prefs.getBool('notify.sound'), isNull);
  });
}
