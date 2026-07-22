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

  bool _busy = false;
  String? _error;
  bool _existingSportsReady = false;
  bool _existingProfileReady = false;
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

  bool get _canSubmit => _firstRegisteredSport != null;

  bool get _tennisRegistered => _selectedGrade[Sport.tennis] != null;

  bool get _canAdvance => switch (_step) {
        0 => _realName.text.trim().length >= 2 &&
            _birthDate != null &&
            !isUnderMinSignupAge(_birthDate!, DateTime.now()),
        1 => _regionCode != null,
        _ => _canSubmit,
      };

  Future<void> _pickBirthDate() async {
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
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (picked == null) return;

    final PreparedClubImage image;
    try {
      image = await prepareClubImage(picked);
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
        if (_realName.text.trim().isEmpty &&
            (profile.name?.isNotEmpty ?? false)) {
          _realName.text = profile.name!;
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
    final used = _orgs.map((o) => o.org).toSet();
    final available =
        tennisOrgs.where((o) => !used.contains(o)).toList(growable: false);
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

    if (picked != null) {
      setState(() {
        _orgs.add(_OrgDraft(org: picked));
        _primaryOrg ??= picked;
      });
    }
  }

  void _removeOrg(String org) {
    setState(() {
      _orgs.removeWhere((o) => o.org == org);
      if (_primaryOrg == org) {
        _primaryOrg = _orgs.isEmpty ? null : _orgs.first.org;
      }
    });
  }

  void _setPrimaryOrg(String org) {
    setState(() => _primaryOrg = org);
  }

  // ───────────────────────────────────────────────────
  // submit
  // ───────────────────────────────────────────────────
  Future<void> _submit() async {
    if (AppConfig.userDesignPreview) {
      context.go('/');
      return;
    }

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
      if (_tennisRegistered && _orgs.isNotEmpty) {
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
    _prepareExistingProfile(ref.watch(myProfileProvider).valueOrNull);
    _prepareExistingSports(ref.watch(userSportsProvider).valueOrNull);
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
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '이름 (실명)',
                hintText: '대회·클럽 신청에 사용돼요',
                prefixIcon: Icon(Icons.person_outline_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: AllRoundE2EKeys.onboardingNicknameField,
              controller: _nickname,
              maxLength: 10,
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
          Text('출전 부서 선택', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: tennisDivisions.where((d) => d.org == draft.org).map((d) {
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
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.score,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
}
