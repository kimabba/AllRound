import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import '../../models/tournament.dart';
import '../../services/local_user_preferences.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';
import '../../utils/age.dart';
import '../../utils/club_image_upload.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/app_toast.dart';

// 지역 선택지는 grade_labels.dart 의 regionCodes(표준 17개 광역시도) 정본을 그대로 쓴다.
// code=label 1:1 이므로 별도 choices 목록이나 displayLabel 이중 상태가 필요 없다.

/// 협회별로 고른 부서 코드 집합을 받아, 저장해도 되는지 판정한다(JY-136).
///
/// 빈 집합이 하나라도 있으면 false. 그 협회는 `division_codes` 가 빈 배열로
/// 저장되는데, 자격매칭은 `expand_division_codes(division_codes) &&
/// eligible_grades` 배열 교집합이라 빈 배열이면 교집합이 항상 0 —
/// "내 등급 대회만" 이 에러도 안내도 없이 0건이 된다.
bool tennisOrgSelectionsAreComplete(Iterable<Set<String>> selectedPerOrg) =>
    selectedPerOrg.every((codes) => codes.isNotEmpty);

/// 실명 칸에 닉네임이 들어오는 걸 막는다.
///
/// 이 칸의 값(users.name)은 협회 랭킹표의 선수명과 글자까지 같아야 후보 매칭
/// (my_ranking_candidates)이 붙는다. 실측(2026-08-05 프로덕션) 가입자 20명 중
/// 절반이 `이름1` 같은 값이라 매칭이 0건이었다. 랭킹표가 한글 실명이므로 한글만
/// 받는다.
///
/// 상한이 7자인 이유: 법정 이름 5자 제한은 성을 뺀 기준이라, 복성 `남궁`+5자
/// 이름이면 7자가 된다. `테니스왕` 같은 한글 닉네임은 이 검사로 못 거른다 — 그건
/// 관리자 승인 단계에서 본다. 여기서 막는 건 숫자·영문·자모·특수문자다.
// ponytail: NFD(자모 분해) 로 붙여넣으면 거부된다. Dart 에 유니코드 정규화가
// 없어 패키지를 붙여야 하는데, 에러 문구를 보고 직접 타이핑하면 풀리는 문제라
// 그대로 둔다.
final _realNamePattern = RegExp(r'^[가-힣]{2,7}$');

bool isValidRealName(String value) => _realNamePattern.hasMatch(value.trim());

/// 재진입 때 실명 칸에 되돌릴 값. 규칙 밖이면 null — 칸을 비워 직접 쓰게 한다.
///
/// 가입 트리거가 users.name 을 `split_part(email,'@',1)` 로 채워둔다
/// (20260719010238_enforce_pre_account_age.sql). 그대로 복원하면 `tennis1`
/// 같은 자동 생성값이 칸에 들어앉고 사용자는 그게 자기 실명인 줄 안다 —
/// 실측 20명 중 10명이 이 값이다.
String? restoredRealName(String? savedName) =>
    isValidRealName(savedName ?? '') ? savedName : null;

