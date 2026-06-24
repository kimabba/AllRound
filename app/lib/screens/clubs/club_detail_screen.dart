import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/club_event.dart';
import '../../models/club_post.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';

/// 클럽 상세 전체화면: 소개 / 멤버 / 일정 탭.
class ClubDetailScreen extends ConsumerStatefulWidget {
  final Club club;
  const ClubDetailScreen({super.key, required this.club});

  @override
  ConsumerState<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends ConsumerState<ClubDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _inFlight = false;
  Future<List<ClubMember>>? _membersF;
  Future<List<ClubEvent>>? _eventsF;
  int? _monthlyFee;

  Club get club => widget.club;
  bool get _canManageClub => club.isOwner || club.isManager;

  @override
  void initState() {
    super.initState();
    _monthlyFee = club.monthlyFee;
    _tab = TabController(length: _canManageClub ? 5 : 4, vsync: this);
    if (club.isMember) _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _membersF = ref.read(apiProvider).clubMembers(club.id);
      _eventsF = ref.read(apiProvider).clubEvents(club.id);
    });
  }

  Future<void> _toggleFavorite(bool isFavorite) async {
    if (AppConfig.userDesignPreview) return;
    await ref.read(apiProvider).toggleClubFavorite(club.id, !isFavorite);
    ref.invalidate(clubFavoriteIdsProvider);
    ref.invalidate(myFavoriteClubsProvider);
  }

  Future<void> _join() async {
    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).joinClub(club.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가입 신청이 완료되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('가입 신청 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('클럽 탈퇴'),
        content: Text('${club.name}에서 탈퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).leaveClub(club.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('탈퇴 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isMember = club.isMember;
    final favoriteIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    final isFavorite = favoriteIds.contains(club.id);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(club.name),
        actions: [
          IconButton(
            tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
            onPressed: () => _toggleFavorite(isFavorite),
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(club: club),
          Material(
            color: cs.surface,
            child: TabBar(
              controller: _tab,
              labelStyle: tt.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              tabs: [
                const Tab(text: '소개'),
                const Tab(text: '멤버'),
                const Tab(text: '일정'),
                const Tab(text: '게시판'),
                if (_canManageClub) const Tab(text: '관리'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _IntroTab(
                  club: club,
                  monthlyFee: _monthlyFee,
                  inFlight: _inFlight,
                  onJoin: _join,
                  onLeave: _leave,
                ),
                isMember
                    ? _MembersTab(
                        future: _membersF!,
                        club: club,
                        onChanged: _reload,
                      )
                    : _memberOnlyNotice(cs, tt),
                isMember
                    ? _EventsTab(
                        club: club,
                        future: _eventsF!,
                        canCreateEvent: _canManageClub,
                        onChanged: _reload,
                      )
                    : _memberOnlyNotice(cs, tt),
                isMember ? _PostsTab(club: club) : _memberOnlyNotice(cs, tt),
                if (_canManageClub)
                  _ClubManagementTab(
                    club: club,
                    membersFuture: _membersF!,
                    monthlyFee: _monthlyFee,
                    onMonthlyFeeChanged: (value) {
                      setState(() => _monthlyFee = value);
                    },
                    onChanged: _reload,
                    onDeleted: () => Navigator.pop(context, true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberOnlyNotice(ColorScheme cs, TextTheme tt) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          _EmptyState(
            icon: Icons.lock_outline_rounded,
            title: '가입 후 이용할 수 있어요',
            message: '멤버, 일정, 게시판은 클럽 멤버에게만 공개됩니다.',
          ),
        ],
      );
}

// ─── 헤더 ────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final Club club;
  const _Header({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accent = AppSportColors.forSport(club.sport);
    final description = club.description?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: AppCard(
        variant: AppCardVariant.outlined,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ClubLogo(club: club, size: 80),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _MetaChip(
                            icon: isTennis
                                ? Icons.sports_tennis_rounded
                                : Icons.sports_soccer_rounded,
                            label: sportLabelFromString(club.sport),
                            color: accent,
                          ),
                          if (club.region != null && club.region!.isNotEmpty)
                            _MetaChip(
                              icon: Icons.place_outlined,
                              label: club.region!,
                            ),
                          _MetaChip(
                            icon: Icons.groups_rounded,
                            label: '${club.memberCount}명',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        club.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      if (club.isMember) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _RolePill(club: club),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClubLogo extends StatelessWidget {
  final Club club;
  final double size;
  const _ClubLogo({required this.club, required this.size});

  @override
  Widget build(BuildContext context) {
    final isTennis = club.sport == 'tennis';
    final accent = AppSportColors.forSport(club.sport);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: club.logoUrl == null || club.logoUrl!.isEmpty
          ? Icon(
              isTennis
                  ? Icons.sports_tennis_rounded
                  : Icons.sports_soccer_rounded,
              color: accent,
              size: size * 0.46,
            )
          : Image.network(
              club.logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                isTennis
                    ? Icons.sports_tennis_rounded
                    : Icons.sports_soccer_rounded,
                color: accent,
                size: size * 0.42,
              ),
            ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: (color ?? cs.primary)
            .withValues(alpha: color == null ? 0.08 : 0.14),
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final Club club;
  const _RolePill({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = club.isOwner ? '클럽장' : (club.isManager ? '운영진' : '멤버');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

// ─── 소개 탭 ──────────────────────────────────────────────────────
class _IntroTab extends StatelessWidget {
  final Club club;
  final int? monthlyFee;
  final bool inFlight;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  const _IntroTab({
    required this.club,
    required this.monthlyFee,
    required this.inFlight,
    required this.onJoin,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final description = club.description?.trim();
    final hasContactInfo = [
      club.address,
      club.contact,
      club.website,
    ].any((value) => value != null && value.trim().isNotEmpty);
    final hasActivityInfo = club.meetingDays.isNotEmpty ||
        monthlyFee != null ||
        (club.genderPreference != null && club.genderPreference!.isNotEmpty);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          variant: AppCardVariant.elevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '클럽 소개',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description == null || description.isEmpty
                    ? '아직 소개가 등록되지 않았어요.'
                    : description,
                style: tt.bodyMedium?.copyWith(
                  color: description == null || description.isEmpty
                      ? cs.onSurfaceVariant
                      : cs.onSurface,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (hasActivityInfo) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            variant: AppCardVariant.outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '활동 정보',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (club.meetingDays.isNotEmpty)
                      _InfoChip(
                        icon: Icons.calendar_month_rounded,
                        label: club.meetingDays.join('·'),
                      ),
                    if (club.genderPreference != null &&
                        club.genderPreference!.isNotEmpty)
                      _InfoChip(
                        icon: Icons.wc_rounded,
                        label: clubGenderLabel(club.genderPreference),
                      ),
                    if (monthlyFee != null)
                      _InfoChip(
                        icon: Icons.payments_outlined,
                        label: clubMonthlyFeeLabel(monthlyFee!),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (hasContactInfo) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            variant: AppCardVariant.outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '연락 및 위치',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.md),
                if (club.address != null && club.address!.isNotEmpty)
                  _infoRow(context, Icons.place_outlined, club.address!),
                if (club.contact != null && club.contact!.isNotEmpty)
                  _infoRow(context, Icons.call_outlined, club.contact!),
                if (club.website != null && club.website!.isNotEmpty)
                  _infoRow(
                    context,
                    Icons.link_rounded,
                    club.website!,
                    onTap: () => launchUrl(
                      Uri.parse(club.website!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (!club.isMember)
          FilledButton.icon(
            onPressed: inFlight ? null : onJoin,
            icon: inFlight
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_rounded),
            label: const Text('가입 신청'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          )
        else if (!club.isOwner)
          OutlinedButton.icon(
            onPressed: inFlight ? null : onLeave,
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('탈퇴'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        if (club.isMember)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              club.isOwner
                  ? '클럽장으로 참여 중'
                  : (club.isManager ? '운영진으로 참여 중' : '멤버로 참여 중'),
              textAlign: TextAlign.center,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text,
      {VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: tt.bodyMedium?.copyWith(
                    color: onTap != null ? cs.primary : null,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _RoleLabelChip extends StatelessWidget {
  final String label;
  const _RoleLabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: AppCard(
        variant: AppCardVariant.outlined,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 멤버 탭 ──────────────────────────────────────────────────────
class _MembersTab extends ConsumerWidget {
  final Future<List<ClubMember>> future;
  final Club club;
  final VoidCallback onChanged;
  const _MembersTab({
    required this.future,
    required this.club,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<ClubMember>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const _EmptyState(
            icon: Icons.error_outline_rounded,
            title: '멤버를 불러오지 못했습니다',
            message: '잠시 후 다시 시도해주세요.',
          );
        }
        final members = snap.data ?? const [];
        if (members.isEmpty) {
          return const _EmptyState(
            icon: Icons.group_outlined,
            title: '아직 멤버가 없습니다',
            message: '첫 멤버가 들어오면 여기에 표시됩니다.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final m = members[i];
            final cs = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            final initial = (m.displayName ?? '?').characters.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                variant: AppCardVariant.outlined,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        m.displayName ?? '익명',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (m.role != 'member')
                      _RoleLabelChip(label: m.roleLabel)
                    else if (club.isOwner)
                      IconButton(
                        icon: Icon(
                          Icons.person_remove_rounded,
                          color: cs.error,
                          size: 20,
                        ),
                        tooltip: '강퇴',
                        onPressed: () => _confirmKick(context, ref, m),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmKick(
    BuildContext context,
    WidgetRef ref,
    ClubMember m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('${m.displayName ?? '이 멤버'}를 강퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('강퇴'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiProvider).kickMember(club.id, m.userId);
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.displayName ?? '멤버'}를 강퇴했습니다')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('강퇴 실패: $e')),
        );
      }
    }
  }
}

// ─── 관리 탭 ──────────────────────────────────────────────────────
class _ClubManagementTab extends ConsumerWidget {
  final Club club;
  final Future<List<ClubMember>> membersFuture;
  final int? monthlyFee;
  final ValueChanged<int?> onMonthlyFeeChanged;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;

  const _ClubManagementTab({
    required this.club,
    required this.membersFuture,
    required this.monthlyFee,
    required this.onMonthlyFeeChanged,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          variant: AppCardVariant.elevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('운영 권한',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                club.isOwner
                    ? '클럽장은 멤버 관리, 부운영자 지정, 회비 관리, 클럽 삭제를 할 수 있습니다.'
                    : '부운영자는 일정 등록과 회비 관리를 할 수 있습니다.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _MonthlyFeeManageCard(
          club: club,
          monthlyFee: monthlyFee,
          onChanged: onMonthlyFeeChanged,
        ),
        if (club.isOwner) ...[
          const SizedBox(height: AppSpacing.md),
          _MemberRoleManageCard(
            club: club,
            future: membersFuture,
            onChanged: onChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _DangerClubManageCard(club: club, onDeleted: onDeleted),
        ],
      ],
    );
  }
}

class _MonthlyFeeManageCard extends ConsumerStatefulWidget {
  final Club club;
  final int? monthlyFee;
  final ValueChanged<int?> onChanged;

  const _MonthlyFeeManageCard({
    required this.club,
    required this.monthlyFee,
    required this.onChanged,
  });

  @override
  ConsumerState<_MonthlyFeeManageCard> createState() =>
      _MonthlyFeeManageCardState();
}

class _MonthlyFeeManageCardState extends ConsumerState<_MonthlyFeeManageCard> {
  late final TextEditingController _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.monthlyFee == null ? '' : widget.monthlyFee.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _MonthlyFeeManageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText =
        widget.monthlyFee == null ? '' : widget.monthlyFee.toString();
    if (oldWidget.monthlyFee != widget.monthlyFee &&
        _controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();
    final fee = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && fee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회비는 숫자로 입력해주세요')),
      );
      return;
    }
    if (fee != null && (fee < 0 || fee > 1000000)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회비는 0원 이상 100만원 이하로 입력해주세요')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateClubMonthlyFee(widget.club.id, fee);
      widget.onChanged(fee);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회비 정보를 저장했습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('회비 저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('회비 관리',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '월회비',
              hintText: '예: 40000',
              suffixText: '원',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _MemberRoleManageCard extends ConsumerWidget {
  final Club club;
  final Future<List<ClubMember>> future;
  final VoidCallback onChanged;

  const _MemberRoleManageCard({
    required this.club,
    required this.future,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('멤버 권한 관리',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<ClubMember>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return const Text('멤버를 불러오지 못했습니다.');
              }
              final members = snap.data ?? const [];
              final manageable =
                  members.where((member) => !member.isOwner).toList();
              if (manageable.isEmpty) {
                return const Text('관리할 멤버가 아직 없습니다.');
              }
              return Column(
                children: [
                  for (final member in manageable)
                    _MemberManageRow(
                      club: club,
                      member: member,
                      onChanged: onChanged,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemberManageRow extends ConsumerStatefulWidget {
  final Club club;
  final ClubMember member;
  final VoidCallback onChanged;

  const _MemberManageRow({
    required this.club,
    required this.member,
    required this.onChanged,
  });

  @override
  ConsumerState<_MemberManageRow> createState() => _MemberManageRowState();
}

class _MemberManageRowState extends ConsumerState<_MemberManageRow> {
  bool _busy = false;

  Future<void> _setRole(String role) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setClubMemberRole(
            clubId: widget.club.id,
            targetUserId: widget.member.userId,
            role: role,
          );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(role == 'manager' ? '부운영자로 지정했습니다' : '부운영자를 해제했습니다'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('권한 변경 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _kick() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('${widget.member.displayName ?? '이 멤버'}를 강퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('강퇴'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).kickMember(
            widget.club.id,
            widget.member.userId,
          );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${widget.member.displayName ?? '멤버'}를 강퇴했습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('강퇴 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final member = widget.member;
    final initial = (member.displayName ?? '?').characters.first;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName ?? '익명',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  member.roleLabel,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (member.isManager)
            TextButton(
              onPressed: _busy ? null : () => _setRole('member'),
              child: const Text('해제'),
            )
          else
            TextButton(
              onPressed: _busy ? null : () => _setRole('manager'),
              child: const Text('지정'),
            ),
          IconButton(
            tooltip: '강퇴',
            onPressed: _busy ? null : _kick,
            icon: Icon(Icons.person_remove_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }
}

class _DangerClubManageCard extends ConsumerStatefulWidget {
  final Club club;
  final VoidCallback onDeleted;

  const _DangerClubManageCard({
    required this.club,
    required this.onDeleted,
  });

  @override
  ConsumerState<_DangerClubManageCard> createState() =>
      _DangerClubManageCardState();
}

class _DangerClubManageCardState extends ConsumerState<_DangerClubManageCard> {
  bool _busy = false;

  Future<void> _deleteClub() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('클럽 삭제'),
        content: Text('${widget.club.name} 클럽을 삭제할까요? 삭제하면 목록에서 내려갑니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).deleteClub(widget.club.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('클럽을 삭제했습니다')),
        );
        widget.onDeleted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('클럽 삭제 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('클럽 삭제',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '삭제하면 일반 목록과 검색에서 내려갑니다. 이 작업은 클럽장만 실행할 수 있습니다.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _deleteClub,
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('클럽 삭제'),
          ),
        ],
      ),
    );
  }
}

// ─── 일정 탭 ──────────────────────────────────────────────────────
class _EventsTab extends ConsumerWidget {
  final Club club;
  final Future<List<ClubEvent>> future;
  final bool canCreateEvent;
  final VoidCallback onChanged;
  const _EventsTab({
    required this.club,
    required this.future,
    required this.canCreateEvent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        FutureBuilder<List<ClubEvent>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return const _EmptyState(
                icon: Icons.error_outline_rounded,
                title: '일정을 불러오지 못했습니다',
                message: '잠시 후 다시 시도해주세요.',
              );
            }
            final events = snap.data ?? const [];
            if (events.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  96,
                ),
                child: _EmptyState(
                  icon: Icons.event_available_outlined,
                  title: '다가오는 모임이 없어요',
                  message: canCreateEvent
                      ? '아래 버튼으로 정기 모임이나 번개 모임을 만들어보세요.'
                      : '운영진이 새 일정을 등록하면 여기에 표시됩니다.',
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                88,
              ),
              itemCount: events.length,
              itemBuilder: (context, i) => _EventCard(
                event: events[i],
                onChanged: onChanged,
              ),
            );
          },
        ),
        if (canCreateEvent)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: FloatingActionButton.extended(
              onPressed: () => _openCreate(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('모임 만들기'),
            ),
          ),
      ],
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _EventCreateSheet(club: club),
    );
    if (created == true) onChanged();
  }
}

class _EventCard extends ConsumerStatefulWidget {
  final ClubEvent event;
  final VoidCallback onChanged;
  const _EventCard({required this.event, required this.onChanged});

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  bool _busy = false;

  Future<void> _respond(bool going) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).respondEvent(widget.event.id, going: going);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('응답 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final e = widget.event;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoChip(
              icon: Icons.event_available_rounded,
              label: '${e.goingCount}명 참석',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(e.title,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(_fmtDateTime(e.startsAt),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            if (e.locationText != null && e.locationText!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(e.locationText!,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
            if (e.description != null && e.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(e.description!, style: tt.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : () => _respond(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: e.iAmGoing ? cs.primary : null,
                      foregroundColor: e.iAmGoing ? cs.onPrimary : null,
                    ),
                    child: const Text('참석'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _respond(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          e.myStatus == 'not_going' ? cs.error : null,
                    ),
                    child: const Text('불참'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 모임 생성 시트 ───────────────────────────────────────────────
class _EventCreateSheet extends ConsumerStatefulWidget {
  final Club club;
  const _EventCreateSheet({required this.club});

  @override
  ConsumerState<_EventCreateSheet> createState() => _EventCreateSheetState();
}

class _EventCreateSheetState extends ConsumerState<_EventCreateSheet> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _startsAt;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _startsAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _startsAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 일시를 입력하세요')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).createClubEvent(
            clubId: widget.club.id,
            title: _title.text.trim(),
            description: _desc.text.trim(),
            locationText: _location.text.trim(),
            startsAt: _startsAt!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('생성 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('모임 만들기', style: tt.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '제목 *',
              hintText: '예: 주말 정기 모임',
            ),
            maxLength: 100,
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '장소',
              hintText: '예: ○○구장',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: '설명'),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label:
                Text(_startsAt == null ? '일시 선택 *' : _fmtDateTime(_startsAt!)),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('만들기'),
          ),
        ],
      ),
    );
  }
}

// ─── 게시판 탭 ─────────────────────────────────────────────────
class _PostsTab extends ConsumerStatefulWidget {
  final Club club;
  const _PostsTab({required this.club});

  @override
  ConsumerState<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends ConsumerState<_PostsTab> {
  List<ClubPost>? _posts;
  bool _loading = true;
  String? _activeTag;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await ref.read(apiProvider).clubPosts(
            widget.club.id,
            tag: _activeTag,
          );
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            children: [
              _TagChip(
                label: '전체',
                selected: _activeTag == null,
                onTap: () {
                  _activeTag = null;
                  _load();
                },
              ),
              _TagChip(
                label: '공지',
                selected: _activeTag == 'notice',
                onTap: () {
                  _activeTag = 'notice';
                  _load();
                },
              ),
              _TagChip(
                label: '자유',
                selected: _activeTag == 'free',
                onTap: () {
                  _activeTag = 'free';
                  _load();
                },
              ),
              _TagChip(
                label: '모집',
                selected: _activeTag == 'recruit',
                onTap: () {
                  _activeTag = 'recruit';
                  _load();
                },
              ),
              _TagChip(
                label: '사진',
                selected: _activeTag == 'photo',
                onTap: () {
                  _activeTag = 'photo';
                  _load();
                },
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _posts == null || _posts!.isEmpty
              ? const _EmptyState(
                  icon: Icons.forum_outlined,
                  title: '게시글이 없습니다',
                  message: '클럽 소식이 올라오면 여기에 표시됩니다.',
                )
              : RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _posts!.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _PostRow(post: _posts![i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  final ClubPost post;
  const _PostRow({required this.post});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: post.tag == 'notice'
                            ? cs.errorContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        post.tagLabel,
                        style: tt.labelSmall?.copyWith(
                          color: post.tag == 'notice'
                              ? cs.onErrorContainer
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${post.authorName ?? '익명'} · ${_timeAgo(post.createdAt)}${post.commentCount > 0 ? ' · 댓글 ${post.commentCount}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.image_rounded, size: 18, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.month}/${dt.day}';
  }
}

String _fmtDateTime(DateTime dt) {
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  final w = wd[(dt.weekday - 1) % 7];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.month}월 ${dt.day}일 ($w) $h:$m';
}
