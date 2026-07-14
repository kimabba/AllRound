import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _allowedSports = {'tennis', 'futsal'};
const _allowedMeetingDays = {'월', '화', '수', '목', '금', '토', '일'};
const _allowedGenderPreferences = {'mixed', 'male', 'female'};

class ClubCreateDraft {
  const ClubCreateDraft({
    required this.sport,
    required this.name,
    required this.region,
    required this.address,
    required this.contact,
    required this.website,
    required this.description,
    required this.monthlyFee,
    required this.meetingDays,
    required this.genderPreference,
    required this.step,
    required this.hadSelectedImages,
  });

  final String sport;
  final String name;
  final String region;
  final String address;
  final String contact;
  final String website;
  final String description;
  final String monthlyFee;
  final List<String> meetingDays;
  final String? genderPreference;
  final int step;
  final bool hadSelectedImages;

  bool get hasUserContent =>
      name.trim().isNotEmpty ||
      region.trim().isNotEmpty ||
      address.trim().isNotEmpty ||
      contact.trim().isNotEmpty ||
      website.trim().isNotEmpty ||
      description.trim().isNotEmpty ||
      monthlyFee.trim().isNotEmpty ||
      meetingDays.isNotEmpty ||
      genderPreference != null ||
      hadSelectedImages;

  String toJsonString() => jsonEncode(<String, Object?>{
        'version': 1,
        'sport': sport,
        'name': name,
        'region': region,
        'address': address,
        'contact': contact,
        'website': website,
        'description': description,
        'monthly_fee': monthlyFee,
        'meeting_days': meetingDays,
        'gender_preference': genderPreference,
        'step': step,
        'had_selected_images': hadSelectedImages,
      });

  static ClubCreateDraft? fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source) as Object?;
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
      return null;
    }

    final rawSport = decoded['sport'];
    final sport = rawSport is String && _allowedSports.contains(rawSport)
        ? rawSport
        : 'tennis';
    final rawDays = decoded['meeting_days'];
    final meetingDays = rawDays is List<Object?>
        ? rawDays
            .whereType<String>()
            .where(_allowedMeetingDays.contains)
            .toSet()
            .toList(growable: false)
        : const <String>[];
    final rawGender = decoded['gender_preference'];
    final genderPreference =
        rawGender is String && _allowedGenderPreferences.contains(rawGender)
            ? rawGender
            : null;
    final rawStep = decoded['step'];
    final step = rawStep is int ? rawStep.clamp(0, 2) : 0;

    return ClubCreateDraft(
      sport: sport,
      name: _stringValue(decoded['name']),
      region: _stringValue(decoded['region']),
      address: _stringValue(decoded['address']),
      contact: _stringValue(decoded['contact']),
      website: _stringValue(decoded['website']),
      description: _stringValue(decoded['description']),
      monthlyFee: _stringValue(decoded['monthly_fee']),
      meetingDays: meetingDays,
      genderPreference: genderPreference,
      step: step,
      hadSelectedImages: decoded['had_selected_images'] == true,
    );
  }
}

String _stringValue(Object? value) => value is String ? value : '';

class ClubCreateDraftStore {
  ClubCreateDraftStore(this._preferences);

  final SharedPreferences _preferences;

  String _key(String userId) => 'clubs.createDraft.v1.$userId';

  ClubCreateDraft? load(String userId) {
    final source = _preferences.getString(_key(userId));
    if (source == null) return null;
    return ClubCreateDraft.fromJsonString(source);
  }

  Future<void> save(String userId, ClubCreateDraft draft) async {
    await _preferences.setString(_key(userId), draft.toJsonString());
  }

  Future<void> clear(String userId) => _preferences.remove(_key(userId));
}
