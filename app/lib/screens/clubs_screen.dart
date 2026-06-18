import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/matchup_logo.dart';
import 'clubs/club_create_screen.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  // 내 클럽 탭
  List<Club>? _myClubs;
  bool _loadingMy = false;

  // 클럽 찾기 탭
  final String _q = '';
  List<Club>? _clubs;
  bool _loading = false;
  String? _searchError;
  _ClubSearchFilters _clubFilters = const _ClubSearchFilters();
  late Set<String> _clubInterests;

  @override
  void initState() {
    super.initState();
    _clubInterests = {ref.read(activeSportProvider) ?? 'futsal'};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
    });
  }

  Future<void> _loadMyClubs() async {
    setState(() => _loadingMy = true);
    try {
      if (AppConfig.userDesignPreview) {
        if (mounted) setState(() => _myClubs = _previewManagedClubs);
        return;
      }
      final list = await ref.read(apiProvider).myClubs();
      if (mounted) setState(() => _myClubs = list);
    } catch (_) {
      if (mounted) setState(() => _myClubs = []);
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _searchError = null;
    });
    try {
      if (AppConfig.userDesignPreview) {
        if (mounted) setState(() => _clubs = _previewSearchClubs);
        return;
      }
      final api = ref.read(apiProvider);
      final sports = _clubInterests.isEmpty
          ? const <String>['tennis', 'futsal']
          : _clubInterests.toList();
      final results = await Future.wait(
        sports.map(
          (sport) => api.searchClubs(
            sport: sport,
            region: _clubFilters.region,
            q: _q,
          ),
        ),
      );
      final seen = <String>{};
      final list = [
        for (final clubs in results)
          for (final club in clubs)
            if (seen.add(club.id)) club,
      ];
      if (mounted) setState(() => _clubs = list);
    } catch (_) {
      if (mounted) setState(() => _searchError = '클럽 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClubCreateScreen()),
    );
    if (result == true) {
      _loadMyClubs();
      _load();
    }
  }

  Future<void> _openClubFilterSheet() async {
    final cs = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<_ClubFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClubFilterSheet(
        initialFilters: _clubFilters,
        initialInterests: _clubInterests,
        title: '클럽 찾기 조건',
        icon: Icons.tune_rounded,
        accentColor: cs.primaryContainer,
        onAccentColor: cs.onPrimaryContainer,
      ),
    );
    if (result != null) {
      setState(() {
        _clubFilters = result.filters;
        _clubInterests = result.interests;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveClubs = _clubs ?? _previewSearchClubs;
    final visibleClubs = effectiveClubs
        .where((club) => _clubInterests.contains(club.sport))
        .where((club) => _matchesClubFilters(club, _clubFilters))
        .toList();
    final newClubs = _newPreviewClubs(visibleClubs);
    final recommendedClubs = _recommendedPreviewClubs(visibleClubs);
    final joinedClubs = (_myClubs ?? _previewManagedClubs)
        .where((club) => club.isMember)
        .toList();
    final managedClubs = joinedClubs.where((club) => club.isManager).toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const BrandedAppBarTitle(title: '클럽'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('클럽 만들기'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              112,
            ),
            sliver: SliverList.list(
              children: [
                _SimplePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SimpleSectionHeader(
                        title: '내 주변에 새로 생겼어요',
                        action: '더보기',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_loading || _loadingMy)
                        const LinearProgressIndicator(),
                      if (_searchError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _searchError!,
                          style: TextStyle(color: cs.error),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      _SimpleClubGrid(clubs: newClubs),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SimpleActionCard(
                  icon: Icons.location_on_rounded,
                  title: '맞춤 조건 설정',
                  subtitle: [
                    _selectedSportLabel(_clubInterests),
                    ..._clubFilters.labels,
                  ].join(' · '),
                  action: '설정',
                  color: const Color(0xFFEAF7F1),
                  onTap: _openClubFilterSheet,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (managedClubs.isNotEmpty) ...[
                  _SimpleActionCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: '팀원모집',
                    subtitle: '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                    color: const Color(0xFFEAF7F1),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '가입한 클럽',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Text(
                      '가입한 클럽 공개',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Switch(value: true, onChanged: (_) {}),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SimpleClubTile(
                    club: joinedClubs.isEmpty ? null : joinedClubs.first),
                const SizedBox(height: AppSpacing.xl),
                _SimpleSectionHeader(
                  title: '맞춤추천',
                  subtitle: _clubFilters.hasActive
                      ? [
                          _selectedSportLabel(_clubInterests),
                          ..._clubFilters.labels,
                        ].join(' · ')
                      : '${_selectedSportLabel(_clubInterests)} 기준',
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final club in recommendedClubs.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _SimpleClubTile(club: club),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesClubFilters(Club club, _ClubSearchFilters filters) {
    if (filters.region != null && club.region != filters.region) return false;
    if (filters.gender != null &&
        club.genderPreference != null &&
        club.genderPreference != filters.gender) {
      return false;
    }
    if (filters.days.isNotEmpty &&
        club.meetingDays.isNotEmpty &&
        club.meetingDays.every((day) => !filters.days.contains(day))) {
      return false;
    }
    if (club.monthlyFee != null &&
        (club.monthlyFee! < filters.feeRange.start ||
            club.monthlyFee! > filters.feeRange.end)) {
      return false;
    }
    return true;
  }

  String _selectedSportLabel(Set<String> interests) {
    if (interests.length == 1) {
      return sportLabelFromString(interests.first);
    }
    return '테니스 · 풋살';
  }

  List<Club> _newPreviewClubs(List<Club> source) {
    final now = DateTime.now();
    final recent = source.where((club) {
      final createdAt = club.createdAt;
      if (createdAt == null) return false;
      return now.difference(createdAt).inDays <= 7;
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return (recent.isEmpty ? source : recent).take(4).toList();
  }

  List<Club> _recommendedPreviewClubs(List<Club> source) {
    final scored = [
      for (final club in source)
        (
          club: club,
          score: (_clubFilters.region != null &&
                      club.region == _clubFilters.region
                  ? 4
                  : 0) +
              (_clubFilters.days.isNotEmpty &&
                      club.meetingDays.any(_clubFilters.days.contains)
                  ? 2
                  : 0) +
              club.memberCount,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((item) => item.club).toList();
  }
}

final _previewManagedClubs = [
  Club(
    id: 'preview-managed-futsal',
    sport: 'futsal',
    name: '광주 위너스 풋살클럽',
    region: '광주',
    address: '광주 북구 풋살파크',
    description: '주말 저녁 풋살 멤버를 모집하는 클럽',
    memberCount: 18,
    myRole: 'owner',
  ),
  Club(
    id: 'preview-managed-tennis',
    sport: 'tennis',
    name: '올라운드 테니스 크루',
    region: '광주',
    address: '염주실내테니스장',
    description: '초보부터 함께 치는 테니스 모임',
    memberCount: 24,
    myRole: 'manager',
  ),
];

final _previewSearchClubs = [
  Club(
    id: 'preview-new-futsal-1',
    sport: 'futsal',
    name: '리얼 FS 신규회원 모집중',
    region: '광주',
    address: '광주 북구 풋살파크',
    description: '평일 저녁과 주말에 함께 뛰는 풋살 클럽',
    memberCount: 78,
    meetingDays: const ['화', '목', '토'],
    monthlyFee: 30000,
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  Club(
    id: 'preview-new-tennis-1',
    sport: 'tennis',
    name: '올라운드 테니스 크루',
    region: '광주',
    address: '염주실내테니스장',
    description: '초보부터 랠리까지 함께 치는 테니스 모임',
    memberCount: 24,
    meetingDays: const ['수', '토'],
    monthlyFee: 20000,
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  Club(
    id: 'preview-new-futsal-2',
    sport: 'futsal',
    name: '광주 위너스 풋살클럽',
    region: '광주',
    address: '수완 풋살파크',
    description: '초급자도 참여 가능한 주말 풋살 클럽',
    memberCount: 32,
    meetingDays: const ['일'],
    monthlyFee: 10000,
    genderPreference: '남성',
    createdAt: DateTime.now().subtract(const Duration(days: 5)),
  ),
  Club(
    id: 'preview-new-tennis-2',
    sport: 'tennis',
    name: '광주 랠리메이트',
    region: '광주',
    address: '상무 테니스코트',
    description: '퇴근 후 가볍게 치는 직장인 테니스 클럽',
    memberCount: 41,
    meetingDays: const ['월', '목'],
    monthlyFee: 40000,
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 6)),
  ),
  Club(
    id: 'preview-rec-futsal-1',
    sport: 'futsal',
    name: '첨단 풋살 러닝메이트',
    region: '광주',
    address: '첨단 풋살센터',
    description: '입문자와 초급자가 편하게 참여하는 모임',
    memberCount: 18,
    meetingDays: const ['금'],
    monthlyFee: 0,
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 14)),
  ),
  Club(
    id: 'preview-rec-tennis-1',
    sport: 'tennis',
    name: '주말 테니스 친구들',
    region: '광주',
    address: '광주 월드컵 테니스장',
    description: '주말 오전 중심의 테니스 동호회',
    memberCount: 56,
    meetingDays: const ['토', '일'],
    monthlyFee: 50000,
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 21)),
  ),
];

class _SimpleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? action;

  const _SimpleSectionHeader({
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        if (action != null)
          Text(
            action!,
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _SimplePanel extends StatelessWidget {
  final Widget child;

  const _SimplePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SimpleClubGrid extends StatelessWidget {
  final List<Club> clubs;

  const _SimpleClubGrid({required this.clubs});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final club in clubs.take(4))
          SizedBox(
            width: 180,
            child: _SimpleClubMiniTile(club: club),
          ),
      ],
    );
  }
}

class _SimpleClubMiniTile extends StatelessWidget {
  final Club club;

  const _SimpleClubMiniTile({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        _SimpleClubAvatar(club: club, size: 52),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimpleActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final Color color;
  final VoidCallback? onTap;

  const _SimpleActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary),
                ),
                child: Text(
                  action!,
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SimpleClubTile extends StatelessWidget {
  final Club? club;

  const _SimpleClubTile({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final item = club;

    if (item == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          '관심 있는 클럽을 찾아 가입해보세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SimpleClubAvatar(club: item, size: 72),
              if (item.createdAt != null)
                Positioned(
                  left: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B4F),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      'N',
                      style: tt.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description ?? '새로운 클럽 일정을 확인해보세요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '${sportLabelFromString(item.sport)} · ${item.region ?? '지역 미정'} · 멤버 ${item.memberCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleClubAvatar extends StatelessWidget {
  final Club club;
  final double size;

  const _SimpleClubAvatar({
    required this.club,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _clubLogoSpec(club);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        spec.icon,
        color: spec.foreground,
        size: size * 0.48,
      ),
    );
  }

  _ClubLogoSpec _clubLogoSpec(Club club) {
    final name = club.name;
    if (name.contains('리얼')) {
      return const _ClubLogoSpec(
        icon: Icons.shield_rounded,
        background: Color(0xFFE8F2FF),
        foreground: Color(0xFF2563EB),
      );
    }
    if (name.contains('올라운드')) {
      return const _ClubLogoSpec(
        icon: Icons.all_inclusive_rounded,
        background: Color(0xFFEAF7F1),
        foreground: Color(0xFF059669),
      );
    }
    if (name.contains('위너스')) {
      return const _ClubLogoSpec(
        icon: Icons.emoji_events_rounded,
        background: Color(0xFFFFF4D6),
        foreground: Color(0xFFF59E0B),
      );
    }
    if (name.contains('랠리')) {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    if (name.contains('첨단')) {
      return const _ClubLogoSpec(
        icon: Icons.bolt_rounded,
        background: Color(0xFFEDE9FE),
        foreground: Color(0xFF7C3AED),
      );
    }
    if (name.contains('주말')) {
      return const _ClubLogoSpec(
        icon: Icons.wb_sunny_rounded,
        background: Color(0xFFFFF7ED),
        foreground: Color(0xFFEA580C),
      );
    }
    if (club.sport == 'tennis') {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    return const _ClubLogoSpec(
      icon: Icons.sports_soccer_rounded,
      background: Color(0xFFE8F6D6),
      foreground: Color(0xFF7DCD18),
    );
  }
}

class _ClubLogoSpec {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _ClubLogoSpec({
    required this.icon,
    required this.background,
    required this.foreground,
  });
}

class _TeamRecruitingEntryCard extends StatelessWidget {
  final List<Club> managedClubs;

  const _TeamRecruitingEntryCard({required this.managedClubs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showRecruitingSheet(context),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7F1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBFE8D2)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF16A34A),
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '팀원모집',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecruitingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final tt = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '팀원모집 관리',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '클럽장 또는 운영진 권한이 있는 클럽만 표시됩니다.',
                  style: tt.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final club in managedClubs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _ClubSportThumbnail(
                      sport: club.sport,
                      accentColor: club.sport == 'tennis'
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.secondary,
                      logoUrl: club.logoUrl,
                    ),
                    title: Text(
                      club.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${sportLabelFromString(club.sport)} · ${club.isOwner ? '클럽장' : '운영진'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${club.name} 팀원모집 작성 화면은 준비 중입니다.'),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClubSearchFilters {
  final String? region;
  final String? gender;
  final Set<String> days;
  final RangeValues feeRange;

  const _ClubSearchFilters({
    this.region,
    this.gender,
    this.days = const {},
    this.feeRange = const RangeValues(0, 100000),
  });

  bool get hasActive =>
      region != null ||
      gender != null ||
      days.isNotEmpty ||
      feeRange.start > 0 ||
      feeRange.end < 100000;

  List<String> get labels => [
        if (region != null) region!,
        if (gender != null) gender!,
        for (final day in days) day,
        if (feeRange.start > 0 || feeRange.end < 100000)
          '${_formatFee(feeRange.start)}~${_formatFee(feeRange.end)}',
      ];

  _ClubSearchFilters copyWith({
    String? region,
    bool clearRegion = false,
    String? gender,
    bool clearGender = false,
    Set<String>? days,
    RangeValues? feeRange,
  }) {
    return _ClubSearchFilters(
      region: clearRegion ? null : (region ?? this.region),
      gender: clearGender ? null : (gender ?? this.gender),
      days: days ?? this.days,
      feeRange: feeRange ?? this.feeRange,
    );
  }

  _ClubSearchFilters cleared() => const _ClubSearchFilters();
}

class _ClubFilterResult {
  final _ClubSearchFilters filters;
  final Set<String> interests;

  const _ClubFilterResult({
    required this.filters,
    required this.interests,
  });
}

String _formatFee(double value) {
  final amount = value.round();
  if (amount == 0) return '0원';
  if (amount >= 100000) return '10만원+';
  if (amount % 10000 == 0) return '${amount ~/ 10000}만원';
  return '${amount ~/ 1000}천원';
}

// ─── 클럽 찾기 탭 ────────────────────────────────────────────────────────────

// 클럽 찾기 탭 구조를 되돌릴 때 참고할 수 있도록 남겨둔 기존 컴포넌트.
// ignore: unused_element
class _SearchTab extends StatelessWidget {
  final String q;
  final Set<String> interests;
  final List<Club>? myClubs;
  final bool loadingMy;
  final List<Club>? clubs;
  final bool loading;
  final String? error;
  final Set<String> favoriteIds;
  final _ClubSearchFilters filters;
  final ValueChanged<Set<String>> onInterestsChanged;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_ClubSearchFilters> onFiltersChanged;
  final VoidCallback onSearch;
  final VoidCallback onJoined;

  const _SearchTab({
    required this.q,
    required this.interests,
    required this.myClubs,
    required this.loadingMy,
    required this.clubs,
    required this.loading,
    // ignore: unused_element_parameter
    this.error,
    required this.favoriteIds,
    required this.filters,
    required this.onInterestsChanged,
    required this.onQueryChanged,
    required this.onFiltersChanged,
    required this.onSearch,
    required this.onJoined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLocalPreview =
        Uri.base.host == '127.0.0.1' || Uri.base.host == 'localhost';
    final effectiveClubs = clubs ??
        (AppConfig.userDesignPreview || isLocalPreview
            ? _previewSearchClubs
            : null);
    final visibleClubs = effectiveClubs
        ?.where((club) => interests.contains(club.sport))
        .where((club) => _matchesClientFilters(club, filters))
        .toList();
    final newClubs = _newClubs(visibleClubs ?? const []);
    final recommendedClubs = _recommendedClubs(visibleClubs ?? const []);
    final joinedClubs =
        (myClubs ?? const <Club>[]).where((club) => club.isMember).toList();
    final managedClubs = joinedClubs.where((club) => club.isManager).toList();

    return Column(
      children: [
        Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              _ClubFindControlCard(
                filters: filters,
                interests: interests,
                onFilterTap: () => _openFilterSheet(context),
                onInterestTap: () => _openInterestSheet(context),
              ),
              if (filters.hasActive) ...[
                const SizedBox(height: AppSpacing.sm),
                _ActiveFilterChips(
                  filters: filters,
                  onClear: () => onFiltersChanged(filters.cleared()),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                decoration: InputDecoration(
                  hintText: '클럽명·설명 검색',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: onQueryChanged,
                onSubmitted: (_) => onSearch(),
              ),
            ],
          ),
        ),
        if (loading) LinearProgressIndicator(color: cs.primary),
        Expanded(
          child: error != null
              ? AppEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: error!,
                  description: '네트워크 연결을 확인하고 다시 시도해 주세요.',
                  actionLabel: '다시 시도',
                  onAction: onSearch,
                )
              : effectiveClubs == null
                  ? const SizedBox.shrink()
                  : visibleClubs!.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.groups_rounded,
                          title: '등록된 클럽이 없습니다',
                          description: '다른 검색어나 필터로 시도해 보세요.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.lg,
                          ),
                          children: [
                            if (newClubs.isNotEmpty) ...[
                              _ClubSectionHeader(
                                title: '내 주변에 새로 생겼어요',
                                actionLabel: '더보기',
                                onAction: onSearch,
                              ),
                              _NewClubGrid(
                                clubs: newClubs,
                                favoriteIds: favoriteIds,
                                onJoined: onJoined,
                              ),
                              const SizedBox(height: AppSpacing.xl),
                            ],
                            if (managedClubs.isNotEmpty) ...[
                              _TeamRecruitingEntryCard(
                                managedClubs: managedClubs,
                              ),
                              const SizedBox(height: AppSpacing.xl),
                            ],
                            _JoinedClubSection(
                              clubs: joinedClubs,
                              loading: loadingMy,
                              favoriteIds: favoriteIds,
                              onJoined: onJoined,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _InterestSettingsCard(
                              interests: interests,
                              onTap: () => _openInterestSheet(context),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            if (recommendedClubs.isNotEmpty) ...[
                              _ClubSectionHeader(
                                title: '맞춤추천',
                                subtitle: filters.hasActive
                                    ? filters.labels.join(' · ')
                                    : '내 관심 종목 기준',
                              ),
                              for (final club in recommendedClubs.take(3))
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: _ClubCard(
                                    club: club,
                                    showRole: false,
                                    isFavorite: favoriteIds.contains(club.id),
                                    onChanged: onJoined,
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            _ClubSectionHeader(
                              title: '전체 클럽',
                              subtitle: '${visibleClubs.length}개',
                            ),
                            for (final club in visibleClubs)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: _ClubCard(
                                  club: club,
                                  showRole: false,
                                  isFavorite: favoriteIds.contains(club.id),
                                  onChanged: onJoined,
                                ),
                              ),
                          ],
                        ),
        ),
      ],
    );
  }

  bool _matchesClientFilters(Club club, _ClubSearchFilters filters) {
    if (filters.region != null && club.region != filters.region) return false;
    if (filters.gender != null &&
        club.genderPreference != null &&
        club.genderPreference != filters.gender) {
      return false;
    }
    if (filters.days.isNotEmpty &&
        club.meetingDays.isNotEmpty &&
        club.meetingDays.every((day) => !filters.days.contains(day))) {
      return false;
    }
    if (club.monthlyFee != null &&
        (club.monthlyFee! < filters.feeRange.start ||
            club.monthlyFee! > filters.feeRange.end)) {
      return false;
    }
    return true;
  }

  List<Club> _newClubs(List<Club> source) {
    final now = DateTime.now();
    final recent = source.where((club) {
      final createdAt = club.createdAt;
      if (createdAt == null) return false;
      return now.difference(createdAt).inDays <= 7;
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    if (recent.isNotEmpty) return recent.take(4).toList();
    return source.take(4).toList();
  }

  List<Club> _recommendedClubs(List<Club> source) {
    final scored = [
      for (final club in source)
        (
          club: club,
          score: (filters.region != null && club.region == filters.region
                  ? 4
                  : 0) +
              (filters.gender != null && club.genderPreference == filters.gender
                  ? 2
                  : 0) +
              (filters.days.isNotEmpty &&
                      club.meetingDays.any(filters.days.contains)
                  ? 2
                  : 0) +
              (club.monthlyFee != null &&
                      club.monthlyFee! >= filters.feeRange.start &&
                      club.monthlyFee! <= filters.feeRange.end
                  ? 1
                  : 0) +
              club.memberCount,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((item) => item.club).toList();
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<_ClubFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClubFilterSheet(
        initialFilters: filters,
        initialInterests: interests,
        title: '클럽 찾기 조건',
        icon: Icons.tune_rounded,
        accentColor: cs.primaryContainer,
        onAccentColor: cs.onPrimaryContainer,
      ),
    );
    if (result != null) {
      onFiltersChanged(result.filters);
      onInterestsChanged(result.interests);
    }
  }

  Future<void> _openInterestSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _InterestSheet(initialInterests: interests),
    );
    if (result != null && result.isNotEmpty) onInterestsChanged(result);
  }
}

class _ClubFindControlCard extends StatelessWidget {
  final _ClubSearchFilters filters;
  final Set<String> interests;
  final VoidCallback onFilterTap;
  final VoidCallback onInterestTap;

  const _ClubFindControlCard({
    required this.filters,
    required this.interests,
    required this.onFilterTap,
    required this.onInterestTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final interestLabel = interests.map(sportLabelFromString).join(' · ');

    return AppCard(
      variant: AppCardVariant.filled,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '관심사 설정하기',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      interestLabel.isEmpty ? '테니스 · 풋살' : interestLabel,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onInterestTap,
                child: const Text('설정'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: onFilterTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      filters.hasActive
                          ? filters.labels.join(' · ')
                          : '지역 · 성별 · 모임요일 · 월회비',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelLarge?.copyWith(
                        color: filters.hasActive
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
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
    );
  }
}

class _InterestSettingsCard extends StatelessWidget {
  final Set<String> interests;
  final VoidCallback onTap;

  const _InterestSettingsCard({
    required this.interests,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: Color(0xFF2F73F6),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '관심사 설정하기',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '선택한 종목의 클럽만 볼 수 있어요.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinedClubSection extends StatelessWidget {
  final List<Club> clubs;
  final bool loading;
  final Set<String> favoriteIds;
  final VoidCallback onJoined;

  const _JoinedClubSection({
    required this.clubs,
    required this.loading,
    required this.favoriteIds,
    required this.onJoined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '가입한 클럽',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '가입한 클럽 공개',
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (loading && clubs.isEmpty)
          const LinearProgressIndicator()
        else if (clubs.isEmpty)
          AppCard(
            variant: AppCardVariant.outlined,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '관심 있는 클럽을 찾아 가입해보세요.',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _ClubCard(
            club: clubs.first,
            showRole: true,
            isFavorite: favoriteIds.contains(clubs.first.id),
            onChanged: onJoined,
          ),
      ],
    );
  }
}

class _InterestSheet extends StatefulWidget {
  final Set<String> initialInterests;

  const _InterestSheet({required this.initialInterests});

  @override
  State<_InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends State<_InterestSheet> {
  late final Set<String> _selected = {...widget.initialInterests};

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '관심사 선택',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SportInterestChip(
                  sport: 'tennis',
                  selected: _selected.contains('tennis'),
                  onTap: _toggleSport,
                ),
                _SportInterestChip(
                  sport: 'futsal',
                  selected: _selected.contains('futsal'),
                  onTap: _toggleSport,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('적용하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSport(String sport) {
    setState(() {
      if (!_selected.add(sport)) _selected.remove(sport);
    });
  }
}

class _SportInterestChip extends StatelessWidget {
  final String sport;
  final bool selected;
  final ValueChanged<String> onTap;

  const _SportInterestChip({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';
    final cs = Theme.of(context).colorScheme;

    return FilterChip(
      avatar: Icon(
        isTennis ? Icons.sports_tennis_rounded : Icons.sports_soccer_rounded,
        size: 18,
      ),
      showCheckmark: true,
      checkmarkColor: cs.primary,
      selectedColor: cs.primaryContainer,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
      ),
      label: Text(sportLabelFromString(sport)),
      labelStyle: TextStyle(
        color: selected ? cs.primary : cs.onSurface,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
      ),
      selected: selected,
      onSelected: (_) => onTap(sport),
    );
  }
}

class _ClubSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ClubSectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _NewClubGrid extends StatelessWidget {
  final List<Club> clubs;
  final Set<String> favoriteIds;
  final VoidCallback onJoined;

  const _NewClubGrid({
    required this.clubs,
    required this.favoriteIds,
    required this.onJoined,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final club in clubs.take(4))
              SizedBox(
                width: width,
                child: _CompactClubCard(
                  club: club,
                  isFavorite: favoriteIds.contains(club.id),
                  onChanged: onJoined,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompactClubCard extends ConsumerWidget {
  final Club club;
  final bool isFavorite;
  final VoidCallback onChanged;

  const _CompactClubCard({
    required this.club,
    required this.isFavorite,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
    ].whereType<String>().join(' · ');

    return AppCard(
      onTap: () async {
        await context.push('/clubs/${club.id}', extra: club);
        onChanged();
      },
      child: Row(
        children: [
          _ClubSportThumbnail(
            sport: club.sport,
            accentColor: club.sport == 'tennis' ? cs.tertiary : cs.secondary,
            logoUrl: club.logoUrl,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        club.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (club.createdAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B4F),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'NEW',
                          style: tt.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final _ClubSearchFilters filters;
  final VoidCallback onClear;

  const _ActiveFilterChips({
    required this.filters,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in filters.labels)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.primaryContainer,
                      labelStyle: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: onClear,
          child: const Text('초기화'),
        ),
      ],
    );
  }
}

class _ClubFilterSheet extends StatefulWidget {
  final _ClubSearchFilters initialFilters;
  final Set<String> initialInterests;
  final String title;
  final IconData icon;
  final Color accentColor;
  final Color onAccentColor;

  const _ClubFilterSheet({
    required this.initialFilters,
    required this.initialInterests,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onAccentColor,
  });

  @override
  State<_ClubFilterSheet> createState() => _ClubFilterSheetState();
}

class _ClubFilterSheetState extends State<_ClubFilterSheet> {
  static const _regions = ['서울', '경기', '인천', '광주', '부산', '대구', '대전'];
  static const _genders = ['여성', '남성', '혼성'];
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  late _ClubSearchFilters _filters = widget.initialFilters;
  late Set<String> _selectedInterests = widget.initialInterests.isEmpty
      ? const {'tennis', 'futsal'}
      : {...widget.initialInterests};

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.onAccentColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.title,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FilterSection(
              title: '종목',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SportInterestChip(
                      sport: 'tennis',
                      selected: _selectedInterests.contains('tennis'),
                      onTap: _selectSport,
                    ),
                    _SportInterestChip(
                      sport: 'futsal',
                      selected: _selectedInterests.contains('futsal'),
                      onTap: _selectSport,
                    ),
                  ],
                ),
              ],
            ),
            _FilterSection(
              title: '지역',
              children: [
                _FilterChipWrap(
                  values: _regions,
                  selected: {_filters.region}.whereType<String>().toSet(),
                  onSelected: (value) => setState(() {
                    _filters = _filters.region == value
                        ? _filters.copyWith(clearRegion: true)
                        : _filters.copyWith(region: value);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title: '성별',
              children: [
                _FilterChipWrap(
                  values: _genders,
                  selected: {_filters.gender}.whereType<String>().toSet(),
                  onSelected: (value) => setState(() {
                    _filters = _filters.gender == value
                        ? _filters.copyWith(clearGender: true)
                        : _filters.copyWith(gender: value);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title: '모임요일',
              children: [
                _FilterChipWrap(
                  values: _days,
                  selected: _filters.days,
                  onSelected: (value) => setState(() {
                    final next = {..._filters.days};
                    if (!next.add(value)) next.remove(value);
                    _filters = _filters.copyWith(days: next);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title:
                  '월회비 ${_formatFee(_filters.feeRange.start)} ~ ${_formatFee(_filters.feeRange.end)}',
              children: [
                RangeSlider(
                  values: _filters.feeRange,
                  min: 0,
                  max: 100000,
                  divisions: 20,
                  labels: RangeLabels(
                    _formatFee(_filters.feeRange.start),
                    _formatFee(_filters.feeRange.end),
                  ),
                  onChanged: (value) => setState(() {
                    _filters = _filters.copyWith(feeRange: value);
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _filters = _filters.cleared();
                      _selectedInterests = widget.initialInterests.isEmpty
                          ? const {'tennis'}
                          : {...widget.initialInterests};
                    }),
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ClubFilterResult(
                        filters: _filters,
                        interests: _selectedInterests,
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('조건 적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectSport(String sport) {
    setState(() {
      _selectedInterests = {sport};
    });
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FilterSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _FilterChipWrap extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onSelected;

  const _FilterChipWrap({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          FilterChip(
            label: Text(value),
            selected: selected.contains(value),
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

// ─── 클럽 카드 ──────────────────────────────────────────────────────────────

class _ClubCard extends ConsumerWidget {
  final Club club;
  final bool showRole;
  final bool isFavorite;
  final VoidCallback onChanged;

  const _ClubCard({
    required this.club,
    required this.showRole,
    required this.isFavorite,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accentColor = isTennis ? cs.tertiary : cs.secondary;

    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
      if (club.memberCount > 0) '${club.memberCount}명',
    ].whereType<String>().join(' · ');

    return AppCard(
      onTap: () => _showDetail(context, ref),
      variant: AppCardVariant.elevated,
      child: Row(
        children: [
          _ClubSportThumbnail(
            sport: club.sport,
            accentColor: accentColor,
            logoUrl: club.logoUrl,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        club.name,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (showRole && club.myRole != null)
                      _RoleChip(role: club.myRole!),
                    if (showRole && club.isPending)
                      _StatusChip(label: '승인 대기중', color: Colors.orange),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
            iconSize: 20,
            color: isFavorite ? accentColor : cs.onSurfaceVariant,
            tooltip: isFavorite ? '관심 해제' : '관심 저장',
            onPressed: () async {
              if (AppConfig.userDesignPreview) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('디자인 미리보기용 관심 버튼입니다.')),
                );
                return;
              }
              await ref
                  .read(apiProvider)
                  .toggleClubFavorite(club.id, !isFavorite);
              ref.invalidate(clubFavoriteIdsProvider);
              ref.invalidate(myFavoriteClubsProvider);
            },
          ),
          if (club.website != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              iconSize: 20,
              color: cs.onSurfaceVariant,
              onPressed: () => launchUrl(
                Uri.parse(club.website!),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref) async {
    await context.push('/clubs/${club.id}', extra: club);
    onChanged();
  }
}

class _ClubSportThumbnail extends StatelessWidget {
  const _ClubSportThumbnail({
    required this.sport,
    required this.accentColor,
    this.logoUrl,
  });

  final String sport;
  final Color accentColor;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 56,
        height: 56,
        child: logoUrl == null || logoUrl!.isEmpty
            ? Stack(
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
                    size: 24,
                  ),
                ],
              )
            : Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: accentColor.withValues(alpha: 0.16),
                  child: Icon(
                    isTennis
                        ? Icons.sports_tennis_rounded
                        : Icons.sports_soccer_rounded,
                    color: accentColor,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      'owner' => '클럽장',
      'manager' => '운영진',
      _ => '멤버',
    };
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