/// 서버에 등록돼 있는데 화면 초안에는 없는 협회를 고른다(#337).
///
/// 복원이 늦게 도착하는 사이 사용자가 협회를 먼저 추가할 수 있다. 그때 복원을
/// 통째로 건너뛰면 서버 협회가 저장 목록에서 빠지고, `saveTennisOrgs` 의
/// delete-all 이 그걸 지운다 — 고치려던 유실이 그대로 재발한다. 둘을 합친다.
List<UserTennisOrg> tennisOrgsMissingFromDraft(
  Iterable<UserTennisOrg> saved,
  Set<String> draftedOrgs,
) =>
    saved.where((o) => !draftedOrgs.contains(o.org)).toList();

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _realName = TextEditingController();
  final TextEditingController _nickname = TextEditingController();
  DateTime? _birthDate;
  Uint8List? _avatarBytes;
  int _step = 0;

  // 종목·등급
  final Map<Sport, String?> _selectedGrade = {
    Sport.tennis: null,
    Sport.futsal: null,
  };
  Sport _primarySport = Sport.tennis;

  // 권역 (테니스 한정, 선택)
  String? _regionCode;

  // Multi-org (테니스 한정, 다중)
  final List<_OrgDraft> _orgs = [];
  String? _primaryOrg;
  bool _primaryOrgTouched = false;

  bool _busy = false;
  String? _error;
  bool _existingSportsReady = false;
  bool _existingProfileReady = false;
  bool _existingOrgsReady = false;
  bool _profilePhotoReady = false;
  bool _sportsTouched = false;

  String? get _profileAvatarPrefsKey {
    final userId = ref.read(currentUserProvider)?.id;
    return userId == null ? null : profileAvatarKeyForUser(userId);
  }

  Sport? get _firstRegisteredSport {
    for (final sport in Sport.values) {
      if (_selectedGrade[sport] != null) return sport;
    }
    return null;
  }

  Sport get _effectivePrimarySport {
    if (_selectedGrade[_primarySport] != null) return _primarySport;
    return _firstRegisteredSport ?? _primarySport;
  }

  bool get _canSubmit =>
      _firstRegisteredSport != null &&
      // 협회를 추가했으면 부서를 최소 1개 골라야 넘어간다. 테니스 미등록이면
      // _orgs 는 저장되지 않으므로(:438) 검사하지 않는다.
      (!_tennisRegistered ||
          tennisOrgSelectionsAreComplete(
              _orgs.map((o) => o.selectedDivisionCodes)));

  bool get _tennisRegistered => _selectedGrade[Sport.tennis] != null;

  bool get _canAdvance => switch (_step) {
        0 => isValidRealName(_realName.text) &&
            _birthDate != null &&
            !isUnderMinSignupAge(_birthDate!, DateTime.now()),
        1 => _regionCode != null,
        _ => _canSubmit,
      };

  Future<void> _pickBirthDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: '생년월일 선택',
    );
    if (!mounted) return;
    if (picked != null) {
      final underage = isUnderMinSignupAge(picked, now);
      setState(() {
        _birthDate = picked;
        _error = underage ? '만 $kMinSignupAge세 이상만 가입할 수 있습니다.' : null;
      });
    }
  }

  String _formatBirthDate(DateTime d) =>
      '${d.year}년 ${d.month.toString().padLeft(2, '0')}월 '
      '${d.day.toString().padLeft(2, '0')}일';

  Future<void> _prepareProfilePhoto() async {
    if (_profilePhotoReady) return;
    _profilePhotoReady = true;
    final avatarKey = _profileAvatarPrefsKey;
    final prefs = await SharedPreferences.getInstance();
    await removeLegacyUnscopedProfileAvatar(prefs);
    final avatarBase64 = avatarKey == null ? null : prefs.getString(avatarKey);
    if (!mounted || avatarBase64 == null || avatarBase64.isEmpty) return;
    setState(() => _avatarBytes = base64Decode(avatarBase64));
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final avatarKey = _profileAvatarPrefsKey;
    if (avatarKey == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (picked == null) return;

    final PreparedClubImage image;
    try {
      // 프로필 사진은 나중에 profile-avatars(3MB) 로 올라간다.
      image = await prepareClubImage(picked, maxBytes: profileAvatarMaxBytes);
    } on ClubImagePreparationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(avatarKey, base64Encode(image.bytes));
    if (!mounted) return;
    setState(() => _avatarBytes = image.bytes);
  }

  Future<void> _removeProfilePhoto() async {
    final avatarKey = _profileAvatarPrefsKey;
    final prefs = await SharedPreferences.getInstance();
    if (avatarKey != null) await prefs.remove(avatarKey);
    if (!mounted) return;
    setState(() => _avatarBytes = null);
  }

  Future<void> _showProfilePhotoSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _PhotoSheetAction(
                  icon: Icons.photo_camera_rounded,
                  label: '카메라로 촬영',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickProfilePhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                _PhotoSheetAction(
                  icon: Icons.photo_library_rounded,
                  label: '앨범에서 선택',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickProfilePhoto(ImageSource.gallery);
                  },
                ),
                if (_avatarBytes != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _PhotoSheetAction(
                    icon: Icons.delete_outline_rounded,
                    label: '프로필 사진 삭제',
                    accentColor: cs.error,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _removeProfilePhoto();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _prepareExistingSports(List<UserSport>? sports) {
    if (_existingSportsReady || sports == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _existingSportsReady) return;
      if (_sportsTouched || sports.isEmpty) {
        setState(() => _existingSportsReady = true);
        return;
      }

      final selectedGrade = Map<Sport, String?>.from(_selectedGrade);
      final validSports = <UserSport>[];
      for (final userSport in sports) {
        final sport = sportFromString(userSport.sport);
        if (!gradesFor(sport).contains(userSport.grade)) continue;
        selectedGrade[sport] = userSport.grade;
        validSports.add(userSport);
      }

      final primary =
          validSports.where((sport) => sport.isPrimary).firstOrNull ??
              validSports.firstOrNull;
      final primarySport =
          primary == null ? _primarySport : sportFromString(primary.sport);
      final fallbackSport = selectedGrade.entries
          .where((entry) => entry.value != null)
          .map((entry) => entry.key)
          .firstOrNull;
      setState(() {
        _selectedGrade
          ..clear()
          ..addAll(selectedGrade);
        _primarySport = selectedGrade[primarySport] == null
            ? (fallbackSport ?? primarySport)
            : primarySport;
        _existingSportsReady = true;
      });
    });
  }

  /// 재진입 시 이미 등록한 협회를 화면으로 복원한다(#337).
  ///
  /// `saveTennisOrgs` 는 delete-all + insert 라 화면이 보낸 목록이 곧 전부가
  /// 된다. 복원하지 않으면 협회를 하나 추가해 저장하는 순간 기존 협회가 통째로
  /// 사라진다. 복원이 끝나기 전에는 `_submit` 이 저장 자체를 건너뛴다.
  ///
  /// 복원 전에 사용자가 직접 추가했다 지운 협회가 서버에도 있으면 여기서 다시
  /// 올라온다. 되살아난 것처럼 보이지만 의도한 동작이다 — 그 삭제는 서버에
  /// 무엇이 있는지 모르는 상태에서 한 것이라 서버 상태에 대한 의사가 아니다.
  /// 존중하면 #337 이 그대로 재발한다(모르는 채 남의 데이터를 지운다). 복원이
  /// 끝난 뒤의 삭제는 `_existingOrgsReady` 가 재실행을 막으므로 그대로 남는다.
  void _prepareExistingOrgs(List<UserTennisOrg>? orgs) {
    if (_existingOrgsReady || orgs == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _existingOrgsReady) return;
      setState(() {
        // 사용자가 먼저 고른 협회는 그대로 두고, 서버에만 있는 것을 채운다.
        final missing = tennisOrgsMissingFromDraft(
          orgs,
          _orgs.map((o) => o.org).toSet(),
        );
        _orgs.addAll(missing.map(_OrgDraft.fromSaved));
        // 라디오로 직접 고른 주 협회만 존중한다. `_addOrg` 가 자동으로 세운
        // 값(먼저 추가한 협회)까지 존중하면, 복원이 늦은 사이 협회를 하나
        // 추가한 것만으로 서버의 주 협회가 조용히 바뀐다.
        if (!_primaryOrgTouched) {
          _primaryOrg =
              (orgs.where((o) => o.isPrimary).firstOrNull ?? orgs.firstOrNull)
                      ?.org ??
                  _primaryOrg;
        }
        // 협회가 하나라도 있으면 주 협회도 있어야 한다. 직접 고른 협회를 다시
        // 지워 _primaryOrg 가 null 이 된 채 복원이 도착하면(touched 라 위 분기가
        // 건너뛴다) 아무도 primary 가 아닌 채로 저장된다.
        _primaryOrg ??= _orgs.firstOrNull?.org;
        _existingOrgsReady = true;
      });
    });
  }

  void _prepareExistingProfile(UserProfile? profile) {
    // profile == null 은 프로바이더가 아직 로딩 중이거나, 신규 유저라 row가
    // 없다는 뜻이다. 신규 유저는 채울 값이 없으므로 대기만 하면 되고,
    // 아래 가드가 두 경우를 함께 처리한다. 재진입(종목 추가·맞춤 설정) 시
    // 기존 실명/닉네임/생년월일을 복원해 재입력 강요·닉네임 유실을 막는다.
    if (_existingProfileReady || profile == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _existingProfileReady) return;
      setState(() {
        // 사용자가 이미 직접 입력한 값은 덮어쓰지 않는다.
        // 실명만 규칙 게이트를 거친다(restoredRealName). 닉네임·생년월일은
        // 사용자가 실제로 입력한 값이라 그대로 되돌린다.
        final restoredName = restoredRealName(profile.name);
        if (_realName.text.trim().isEmpty && restoredName != null) {
          _realName.text = restoredName;
        }
        if (_nickname.text.trim().isEmpty &&
            (profile.nickname?.isNotEmpty ?? false)) {
          _nickname.text = profile.nickname!;
        }
        _birthDate ??= profile.birthDate;
        // 지역도 프로필에서 복원. 17시도 정본에 있는 코드만 쓴다 — deprecated
        // 묶음 코드(seoul_metro 등)는 목록에 없으므로 다시 선택하게 둔다.
        // 사용자가 이미 직접 고른 값은 덮어쓰지 않는다.
        final savedRegion = profile.primaryRegion;
        if (_regionCode == null &&
            savedRegion != null &&
            regionCodes.contains(savedRegion)) {
          _regionCode = savedRegion;
        }
        _existingProfileReady = true;
      });
    });
  }

  void _selectGrade(Sport sport, String? grade) {
    setState(() {
      _sportsTouched = true;
      _selectedGrade[sport] = grade;
      if (grade != null) {
        _primarySport = sport;
        return;
      }
      if (grade == null && _primarySport == sport) {
        _primarySport = _firstRegisteredSport ?? sport;
      }
    });
  }

  // ───────────────────────────────────────────────────
  // org 추가/삭제/수정
  // ───────────────────────────────────────────────────
  Future<void> _addOrg() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final used = _orgs.map((o) => o.org).toSet();
    // 부서 0개 협회를 고르면 부서 칩이 하나도 안 떠서 division_codes 가 빈 채로
    // 저장되고, 자격매칭(배열 교집합)이 항상 0건이 된다(JY-136). 제보 화면과
    // 같은 가드를 쓴다 — 부서가 추가되면 카탈로그에서 자동 반영된다.
    final available = tennisOrgsWithDivisions
        .where((o) => !used.contains(o))
        .toList(growable: false);
    if (available.isEmpty) {
      AppToast.show(context, '등록할 수 있는 협회를 모두 추가했어요', kind: AppToastKind.info);
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('협회 선택', style: Theme.of(c).textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final org = available[i];
                  return ListTile(
                    title: Text(tennisOrgLabel(org)),
                    onTap: () => Navigator.of(c).pop(org),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );

    // 시트가 열려 있는 사이 복원(_prepareExistingOrgs)이 같은 협회를 채웠을 수
    // 있다 — 선택지는 시트를 열 때의 스냅샷이라 그걸 모른다. 그대로 추가하면
    // 같은 org 가 두 번 저장돼 PK 충돌로 insert 가 통째로 실패하고, 그 앞의
    // delete-all 은 이미 커밋돼 협회가 전멸한다.
    if (picked != null && !_orgs.any((o) => o.org == picked)) {
      setState(() {
        _orgs.add(_OrgDraft(org: picked));
        _primaryOrg ??= picked;
      });
    }
  }

  void _removeOrg(String org) {
    setState(() {
      for (final o in _orgs.where((o) => o.org == org).toList()) {
        o.divisionLocal.dispose();
        o.score.dispose();
      }
      _orgs.removeWhere((o) => o.org == org);
      if (_primaryOrg == org) {
        _primaryOrg = _orgs.isEmpty ? null : _orgs.first.org;
      }
    });
  }

  void _setPrimaryOrg(String org) {
    setState(() {
      _primaryOrgTouched = true;
      _primaryOrg = org;
    });
  }

  // ───────────────────────────────────────────────────
  // submit
  // ───────────────────────────────────────────────────
  Future<void> _submit() async {
    if (AppConfig.userDesignPreview) {
      context.go('/');
      return;
    }

    // 0단계 버튼이 이미 막지만 여기서 한 번 더 본다 — users.name 이 실제로
    // 바뀌는 지점은 여기뿐이고, 화면 흐름이 바뀌어도 규칙이 따라오게 한다.
    if (!isValidRealName(_realName.text)) {
      setState(() {
        _step = 0;
        _error = '이름을 한글 실명 2~7자로 입력해 주세요.';
      });
      return;
    }

    // 등록해 둔 협회를 아직 못 불러왔으면 저장하지 않는다 — saveTennisOrgs 가
    // delete-all + insert 라, 비어 있는 _orgs 를 보내면 통째로 사라진다(#337).
    // 조용히 건너뛰면 이번에 고른 협회가 안내 없이 유실되므로 이유를 보여준다.
    if (_tennisRegistered && !_existingOrgsReady) {
      // 조회가 실패한 상태면 다시 눌러도 같은 에러만 뜬다. 재요청을 걸어
      // 일시적 오류에서 빠져나올 길을 준다.
      ref.invalidate(userTennisOrgsProvider);
      setState(() => _error = '등록한 협회를 불러오는 중입니다. 잠시 후 다시 시도해 주세요.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);

      await api.saveProfile(
        name: _realName.text.trim(),
        nickname: _nickname.text.trim(),
        birthDate: _birthDate!,
        // 지역은 종목·협회 등록 여부와 무관하게 항상 users.primary_region 에 남긴다.
        primaryRegion: _regionCode,
      );

      // 1) user_sports
      final sports = <UserSport>[];
      final primarySport = _effectivePrimarySport;
      for (final s in Sport.values) {
        final grade = _selectedGrade[s];
        if (grade == null) continue;
        sports.add(
          UserSport(
            sport: sportToString(s),
            grade: grade,
            isPrimary: s == primarySport,
          ),
        );
      }
      await api.saveUserSports(sports);

      // 2) user_tennis_orgs (테니스 등록자만)
      // 복원이 끝난 것은 위 가드가 보장한다. 빈 목록도 그대로 보낸다 —
      // 사용자가 협회를 전부 지운 것이므로 삭제가 맞다(예전 _orgs.isNotEmpty
      // 가드는 협회 전체 삭제를 아예 불가능하게 만들고 있었다).
      if (_tennisRegistered) {
        final orgRows = _orgs.map((o) {
          return UserTennisOrg(
            org: o.org,
            division: o.divisionLocal.text.trim().isEmpty
                ? 'default'
                : o.divisionLocal.text.trim(),
            divisionCodes: o.selectedDivisionCodes.toList(),
            score: double.tryParse(o.score.text.trim()),
            // region_code 는 deprecated — 지역은 users.primary_region 단일 소스.
            isPrimary: o.org == _primaryOrg,
          );
        }).toList();
        await api.saveTennisOrgs(orgRows);
      }

      ref.invalidate(myProfileProvider);
      ref.invalidate(userSportsProvider);
      ref.invalidate(userTennisOrgsProvider);
      if (mounted) context.go('/');
    } catch (e) {
      final msg = e.toString().contains('MINOR_NOT_ALLOWED')
          ? '만 $kMinSignupAge세 이상만 가입할 수 있습니다.'
          : '프로필을 저장하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleBack() {
    if (_step > 0) {
      setState(() => _step--);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/more');
  }

  @override
  void dispose() {
    _realName.dispose();
    _nickname.dispose();
    for (final o in _orgs) {
      o.divisionLocal.dispose();
      o.score.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────────────────────────────
  // build
  // ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _prepareProfilePhoto();
    _prepareExistingProfile(ref.watch(myProfileProvider).value);
    _prepareExistingSports(ref.watch(userSportsProvider).value);
    _prepareExistingOrgs(ref.watch(userTennisOrgsProvider).value);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      key: AllRoundE2EKeys.onboardingScreen,
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingTopBar(
              step: _step,
              onBack: _handleBack,
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.huge,
                ),
                children: [
                  _StepProgress(current: _step),
                  const SizedBox(height: AppSpacing.xl),
                  if (_step == 0) _buildNicknameStep(cs, tt),
                  if (_step == 1) _buildRegionStep(cs, tt),
                  if (_step == 2) ...[
                    _buildSportStepHeader(cs, tt),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSportCard(Sport.futsal),
                    const SizedBox(height: AppSpacing.md),
                    _buildSportCard(Sport.tennis),
                    if (_tennisRegistered) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _buildOrgsSection(),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      variant: AppCardVariant.outlined,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: cs.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: tt.bodyMedium?.copyWith(color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.huge),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: AppPrimaryButton(
                  key: AllRoundE2EKeys.onboardingPrimaryAction,
                  label: _step == 2 ? '시작하기' : '다음',
                  onPressed: _canAdvance && !_busy
                      ? () {
                          if (_step < 2) {
                            setState(() => _step++);
                          } else {
                            _submit();
                          }
                        }
                      : null,
                  loading: _busy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────
  // sub-widgets
  // ───────────────────────────────────────────────────
  Widget _buildNicknameStep(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '내 운동 생활을\n가볍게 시작해요',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.18,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '기본 정보만 입력하면 대회와 클럽을 내 조건에 맞춰 볼 수 있어요.',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '프로필 설정',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '실명은 대회·클럽 신청에, 닉네임은 앱 활동에 사용돼요.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              button: true,
              label: '프로필 사진 선택',
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: _showProfilePhotoSheet,
                  child: Stack(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.16),
                            width: 1,
                          ),
                          image: _avatarBytes == null
                              ? null
                              : DecorationImage(
                                  image: MemoryImage(_avatarBytes!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: _avatarBytes == null
                            ? Icon(
                                Icons.person_rounded,
                                size: 34,
                                color: cs.primary,
                              )
                            : null,
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: cs.surface, width: 3),
                          ),
                          child: Icon(
                            Icons.camera_alt_rounded,
                            color: cs.onPrimary,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: AllRoundE2EKeys.onboardingNameField,
              controller: _realName,
              maxLength: 20,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '이름 (실명)',
                hintText: '대회·클럽 신청에 사용돼요',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                counterText: '',
                // 빈 칸에는 에러를 띄우지 않는다 — 아직 입력을 시작도 안 했다.
                errorText: _realName.text.trim().isEmpty ||
                        isValidRealName(_realName.text)
                    ? null
                    : '한글 실명 2~7자로 입력해주세요 (협회 랭킹표와 맞춰야 해요)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: AllRoundE2EKeys.onboardingNicknameField,
              controller: _nickname,
              maxLength: 10,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '닉네임 (선택)',
                hintText: '앱 활동에 표시돼요',
                prefixIcon: Icon(Icons.badge_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              key: AllRoundE2EKeys.onboardingBirthDate,
              onTap: _pickBirthDate,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '생년월일',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                child: Text(
                  _birthDate == null
                      ? '생년월일을 선택하세요'
                      : _formatBirthDate(_birthDate!),
                  style: _birthDate == null
                      ? tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)
                      : tt.bodyLarge,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_birthDate != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '현재 만 ${ageOn(_birthDate!, DateTime.now())}세',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '생년월일은 연령 확인과 대회 참가 자격 매칭에만 사용되며 다른 사용자에게 공개되지 않습니다.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: _showProfilePhotoSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_a_photo_rounded, color: cs.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '카메라 촬영 또는 앨범에서 사진 선택',
                          style: tt.labelLarge?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: cs.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegionStep(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주로 활동하는\n지역을 알려주세요',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.22,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '근처 대회와 클럽을 추천해드릴게요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xxl),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 2.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final code in regionCodes)
              _RegionOption(
                key: AllRoundE2EKeys.onboardingRegion(code),
                label: regionLabel(code),
                selected: _regionCode == code,
                onTap: () => setState(() => _regionCode = code),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSportStepHeader(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '어떤 운동을\n주로 하세요?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.22,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_regionCode == null ? '' : '${regionLabel(_regionCode!)}에서 '}활동할 종목과 경력을 선택하세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSportCard(Sport sport) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grades = gradesFor(sport);
    final selected = _selectedGrade[sport];
    final accent = AppSportColors.forSport(sportToString(sport));

    return AppCard(
      variant: AppCardVariant.outlined,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  sport == Sport.tennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                sportLabel(sport),
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (selected != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<Sport>(
                      // ignore: deprecated_member_use
                      groupValue: _effectivePrimarySport,
                      value: sport,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() {
                        _sportsTouched = true;
                        _primarySport = v ?? sport;
                      }),
                    ),
                    Text(
                      '기본 종목',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppChip(
                label: '등록 안 함',
                selected: selected == null,
                leadingIcon: selected == null ? Icons.check_rounded : null,
                onTap: () => _selectGrade(sport, null),
              ),
              for (final g in grades)
                AppChip(
                  key: AllRoundE2EKeys.onboardingGrade(
                    sportToString(sport),
                    g,
                  ),
                  label: gradeLabel(g),
                  selected: selected == g,
                  leadingIcon: selected == g ? Icons.check_rounded : null,
                  selectedColor: accent.withValues(alpha: 0.18),
                  onTap: () => _selectGrade(sport, g),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrgsSection() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              Text('테니스 협회 등록', style: tt.titleLarge),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '(선택, 다중)',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'KATA·KATO·광주협회 등 여러 협회에 등록한 경우 협회별 등급을 따로 입력하세요.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final o in _orgs) ...[
          _buildOrgCard(o),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          variant: AppCardVariant.outlined,
          onTap: _addOrg,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('협회 추가', style: tt.labelLarge?.copyWith(color: cs.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrgCard(_OrgDraft draft) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPrimary = _primaryOrg == draft.org;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tennisOrgLabel(draft.org), style: tt.titleMedium),
              ),
              IconButton(
                onPressed: () => _removeOrg(draft.org),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                tooltip: '삭제',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('내 랭킹 등급 선택', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: rankingGradesForOrg(draft.org).map((d) {
              final selected = draft.selectedDivisionCodes.contains(d.code);
              return FilterChip(
                label: Text(d.label),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      draft.selectedDivisionCodes.add(d.code);
                    } else {
                      draft.selectedDivisionCodes.remove(d.code);
                    }
                    draft.divisionLocal.text = tennisDivisions
                        .where((td) =>
                            draft.selectedDivisionCodes.contains(td.code))
                        .map((td) => td.label)
                        .join(' · ');
                  });
                },
              );
            }).toList(),
          ),
          if (draft.selectedDivisionCodes.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '내 랭킹 등급을 1개 이상 골라야 등급에 맞는 대회를 찾아줄 수 있어요',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.score,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '점수 (선택, 0.0 ~ 10.0)',
              hintText: '예: 5.0',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Radio<String>(
                // ignore: deprecated_member_use
                groupValue: _primaryOrg,
                value: draft.org,
                // ignore: deprecated_member_use
                onChanged: (_) => _setPrimaryOrg(draft.org),
              ),
              Text(
                '주 협회',
                style: tt.labelMedium?.copyWith(
                  color: isPrimary ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const labels = ['프로필', '지역', '종목'];

    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                child: Text(
                  '${index + 1}  ${labels[index]}',
                  textAlign: TextAlign.center,
                  style: tt.labelMedium?.copyWith(
                    color: index == current ? cs.primary : cs.onSurfaceVariant,
                    fontWeight:
                        index == current ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(
          value: (current + 1) / labels.length,
          minHeight: 2,
          color: cs.primary,
          backgroundColor: cs.outlineVariant,
        ),
      ],
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({
    required this.step,
    required this.onBack,
  });

  final int step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final titles = ['프로필 설정', '활동 지역', '종목·경력'];

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(onBack == null
                ? Icons.close_rounded
                : Icons.arrow_back_rounded),
            tooltip: onBack == null ? '닫기' : '이전',
          ),
          Expanded(
            child: Text(
              titles[step],
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${step + 1}/3',
            style: tt.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSheetAction extends StatelessWidget {
  const _PhotoSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = accentColor ?? cs.primary;

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: tt.titleSmall?.copyWith(
                    color: accentColor ?? cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionOption extends StatelessWidget {
  const _RegionOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected ? cs.primary : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: tt.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrgDraft {
  final String org;
  final TextEditingController divisionLocal = TextEditingController();
  final TextEditingController score = TextEditingController();
  final Set<String> selectedDivisionCodes = {};

  _OrgDraft({required this.org});

  /// DB 에 저장된 협회를 화면 초안으로 되돌린다(#337).
  factory _OrgDraft.fromSaved(UserTennisOrg saved) {
    final draft = _OrgDraft(org: saved.org);
    // 카탈로그에 없는 옛 코드도 그대로 싣는다. 걸러내면 저장 때 사라진다.
    // ponytail: 그 대가로 카탈로그 밖 코드는 화면에 안 보인다. 옛 코드만 남은
    // 협회는 칩이 하나도 안 뜨는데 selectedDivisionCodes 는 비어 있지 않아
    // _canSubmit 의 "부서 1개 이상" 경고가 안 뜬다. 옛·현행이 섞인 협회는 현행
    // 칩만 보이고, 그 칩을 껐다 켜면 divisionLocal 라벨이 현행 카탈로그로만
    // 다시 만들어져 옛 라벨이 빠진다(코드 자체는 남는다). 프로덕션 5행에는
    // 카탈로그 밖 코드가 0건이라 두고 본다 — 필요해지면 그 코드를 UI 에
    // '만료된 부서'로 따로 보여주고 라벨 재계산에 포함한다.
    draft.selectedDivisionCodes.addAll(saved.divisionCodes);
    // 'default' 는 라벨이 빈 채로 저장될 때 쓰는 대체값이라 화면엔 되돌리지 않는다.
    if (saved.division != 'default') draft.divisionLocal.text = saved.division;
    final score = saved.score;
    if (score != null) {
      draft.score.text =
          score == score.roundToDouble() ? '${score.toInt()}' : '$score';
    }
    return draft;
  }
}
