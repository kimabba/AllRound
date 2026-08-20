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
    feeType: 'per_event',
    meetingDays: ['월', '수'],
    genderPreference: 'mixed',
    cardColor: '#176B63',
    step: 2,
    hadSelectedImages: true,
    latitude: 37.5,
    longitude: 127.1,
  );

  test('club create draft round-trips typed fields', () {
    final restored = ClubCreateDraft.fromJsonString(draft.toJsonString());

    expect(restored, isNotNull);
    expect(restored!.sport, 'tennis');
    expect(restored.name, '한강 클럽');
    expect(restored.meetingDays, ['월', '수']);
    expect(restored.genderPreference, 'mixed');
    expect(restored.feeType, 'per_event');
    expect(restored.cardColor, '#176B63');
    expect(restored.step, 2);
    expect(restored.hadSelectedImages, isTrue);
    expect(restored.latitude, 37.5);
    expect(restored.longitude, 127.1);
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
      feeType: 'monthly',
      meetingDays: [],
      genderPreference: 'mixed',
      cardColor: '#3156D8',
      step: 2,
      hadSelectedImages: false,
    );

    expect(emptyDraft.hasUserContent, isFalse);
    expect(
      resolveClubCreateSport(selectedSport: 'tennis', draft: emptyDraft),
      'tennis',
    );
  });

  test('작성 중인 임시저장이 있으면 임시저장 종목을 유지한다', () {
    expect(
      resolveClubCreateSport(selectedSport: 'futsal', draft: draft),
      'tennis',
    );
  });

  test('a non-default card color is draft content', () {
    const colorOnlyDraft = ClubCreateDraft(
      sport: 'tennis',
      name: '',
      region: '',
      address: '',
      contact: '',
      website: '',
      description: '',
      monthlyFee: '',
      feeType: 'monthly',
      meetingDays: [],
      genderPreference: null,
      cardColor: '#176B63',
      step: 0,
      hadSelectedImages: false,
    );

    expect(colorOnlyDraft.hasUserContent, isTrue);
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
    expect(restored.feeType, 'monthly');
    expect(restored.cardColor, '#3156D8');
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
