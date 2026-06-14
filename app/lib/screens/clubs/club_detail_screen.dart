import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/club_event.dart';
import '../../models/club_post.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
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

  Club get club => widget.club;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(club.name),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '소개'),
            Tab(text: '멤버'),
            Tab(text: '일정'),
            Tab(text: '게시판'),
          ],
        ),
      ),
      floatingActionButton: (isMember && _tab.index == 2)
          ? null // FAB는 일정 탭 내부에서 노출 (탭 index 추적 복잡 회피)
          : null,
      body: Column(
        children: [
          _Header(club: club),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _IntroTab(
                  club: club,
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
                        onChanged: _reload,
                      )
                    : _memberOnlyNotice(cs, tt),
                isMember
                    ? _PostsTab(club: club)
                    : _memberOnlyNotice(cs, tt),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberOnlyNotice(ColorScheme cs, TextTheme tt) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text('가입 후 이용할 수 있어요',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
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
    final accent = isTennis ? cs.tertiary : cs.secondary;
    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region!,
      '${club.memberCount}명',
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.md),
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: club.logoUrl == null || club.logoUrl!.isEmpty
                ? Icon(
                    isTennis
                        ? Icons.sports_tennis_rounded
                        : Icons.sports_soccer_rounded,
                    color: accent,
                    size: 30,
                  )
                : Image.network(
                    club.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      isTennis
                          ? Icons.sports_tennis_rounded
                          : Icons.sports_soccer_rounded,
                      color: accent,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              meta,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 소개 탭 ──────────────────────────────────────────────────────
class _IntroTab extends StatelessWidget {
  final Club club;
  final bool inFlight;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  const _IntroTab({
    required this.club,
    required this.inFlight,
    required this.onJoin,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        if (club.description != null && club.description!.isNotEmpty) ...[
          Text(club.description!, style: tt.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (club.contact != null)
          _infoRow(context, Icons.call_outlined, club.contact!),
        if (club.address != null)
          _infoRow(context, Icons.place_outlined, club.address!),
        if (club.website != null)
          _infoRow(
            context,
            Icons.link_rounded,
            club.website!,
            onTap: () => launchUrl(
              Uri.parse(club.website!),
              mode: LaunchMode.externalApplication,
            ),
          ),
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
              club.isOwner ? '클럽장' : (club.isManager ? '운영진' : '멤버'),
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
          return const Center(child: Text('멤버를 불러오지 못했습니다.'));
        }
        final members = snap.data ?? const [];
        if (members.isEmpty) {
          return const Center(child: Text('멤버가 없습니다'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: members.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = members[i];
            final cs = Theme.of(context).colorScheme;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  (m.displayName ?? '?').characters.first,
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ),
              title: Text(m.displayName ?? '익명'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.role != 'member')
                    Chip(
                      label: Text(m.roleLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (club.isOwner && m.role == 'member')
                    IconButton(
                      icon: Icon(Icons.person_remove_rounded,
                          color: cs.error, size: 20),
                      tooltip: '강퇴',
                      onPressed: () => _confirmKick(context, ref, m),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmKick(BuildContext context, WidgetRef ref, ClubMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('${m.displayName ?? '이 멤버'}를 강퇴할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
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

// ─── 일정 탭 ──────────────────────────────────────────────────────
class _EventsTab extends ConsumerWidget {
  final Club club;
  final Future<List<ClubEvent>> future;
  final VoidCallback onChanged;
  const _EventsTab({
    required this.club,
    required this.future,
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
              return Center(child: Text('일정을 불러오지 못했습니다.'));
            }
            final events = snap.data ?? const [];
            if (events.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    '다가오는 모임이 없어요.\n아래 버튼으로 모임을 만들어보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 88),
              itemCount: events.length,
              itemBuilder: (context, i) => _EventCard(
                event: events[i],
                onChanged: onChanged,
              ),
            );
          },
        ),
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

    return AppCard(
      variant: AppCardVariant.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              Text('${e.goingCount}명 참석',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
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
      if (mounted) setState(() { _posts = posts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        // 태그 필터 바
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _TagChip(
                  label: '전체',
                  selected: _activeTag == null,
                  onTap: () { _activeTag = null; _load(); }),
              _TagChip(
                  label: '공지',
                  selected: _activeTag == 'notice',
                  onTap: () { _activeTag = 'notice'; _load(); }),
              _TagChip(
                  label: '자유',
                  selected: _activeTag == 'free',
                  onTap: () { _activeTag = 'free'; _load(); }),
              _TagChip(
                  label: '모집',
                  selected: _activeTag == 'recruit',
                  onTap: () { _activeTag = 'recruit'; _load(); }),
              _TagChip(
                  label: '사진',
                  selected: _activeTag == 'photo',
                  onTap: () { _activeTag = 'photo'; _load(); }),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _posts == null || _posts!.isEmpty
              ? Center(
                  child: Text('게시글이 없습니다',
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)))
              : RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _posts!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _PostRow(post: _posts![i]),
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
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
          label: Text(label), selected: selected, onSelected: (_) => onTap()),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: post.tag == 'notice'
                  ? cs.errorContainer
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(post.tagLabel,
                style: tt.labelSmall?.copyWith(
                  color: post.tag == 'notice'
                      ? cs.onErrorContainer
                      : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
      subtitle: Text(
        '${post.authorName ?? '익명'} · ${_timeAgo(post.createdAt)}${post.commentCount > 0 ? ' · 댓글 ${post.commentCount}' : ''}',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: post.imageUrls.isNotEmpty
          ? Icon(Icons.image_rounded, size: 16, color: cs.onSurfaceVariant)
          : null,
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
