import 'package:allround/utils/club_create_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const draft = ClubCreateDraft(
    sport: 'tennis',
    name: '한강 클럽',
    region: '서울',
    address: '잠실',
    contact: '010-0000-0000',
    website: 'https://example.com',
    description: '즐겁게 운동해요',
    monthlyFee: '30000',
    meetingDays: ['월', '수'],
    genderPreference: 'mixed',
    step: 2,
    hadSelectedImages: true,
  );

  test('club create draft round-trips typed fields', () {
    final restored = ClubCreateDraft.fromJsonString(draft.toJsonString());

    expect(restored, isNotNull);
    expect(restored!.sport, 'tennis');
    expect(restored.name, '한강 클럽');
    expect(restored.meetingDays, ['월', '수']);
    expect(restored.genderPreference, 'mixed');
    expect(restored.step, 2);
    expect(restored.hadSelectedImages, isTrue);
    expect(restored.hasUserContent, isTrue);
  });

  test('default-only draft is not treated as user content', () {
    const emptyDraft = ClubCreateDraft(
      sport: 'tennis',
      name: '',
      region: '',
      address: '',
      contact: '',
      website: '',
      description: '',
      monthlyFee: '',
      meetingDays: [],
      genderPreference: null,
      step: 2,
      hadSelectedImages: false,
    );

    expect(emptyDraft.hasUserContent, isFalse);
  });

  test('club create draft rejects invalid JSON and filters unknown values', () {
    expect(ClubCreateDraft.fromJsonString('{broken'), isNull);

    final restored = ClubCreateDraft.fromJsonString(
      '{"version":1,"sport":"unknown","meeting_days":["월","월요일"],'
      '"gender_preference":"unknown","step":9}',
    );
    expect(restored, isNotNull);
    expect(restored!.sport, 'tennis');
    expect(restored.meetingDays, ['월']);
    expect(restored.genderPreference, isNull);
    expect(restored.step, 2);
  });

  test('draft store keeps drafts isolated by user and clears them', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = ClubCreateDraftStore(preferences);

    await store.save('user-a', draft);

    expect(store.load('user-a')?.name, '한강 클럽');
    expect(store.load('user-b'), isNull);
    await store.clear('user-a');
    expect(store.load('user-a'), isNull);
  });
}
