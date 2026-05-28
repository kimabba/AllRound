import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../state/theme_provider.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';

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

  Future<void> _pickProfilePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
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
                _SheetActionRow(
                  icon: Icons.photo_library_rounded,
                  label: '앨범에서 선택',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickProfilePhoto();
                  },
                ),
                if (_avatarBytes != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _SheetActionRow(
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
                  _NotificationSwitchTile(
                    icon: Icons.emoji_events_outlined,
                    title: '대회 알림',
                    subtitle: 'D-3·신청 마감 알림',
                    value: tournament,
                    onChanged: (value) =>
                        setDialogState(() => tournament = value),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _NotificationSwitchTile(
                    icon: Icons.groups_2_outlined,
                    title: '클럽 알림',
                    subtitle: '내 클럽 공지·업데이트',
                    value: club,
                    onChanged: (value) => setDialogState(() => club = value),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _NotificationSwitchTile(
                    icon: Icons.smart_toy_outlined,
                    title: '코치봇 알림',
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
          _ProfileHeroSliver(
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
                const _MyClubsSection(),
                const SizedBox(height: AppSpacing.xl),
                _SportsSection(sports: sports),
                const SizedBox(height: AppSpacing.xl),
                tennisOrgs.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (orgs) => orgs.isEmpty
                      ? const SizedBox.shrink()
                      : _TennisOrgsSection(orgs: orgs),
                ),
                const SizedBox(height: AppSpacing.xl),
                _AppearanceSection(),
                const SizedBox(height: AppSpacing.xl),
                _AccountSection(
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

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar
// ────────────────────────────────────────────────────────────

class _ProfileHeroSliver extends StatelessWidget {
  final String initial;
  final String email;
  final AsyncValue<List<UserSport>> sports;
  final AsyncValue<List<UserTennisOrg>> tennisOrgs;
  final Uint8List? avatarBytes;
  final VoidCallback onAvatarTap;

  const _ProfileHeroSliver({
    required this.initial,
    required this.email,
    required this.sports,
    required this.tennisOrgs,
    required this.avatarBytes,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      expandedHeight: 306,
      pinned: true,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      title: Text(
        'MY',
        style: tt.titleLarge?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, const Color(0xFF3B5BDB), cs.secondary],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                kToolbarHeight + AppSpacing.md,
                AppSpacing.lg,
                112,
              ),
              child: _ProfileHeaderContent(
                initial: initial,
                email: email,
                sports: sports,
                avatarBytes: avatarBytes,
                onAvatarTap: onAvatarTap,
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: _StatsGrid(sports: sports, tennisOrgs: tennisOrgs),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeaderContent extends StatelessWidget {
  const _ProfileHeaderContent({
    required this.initial,
    required this.email,
    required this.sports,
    required this.avatarBytes,
    required this.onAvatarTap,
  });

  final String initial;
  final String email;
  final AsyncValue<List<UserSport>> sports;
  final Uint8List? avatarBytes;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final primary = sports.maybeWhen(
      data: (items) => items.where((s) => s.isPrimary).firstOrNull,
      orElse: () => null,
    );
    final sportCount = sports.maybeWhen(data: (l) => l.length, orElse: () => 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
                backgroundImage:
                    avatarBytes == null ? null : MemoryImage(avatarBytes!),
                child: avatarBytes == null
                    ? Text(
                        initial,
                        style: tt.headlineMedium?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.onPrimary,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: cs.primary,
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                email.isEmpty ? '사용자' : email,
                style: tt.titleLarge?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _HeroChip(
                    label: primary == null
                        ? '종목 미등록'
                        : sportLabelFromString(primary.sport),
                  ),
                  if (primary != null)
                    _HeroChip(label: gradeLabel(primary.grade)),
                  _HeroChip(label: '$sportCount개 종목'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.onPrimary.withValues(alpha: 0.18),
        borderRadius: AppRadius.pill,
        border: Border.all(color: cs.onPrimary.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.sports, required this.tennisOrgs});

  final AsyncValue<List<UserSport>> sports;
  final AsyncValue<List<UserTennisOrg>> tennisOrgs;

  @override
  Widget build(BuildContext context) {
    final sportCount = sports.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    final orgCount = tennisOrgs.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    final primary = sports.maybeWhen(
      data: (items) => items.where((s) => s.isPrimary).firstOrNull?.sport,
      orElse: () => null,
    );

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.sports_score_rounded,
            value: '$sportCount',
            label: '등록 종목',
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            value: '$orgCount',
            label: '소속 협회',
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: Icons.tune_rounded,
            value: primary == null ? '-' : sportLabelFromString(primary),
            label: '기본 필터',
            color: Theme.of(context).colorScheme.primary,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: (compact ? tt.labelLarge : tt.titleLarge)?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyClubsSection extends ConsumerWidget {
  const _MyClubsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final clubs = ref.watch(myClubsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '내가 등록한 클럽',
          action: _SectionActionButton(
            label: '둘러보기',
            onTap: () => context.go('/clubs'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        clubs.when(
          loading: () =>
              const AppCard(child: Center(child: CircularProgressIndicator())),
          error: (_, __) => AppCard(
            child: Text(
              '등록 클럽을 불러오지 못했습니다.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          data: (items) => items.isEmpty
              ? AppCard(
                  variant: AppCardVariant.elevated,
                  borderRadius: BorderRadius.circular(16),
                  child: _MyClubEmptyContent(cs: cs, tt: tt),
                )
              : Column(
                  children: [
                    for (final club in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          variant: AppCardVariant.elevated,
                          borderRadius: BorderRadius.circular(16),
                          child: Row(
                            children: [
                              _ProfileSportThumbnail(sport: club.sport),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      club.name,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      [
                                        sportLabelFromString(club.sport),
                                        if (club.region != null) club.region!,
                                      ].join(' · '),
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MyClubEmptyContent extends StatelessWidget {
  const _MyClubEmptyContent({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.groups_rounded,
            color: cs.onSecondaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '아직 등록한 클럽이 없습니다',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '마음에 드는 클럽을 찾아 등록하면 이곳에 표시됩니다.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 등록 종목·등급 섹션
// ────────────────────────────────────────────────────────────

class _SportsSection extends StatelessWidget {
  final AsyncValue<List<UserSport>> sports;
  const _SportsSection({required this.sports});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '등록 종목·등급',
          action: _SectionActionButton(
            label: '수정',
            onTap: () => context.push('/onboarding'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        sports.when(
          loading: () => AppCard(
            child: const SizedBox(
              height: 60,
              child: Center(child: LinearProgressIndicator()),
            ),
          ),
          error: (e, _) => AppCard(
            child: Padding(
              padding: AppSpacing.screen,
              child: Text('$e', style: TextStyle(color: cs.error)),
            ),
          ),
          data: (list) => list.isEmpty
              ? AppCard(
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: Text(
                      '아직 등록된 종목이 없습니다.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: list
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _SportCard(sport: s),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _SportCard extends StatelessWidget {
  final UserSport sport;
  const _SportCard({required this.sport});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = sport.sport == 'tennis';
    final accentColor = isTennis ? cs.tertiary : cs.secondary;

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          _ProfileSportThumbnail(sport: sport.sport),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sportLabelFromString(sport.sport),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  gradeLabel(sport.grade),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (sport.isPrimary)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                '활성 종목 (필터 기준)',
                style: tt.labelSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileSportThumbnail extends StatelessWidget {
  const _ProfileSportThumbnail({required this.sport});

  final String sport;

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              isTennis
                  ? 'assets/images/tournaments/tennis-cover.jpg'
                  : 'assets/images/tournaments/futsal-cover.jpg',
              fit: BoxFit.cover,
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
            Icon(
              isTennis
                  ? Icons.sports_tennis_rounded
                  : Icons.sports_soccer_rounded,
              color: Colors.white,
              size: 23,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 테니스 소속 협회 섹션 (multi-org)
// ────────────────────────────────────────────────────────────

class _TennisOrgsSection extends StatelessWidget {
  final List<UserTennisOrg> orgs;
  const _TennisOrgsSection({required this.orgs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '소속 테니스 협회'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: orgs
                .map((org) => _OrgRow(org: org, isLast: org == orgs.last))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _OrgRow extends StatelessWidget {
  final UserTennisOrg org;
  final bool isLast;
  const _OrgRow({required this.org, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = tennisOrgLabel(org.org);
    final shortLabel = tennisOrgShortLabel(org.org);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: Text(
                    shortLabel.length <= 4
                        ? shortLabel
                        : shortLabel.substring(0, 4),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.bodyMedium),
                    if (org.regionCode != null)
                      Text(
                        regionLabel(org.regionCode!),
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (org.isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    '주',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 화면 설정 섹션 (다크모드 토글)
// ────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '화면 설정'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '다크 모드',
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('자동'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('라이트'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('다크'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: cs.primaryContainer,
                  selectedForegroundColor: cs.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 계정 섹션 (알림 + 로그아웃)
// ────────────────────────────────────────────────────────────

class _AccountSection extends StatelessWidget {
  final WidgetRef ref;
  final bool tournamentNotificationsEnabled;
  final bool clubNotificationsEnabled;
  final bool coachNotificationsEnabled;
  final VoidCallback onNotificationTap;

  const _AccountSection({
    required this.ref,
    required this.tournamentNotificationsEnabled,
    required this.clubNotificationsEnabled,
    required this.coachNotificationsEnabled,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeCount = [
      tournamentNotificationsEnabled,
      clubNotificationsEnabled,
      coachNotificationsEnabled,
    ].where((enabled) => enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '계정'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.notifications_outlined,
                label: '알림 설정',
                subtitle: activeCount == 0 ? '모든 알림 꺼짐' : '$activeCount개 알림 켜짐',
                onTap: onNotificationTap,
              ),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              _ActionRow(
                icon: Icons.logout_rounded,
                label: '로그아웃',
                accentColor: cs.error,
                onTap: () async {
                  await ref.read(supabaseProvider).auth.signOut();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? accentColor;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = accentColor ?? cs.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.bodyLarge?.copyWith(color: color)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (accentColor == null)
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotificationSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: value
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accentColor;
  final VoidCallback onTap;

  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = accentColor ?? cs.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: tt.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 공통 헬퍼 위젯
// ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
        if (action != null) ...[const Spacer(), action!],
      ],
    );
  }
}

class _SectionActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SectionActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(label, style: tt.labelMedium?.copyWith(color: cs.primary)),
    );
  }
}
