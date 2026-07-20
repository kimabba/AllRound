import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/providers.dart';
import '../services/local_user_preferences.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/club_image_upload.dart';
import '../widgets/profile/profile_hero_widgets.dart';
import '../widgets/profile/profile_records_widgets.dart';
import '../widgets/profile/profile_settings_widgets.dart';
import '../widgets/profile/profile_sports_widgets.dart';

const _notifyTournamentPrefsKey = 'notify.tournament_deadline';
const _notifyClubPrefsKey = 'notify.club_updates';
const _notifyCoachPrefsKey = 'notify.coachbot_replies';
const _notifySoundPrefsKey = 'notify.sound';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Uint8List? _avatarBytes;
  bool _notifyTournament = true;
  bool _notifyClub = true;
  bool _notifyCoach = false;
  bool _notifySound = true;

  String? get _profileAvatarPrefsKey {
    final userId = ref.read(currentUserProvider)?.id;
    return userId == null ? null : profileAvatarKeyForUser(userId);
  }

  @override
  void initState() {
    super.initState();
    _loadProfileSettings();
  }

  Future<void> _loadProfileSettings() async {
    final avatarKey = _profileAvatarPrefsKey;
    final prefs = await SharedPreferences.getInstance();
    await removeLegacyUnscopedProfileAvatar(prefs);
    final avatarBase64 = avatarKey == null ? null : prefs.getString(avatarKey);
    if (!mounted) return;
    setState(() {
      if (avatarBase64 != null && avatarBase64.isNotEmpty) {
        _avatarBytes = base64Decode(avatarBase64);
      }
      _notifyTournament = prefs.getBool(_notifyTournamentPrefsKey) ?? true;
      _notifyClub = prefs.getBool(_notifyClubPrefsKey) ?? true;
      _notifyCoach = prefs.getBool(_notifyCoachPrefsKey) ?? false;
      _notifySound = prefs.getBool(_notifySoundPrefsKey) ?? true;
    });
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
                SheetActionRow(
                  icon: Icons.photo_camera_rounded,
                  label: '카메라로 촬영',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickProfilePhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                SheetActionRow(
                  icon: Icons.photo_library_rounded,
                  label: '앨범에서 선택',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickProfilePhoto(ImageSource.gallery);
                  },
                ),
                if (_avatarBytes != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SheetActionRow(
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

  Future<void> _showNotificationSettings() async {
    var tournament = _notifyTournament;
    var club = _notifyClub;
    var coach = _notifyCoach;
    var sound = _notifySound;

    final result = await showDialog<
        ({bool tournament, bool club, bool coach, bool sound})>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(
                '알림 설정',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NotificationSwitchTile(
                    icon: Icons.emoji_events_outlined,
                    title: '대회 알림',
                    subtitle: 'D-3·신청 마감 알림',
                    value: tournament,
                    onChanged: (value) =>
                        setDialogState(() => tournament = value),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  NotificationSwitchTile(
                    icon: Icons.groups_2_outlined,
                    title: '클럽 알림',
                    subtitle: '내 클럽 공지·업데이트',
                    value: club,
                    onChanged: (value) => setDialogState(() => club = value),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  NotificationSwitchTile(
                    icon: Icons.smart_toy_outlined,
                    title: '볼보이 알림',
                    subtitle: '답변·추천 업데이트',
                    value: coach,
                    onChanged: (value) => setDialogState(() => coach = value),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  NotificationSwitchTile(
                    icon: Icons.volume_up_outlined,
                    title: '알림음',
                    subtitle: '새 알림이 오면 기본 알림음 재생',
                    value: sound,
                    onChanged: (value) {
                      setDialogState(() => sound = value);
                      if (value) SystemSound.play(SystemSoundType.alert);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop((
                    tournament: tournament,
                    club: club,
                    coach: coach,
                    sound: sound,
                  )),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyTournamentPrefsKey, result.tournament);
    await prefs.setBool(_notifyClubPrefsKey, result.club);
    await prefs.setBool(_notifyCoachPrefsKey, result.coach);
    await prefs.setBool(_notifySoundPrefsKey, result.sound);
    if (!mounted) return;
    setState(() {
      _notifyTournament = result.tournament;
      _notifyClub = result.club;
      _notifyCoach = result.coach;
      _notifySound = result.sound;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final sports = ref.watch(userSportsProvider);
    final tennisOrgs = ref.watch(userTennisOrgsProvider);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final unreadNotificationCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    final email = user?.email ?? '';
    final emailPrefix = email.contains('@') ? email.split('@').first : email;
    // 앱 활동 표시명: 닉네임 → 실명 → 이메일 앞부분 → '사용자'
    final displayName =
        profile?.displayName ?? (emailPrefix.isEmpty ? '사용자' : emailPrefix);
    // 본인만 보는 정보 줄: 실명(표시명과 다를 때만) · 만 나이
    final realName = profile?.name?.trim();
    final age = profile?.ageOn(DateTime.now());
    final infoParts = <String>[
      if (realName != null && realName.isNotEmpty && realName != displayName)
        realName,
      if (age != null) '만 $age세',
    ];
    final infoLine = infoParts.isEmpty ? null : infoParts.join(' · ');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Scaffold(
      key: AllRoundE2EKeys.profileScreen,
      body: CustomScrollView(
        slivers: [
          ProfileHeroSliver(
            initial: initial,
            title: displayName,
            subtitle: email,
            infoLine: infoLine,
            sports: sports,
            tennisOrgs: tennisOrgs,
            avatarBytes: _avatarBytes,
            onAvatarTap: _showProfilePhotoSheet,
            onMoreTap: () => context.push('/more'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const MyClubsSection(),
                const SizedBox(height: AppSpacing.xl),
                const MyTournamentRecordsSection(),
                const SizedBox(height: AppSpacing.xl),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push('/onboarding'),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('맞춤 설정'),
                  ),
                ),
                SportsSection(sports: sports),
                const SizedBox(height: AppSpacing.xl),
                tennisOrgs.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (orgs) => orgs.isEmpty
                      ? const SizedBox.shrink()
                      : TennisOrgsSection(orgs: orgs),
                ),
                const SizedBox(height: AppSpacing.xl),
                ProfileServiceSection(
                  onRulesTap: () => context.push('/rules'),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppearanceSection(),
                const SizedBox(height: AppSpacing.xl),
                AccountSection(
                  ref: ref,
                  unreadNotificationCount: unreadNotificationCount,
                  tournamentNotificationsEnabled: _notifyTournament,
                  clubNotificationsEnabled: _notifyClub,
                  coachNotificationsEnabled: _notifyCoach,
                  onNotificationInboxTap: () => context.push('/notifications'),
                  onNotificationTap: _showNotificationSettings,
                ),
                const SizedBox(height: AppSpacing.xxxl),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
