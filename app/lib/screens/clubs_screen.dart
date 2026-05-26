import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import 'clubs/club_create_screen.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // 내 클럽 탭
  List<Club>? _myClubs;
  bool _loadingMy = false;

  // 클럽 찾기 탭
  String _q = '';
  List<Club>? _clubs;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (mounted) setState(() {});
  }

  Future<void> _loadMyClubs() async {
    setState(() => _loadingMy = true);
    try {
      final list = await ref.read(apiProvider).myClubs();
      if (mounted) setState(() => _myClubs = list);
    } catch (_) {
      if (mounted) setState(() => _myClubs = []);
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(apiProvider).searchClubs(
            sport: ref.read(activeSportProvider),
            q: _q,
          );
      if (mounted) setState(() => _clubs = list);
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

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _load());

    return Scaffold(
      appBar: AppBar(
        title: const Text('동호회·클럽'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '내 클럽'),
            Tab(text: '클럽 찾기'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('클럽 만들기'),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MyClubsTab(
            clubs: _myClubs,
            loading: _loadingMy,
            onRefresh: _loadMyClubs,
          ),
          _SearchTab(
            q: _q,
            clubs: _clubs,
            loading: _loading,
            onQueryChanged: (v) => _q = v,
            onSearch: _load,
            onJoined: () {
              _loadMyClubs();
              _load();
            },
          ),
        ],
      ),
    );
  }
}

// ─── 내 클럽 탭 ──────────────────────────────────────────────────────────────

class _MyClubsTab extends ConsumerWidget {
  final List<Club>? clubs;
  final bool loading;
  final VoidCallback onRefresh;

  const _MyClubsTab({
    required this.clubs,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading && clubs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (clubs == null || clubs!.isEmpty) {
      return const AppEmptyState(
        icon: Icons.groups_rounded,
        title: '소속 클럽이 없습니다',
        description: '클럽 찾기 탭에서 가입 신청하거나\n클럽 만들기로 새 클럽을 열어보세요.',
      );
    }

    // pending(대기중) 클럽을 맨 위로
    final sorted = [...clubs!]
      ..sort((a, b) {
        if (a.isPending && !b.isPending) return -1;
        if (!a.isPending && b.isPending) return 1;
        return 0;
      });

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        itemCount: sorted.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _ClubCard(
            club: sorted[i],
            showRole: true,
            onChanged: onRefresh,
          ),
        ),
      ),
    );
  }
}

// ─── 클럽 찾기 탭 ────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  final String q;
  final List<Club>? clubs;
  final bool loading;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearch;
  final VoidCallback onJoined;

  const _SearchTab({
    required this.q,
    required this.clubs,
    required this.loading,
    required this.onQueryChanged,
    required this.onSearch,
    required this.onJoined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          color: cs.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: '클럽명·설명 검색',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            ),
            onChanged: onQueryChanged,
            onSubmitted: (_) => onSearch(),
          ),
        ),
        if (loading) LinearProgressIndicator(color: cs.primary),
        Expanded(
          child: clubs == null
              ? const SizedBox.shrink()
              : clubs!.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.groups_rounded,
                      title: '등록된 클럽이 없습니다',
                      description: '다른 검색어나 필터로 시도해 보세요.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.lg,
                      ),
                      itemCount: clubs!.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _ClubCard(
                          club: clubs![i],
                          showRole: false,
                          onChanged: onJoined,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ─── 클럽 카드 ──────────────────────────────────────────────────────────────

class _ClubCard extends ConsumerWidget {
  final Club club;
  final bool showRole;
  final VoidCallback onChanged;

  const _ClubCard({
    required this.club,
    required this.showRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;

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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isTennis
                  ? Icons.sports_tennis_rounded
                  : Icons.sports_soccer_rounded,
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(club.name, style: tt.titleMedium)),
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

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      isScrollControlled: true,
      builder: (_) => _ClubDetailSheet(
        club: club,
        ref: ref,
        onChanged: onChanged,
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
          horizontal: AppSpacing.sm, vertical: 2),
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
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
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

// ─── 클럽 상세 바텀시트 ──────────────────────────────────────────────────────

class _ClubDetailSheet extends ConsumerStatefulWidget {
  final Club club;
  final WidgetRef ref;
  final VoidCallback onChanged;

  const _ClubDetailSheet({
    required this.club,
    required this.ref,
    required this.onChanged,
  });

  @override
  ConsumerState<_ClubDetailSheet> createState() => _ClubDetailSheetState();
}

class _ClubDetailSheetState extends ConsumerState<_ClubDetailSheet> {
  bool _inFlight = false;

  Future<void> _join() async {
    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).joinClub(widget.club.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('가입 신청이 완료되었습니다')));
        Navigator.pop(context);
        widget.onChanged();
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
        content: Text('${widget.club.name}에서 탈퇴할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
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
      await ref.read(apiProvider).leaveClub(widget.club.id);
      if (mounted) {
        Navigator.pop(context);
        widget.onChanged();
      }
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final club = widget.club;
    final isMember = club.isMember;
    final isOwner = club.isOwner;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(club.name, style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              sportLabelFromString(club.sport),
              if (club.region != null) club.region!,
              if (club.memberCount > 0) '${club.memberCount}명',
            ].join(' · '),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (club.contact != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('연락처: ${club.contact!}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (club.address != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('주소: ${club.address!}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (club.description != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(club.description!, style: tt.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!isMember)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _inFlight ? null : _join,
                icon: _inFlight
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_rounded),
                label: const Text('가입 신청'),
              ),
            )
          else if (!isOwner)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _inFlight ? null : _leave,
                icon: const Icon(Icons.exit_to_app_rounded),
                label: const Text('탈퇴'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}
