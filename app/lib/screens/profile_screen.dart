import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/profile/profile_hero_widgets.dart';
import '../widgets/profile/profile_records_widgets.dart';
import '../widgets/profile/profile_settings_widgets.dart';
import '../widgets/profile/profile_sports_widgets.dart';

const _profileAvatarPrefsKey = 'profile.avatar.base64';
const _notifyTournamentPrefsKey = 'notify.tournament_deadline';
const _notifyClubPrefsKey = 'notify.club_updates';
const _notifyCoachPrefsKey = 'notify.coachbot_replies';

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

  @override
  void initState() {
    super.initState();
    _loadProfileSettings();
  }

  Future<void> _loadProfileSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarBase64 = prefs.getString(_profileAvatarPrefsKey);
    if (!mounted) return;
    setState(() {
      if (avatarBase64 != null && avatarBase64.isNotEmpty) {
        _avatarBytes = base64Decode(avatarBase64);
      }
      _notifyTournament = prefs.getBool(_notifyTournamentPrefsKey) ?? true;
      _notifyClub = prefs.getBool(_notifyClubPrefsKey) ?? true;
      _notifyCoach = prefs.getBool(_notifyCoachPrefsKey) ?? false;
    });
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileAvatarPrefsKey, base64Encode(bytes));
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _removeProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileAvatarPrefsKey);
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

    final result = await showDialog<({bool tournament, bool club, bool coach})>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
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
                    title: '라운드 코치 알림',
                    subtitle: '답변·추천 업데이트',
                    value: coach,
                    onChanged: (value) => setDialogState(() => coach = value),
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
                  ).pop((tournament: tournament, club: club, coach: coach)),
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
    if (!mounted) return;
    setState(() {
      _notifyTournament = result.tournament;
      _notifyClub = result.club;
      _notifyCoach = result.coach;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final sports = ref.watch(userSportsProvider);
    final tennisOrgs = ref.watch(userTennisOrgsProvider);

    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          ProfileHeroSliver(
            initial: initial,
            email: email,
            sports: sports,
            tennisOrgs: tennisOrgs,
            avatarBytes: _avatarBytes,
            onAvatarTap: _showProfilePhotoSheet,
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
                AppearanceSection(),
                const SizedBox(height: AppSpacing.xl),
                AccountSection(
                  ref: ref,
                  tournamentNotificationsEnabled: _notifyTournament,
                  clubNotificationsEnabled: _notifyClub,
                  coachNotificationsEnabled: _notifyCoach,
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
