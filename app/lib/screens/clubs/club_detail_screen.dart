import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/club_event.dart';
import '../../models/club_post.dart';
import '../../models/moderation.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';
import '../../utils/club_image_upload.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/moderation/ugc_moderation_widgets.dart';
import 'club_inquiry_screen.dart';

enum ClubDetailResult { membershipChanged, deleted }

/// 클럽 상세 전체화면: 소개 / 멤버 / 일정 탭.
///
/// [club]이 전달되면 즉시 표시, 없으면 [clubId]로 서버에서 로드.
class ClubDetailScreen extends ConsumerStatefulWidget {
  final Club? club;
  final String? clubId;
  const ClubDetailScreen({super.key, this.club, this.clubId})
      : assert(club != null || clubId != null);

  @override
  ConsumerState<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends ConsumerState<ClubDetailScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tab;
  bool _inFlight = false;
  Future<List<ClubMember>>? _membersF;
  Future<List<ClubEvent>>? _eventsF;
  int? _monthlyFee;
  MyClubJoinRequest? _myJoinRequest;
  bool _joinRequestLoading = false;
  bool _joinRequestLoadFailed = false;
  int _joinRequestLoadId = 0;

  Club? _club;
  bool _loading = false;
  String? _error;

  Club get club => _club!;
  bool get _canManageClub => club.isOwner || club.isManager;

  @override
  void initState() {
    super.initState();
    if (widget.club != null) {
      _club = widget.club;
      _initTab();
      _refreshClub();
    } else {
      _fetchClub();
    }
  }

  void _initTab() {
    _monthlyFee = club.monthlyFee;
    _tab = TabController(length: _canManageClub ? 5 : 4, vsync: this);
    if (AppConfig.userDesignPreview) return;
    if (club.isMember) {
      _reload();
    } else {
      unawaited(_loadMyJoinRequest());
    }
  }

  Future<void> _loadMyJoinRequest() async {
    if (_club == null || club.isMember || !club.isApproved) {
      _joinRequestLoadId += 1;
      if (mounted) {
        setState(() {
          _myJoinRequest = null;
          _joinRequestLoading = false;
          _joinRequestLoadFailed = false;
        });
      }
      return;
    }

    final loadId = ++_joinRequestLoadId;
    setState(() {
      _joinRequestLoading = true;
      _joinRequestLoadFailed = false;
    });
    try {
      final request =
          await ref.read(apiProvider).myPendingClubJoinRequest(club.id);
      if (!mounted || loadId != _joinRequestLoadId) return;
      setState(() {
        _myJoinRequest = request;
        _joinRequestLoading = false;
      });
    } catch (_) {
      if (!mounted || loadId != _joinRequestLoadId) return;
      setState(() {
        _joinRequestLoading = false;
        _joinRequestLoadFailed = true;
      });
    }
  }

  Future<void> _fetchClub() async {
    setState(() => _loading = true);
    try {
      final fetched = await ref.read(apiProvider).getClub(widget.clubId!);
      if (!mounted) return;
      setState(() {
        _club = fetched;
        _loading = false;
      });
      _initTab();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refreshClub() async {
    if (AppConfig.userDesignPreview) return;
    final clubId = _club?.id ?? widget.clubId;
    if (clubId == null) return;
    try {
      final fetched = await ref.read(apiProvider).getClub(clubId);
      if (!mounted) return;
      final nextTabLength = (fetched.isOwner || fetched.isManager) ? 5 : 4;
      setState(() {
        _club = fetched;
        _monthlyFee = fetched.monthlyFee;
        if (fetched.isMember) {
          _joinRequestLoadId += 1;
          _myJoinRequest = null;
          _joinRequestLoading = false;
          _joinRequestLoadFailed = false;
        }
        if (_tab == null || _tab!.length != nextTabLength) {
          final nextIndex =
              ((_tab?.index ?? 0).clamp(0, nextTabLength - 1)).toInt();
          _tab?.dispose();
          _tab = TabController(length: nextTabLength, vsync: this);
          _tab!.index = nextIndex;
        }
      });
      if (fetched.isMember) {
        _reload();
      } else {
        await _loadMyJoinRequest();
      }
    } catch (_) {
      // 기존 화면 데이터가 있으면 그대로 사용한다.
    }
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _membersF = ref.read(apiProvider).clubMembers(club.id);
      _eventsF = ref.read(apiProvider).clubEvents(club.id);
    });
  }

  void _refreshMembershipData() {
    ref.invalidate(myClubsProvider);
    ref.invalidate(myFavoriteClubsProvider);
    unawaited(_refreshClub());
  }

  Future<void> _toggleFavorite(bool isFavorite) async {
    if (AppConfig.userDesignPreview) return;
    await ref.read(apiProvider).toggleClubFavorite(club.id, !isFavorite);
    ref.invalidate(clubFavoriteIdsProvider);
    ref.invalidate(myFavoriteClubsProvider);
  }

  Future<void> _reportClub() async {
    await showUgcReportSheet(
      context: context,
      ref: ref,
      targetType: UgcTargetType.club,
      targetId: club.id,
    );
  }

  Future<void> _blockClubCreator() async {
    final creatorId = club.createdBy;
    if (creatorId == null) return;
    final blocked = await confirmBlockUser(
      context: context,
      ref: ref,
      userId: creatorId,
      displayName: '클럽 개설자',
    );
    if (blocked && mounted) Navigator.pop(context);
  }

  Future<void> _resubmitRejectedClub() async {
    try {
      await ref.read(apiProvider).resubmitClubReview(club.id);
      ref.invalidate(myClubsProvider);
      await _refreshClub();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재심사를 요청했습니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('재심사 요청 실패: $error')),
        );
      }
    }
  }

  Future<void> _deleteRejectedClub() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('반려 클럽 삭제'),
        content: Text('${club.name} 클럽을 삭제할까요? 삭제 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiProvider).deleteClub(club.id);
      ref.invalidate(myClubsProvider);
      if (mounted) Navigator.pop(context, ClubDetailResult.deleted);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('클럽 삭제 실패: $error')),
        );
      }
    }
  }

  Future<void> _join() async {
    final allowed = await ensureUgcPermission(
      context,
      ref,
      UgcActionKind.clubJoin,
    );
    if (!allowed || !mounted) return;
    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).joinClub(club.id);
      await _loadMyJoinRequest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가입 신청이 완료되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ugcActionErrorMessage(e, fallback: '가입 신청을 완료하지 못했습니다.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  Future<void> _cancelJoinRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('가입 신청 취소'),
        content: Text('${club.name} 가입 신청을 취소할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).cancelJoinClub(club.id);
      _joinRequestLoadId += 1;
      if (!mounted) return;
      setState(() {
        _myJoinRequest = null;
        _joinRequestLoading = false;
        _joinRequestLoadFailed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가입 신청을 취소했습니다.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('가입 신청 취소 실패: $error')),
        );
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _inFlight = true);
    try {
      await ref.read(apiProvider).leaveClub(club.id);
      if (mounted) {
        Navigator.pop(context, ClubDetailResult.membershipChanged);
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _club == null) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text(
                '클럽을 불러올 수 없습니다',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: _fetchClub,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    final isMember = club.isMember;
    final favoriteIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    final isFavorite = favoriteIds.contains(club.id);
    final membersFuture = _membersF ?? Future<List<ClubMember>>.value(const []);
    final eventsFuture = _eventsF ?? Future<List<ClubEvent>>.value(const []);
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final canModerateClub =
        club.createdBy != null && club.createdBy != currentUserId;

    return Scaffold(
      key: AllRoundE2EKeys.clubDetailScreen,
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(club.name),
        actions: [
          IconButton(
            key: isFavorite
                ? AllRoundE2EKeys.clubFavoriteSaved
                : AllRoundE2EKeys.clubFavoriteUnsaved,
            tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
            onPressed: () => _toggleFavorite(isFavorite),
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
          ),
          if (canModerateClub)
            PopupMenuButton<String>(
              tooltip: '클럽 더보기',
              onSelected: (value) {
                if (value == 'report') unawaited(_reportClub());
                if (value == 'block') unawaited(_blockClubCreator());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('클럽 신고')),
                PopupMenuItem(value: 'block', child: Text('개설자 차단')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (club.isRejected && club.statusReason != 'deleted_by_owner')
            _RejectedClubBanner(
              reason: club.statusReason,
              onDelete: _deleteRejectedClub,
              onEdit: () => _tab?.animateTo(_tab!.length - 1),
              onResubmit: _resubmitRejectedClub,
            ),
          _Header(club: club),
          Material(
            color: cs.surface,
            child: TabBar(
              controller: _tab!,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              labelStyle: tt.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              tabs: [
                const Tab(key: AllRoundE2EKeys.clubIntroTab, text: '소개'),
                const Tab(key: AllRoundE2EKeys.clubMembersTab, text: '멤버'),
                const Tab(key: AllRoundE2EKeys.clubEventsTab, text: '일정'),
                const Tab(key: AllRoundE2EKeys.clubPostsTab, text: '게시판'),
                if (_canManageClub)
                  const Tab(
                    key: AllRoundE2EKeys.clubManagementTab,
                    text: '관리',
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab!,
              children: [
                _IntroTab(
                  club: club,
                  monthlyFee: _monthlyFee,
                  inFlight: _inFlight,
                  joinRequest: _myJoinRequest,
                  joinRequestLoading: _joinRequestLoading,
                  joinRequestLoadFailed: _joinRequestLoadFailed,
                  onJoin: _join,
                  onCancelJoin: _cancelJoinRequest,
                  onRetryJoinStatus: _loadMyJoinRequest,
                  onLeave: _leave,
                  onInquiry: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClubInquiryConversationScreen(
                        clubId: club.id,
                        clubName: club.name,
                      ),
                    ),
                  ),
                ),
                isMember
                    ? _MembersTab(
                        future: membersFuture,
                        club: club,
                        onChanged: _refreshMembershipData,
                      )
                    : _memberOnlyNotice(cs, tt),
                isMember
                    ? _EventsTab(
                        club: club,
                        future: eventsFuture,
                        membersFuture: membersFuture,
                        canCreateEvent: _canManageClub,
                        onChanged: _reload,
                      )
                    : _memberOnlyNotice(cs, tt),
                isMember ? _PostsTab(club: club) : _memberOnlyNotice(cs, tt),
                if (_canManageClub)
                  _ClubManagementTab(
                    club: club,
                    membersFuture: membersFuture,
                    monthlyFee: _monthlyFee,
                    onMonthlyFeeChanged: (value) {
                      setState(() => _monthlyFee = value);
                    },
                    onChanged: _refreshMembershipData,
                    onDeleted: () => Navigator.pop(
                      context,
                      ClubDetailResult.deleted,
                    ),
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
class _RejectedClubBanner extends StatelessWidget {
  const _RejectedClubBanner({
    required this.reason,
    required this.onDelete,
    required this.onEdit,
    required this.onResubmit,
  });

  final String? reason;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '클럽 승인이 반려되었습니다',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason?.trim().isNotEmpty == true
                ? reason!
                : '관리자가 반려 사유를 등록하지 않았습니다.',
            style: TextStyle(color: cs.onErrorContainer),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('삭제'),
              ),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('수정하기'),
              ),
              FilledButton.icon(
                onPressed: onResubmit,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('재심사 요청'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Club club;
  const _Header({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accent = AppSportColors.forSport(club.sport);

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
      child: Row(
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
  final MyClubJoinRequest? joinRequest;
  final bool joinRequestLoading;
  final bool joinRequestLoadFailed;
  final VoidCallback onJoin;
  final VoidCallback onCancelJoin;
  final VoidCallback onRetryJoinStatus;
  final VoidCallback onLeave;
  final VoidCallback onInquiry;
  const _IntroTab({
    required this.club,
    required this.monthlyFee,
    required this.inFlight,
    required this.joinRequest,
    required this.joinRequestLoading,
    required this.joinRequestLoadFailed,
    required this.onJoin,
    required this.onCancelJoin,
    required this.onRetryJoinStatus,
    required this.onLeave,
    required this.onInquiry,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        _ClubFlatSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '클럽 소개',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
              if (club.introImageUrls.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ClubIntroPhotoStrip(imageUrls: club.introImageUrls),
              ],
            ],
          ),
        ),
        if (hasActivityInfo) ...[
          const SizedBox(height: AppSpacing.md),
          _ClubFlatSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '활동 정보',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
          _ClubFlatSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '연락 및 위치',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
        if (!club.isMember && club.isApproved) ...[
          OutlinedButton.icon(
            onPressed: onInquiry,
            icon: const Icon(Icons.forum_outlined),
            label: const Text('가입 전 1:1 문의'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.control),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (!club.isMember && joinRequestLoading)
          FilledButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: const Text('가입 신청 상태 확인 중'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.control),
            ),
          )
        else if (!club.isMember && joinRequestLoadFailed)
          OutlinedButton.icon(
            onPressed: inFlight ? null : onRetryJoinStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('가입 신청 상태 다시 확인'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.control),
            ),
          )
        else if (!club.isMember && joinRequest?.isPending == true) ...[
          FilledButton.tonalIcon(
            key: AllRoundE2EKeys.clubJoinPendingAction,
            onPressed: inFlight ? null : onCancelJoin,
            icon: inFlight
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.hourglass_top_rounded),
            label: const Text('가입 승인 대기 중 · 취소하기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.control),
            ),
          ),
          if (joinRequest?.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '신청일 ${_formatJoinRequestDate(joinRequest!.createdAt)}',
                textAlign: TextAlign.center,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ] else if (!club.isMember)
          FilledButton.icon(
            key: AllRoundE2EKeys.clubJoinAvailableAction,
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
              minimumSize: const Size.fromHeight(AppSizes.control),
            ),
          )
        else if (!club.isOwner)
          OutlinedButton.icon(
            onPressed: inFlight ? null : onLeave,
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('탈퇴'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              minimumSize: const Size.fromHeight(AppSizes.control),
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

class _ClubFlatSection extends StatelessWidget {
  const _ClubFlatSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: outline),
          bottom: BorderSide(color: outline),
        ),
      ),
      child: child,
    );
  }
}

class _ClubIntroPhotoStrip extends StatelessWidget {
  const _ClubIntroPhotoStrip({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final urls = imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          return Container(
            width: 168,
            height: 132,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Image.network(
              urls[index],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.image_not_supported_outlined,
                color: cs.onSurfaceVariant,
              ),
            ),
          );
        },
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
    return AppEmptyState(
      icon: icon,
      title: title,
      description: message,
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
            title: '가입된 멤버가 없습니다',
            message: '가입 승인이 완료된 멤버가 여기에 표시됩니다.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final m = members[i];
            final cs = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            final displayName = _clubMemberDisplayName(m);
            final initial = displayName.characters.first;
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
                        displayName,
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
        content: Text('${_clubMemberDisplayName(m)}를 강퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
          SnackBar(content: Text('${_clubMemberDisplayName(m)}를 강퇴했습니다')),
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

String _clubMemberDisplayName(ClubMember member) {
  final name = member.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return '멤버 ${_shortUserId(member.userId)}';
}

String _shortUserId(String userId) {
  return userId.length > 8 ? userId.substring(0, 8) : userId;
}

String _formatJoinRequestDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

String? _stringValue(Object? value) => value is String ? value : null;

Map<String, Object?>? _joinRequestUserFrom(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map<String, Object?>(
      (key, entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  if (value is List && value.isNotEmpty) {
    return _joinRequestUserFrom(value.first);
  }
  return null;
}

class _ClubJoinRequest {
  final String id;
  final String userId;
  final String? message;
  final DateTime? createdAt;
  final String? displayName;
  final String? email;

  const _ClubJoinRequest({
    required this.id,
    required this.userId,
    required this.message,
    required this.createdAt,
    required this.displayName,
    required this.email,
  });

  factory _ClubJoinRequest.fromJson(Map<String, dynamic> json) {
    final user = _joinRequestUserFrom(json['users']);
    return _ClubJoinRequest(
      id: _stringValue(json['id']) ?? '',
      userId: _stringValue(json['user_id']) ?? '',
      message: _stringValue(json['message']),
      createdAt: DateTime.tryParse(_stringValue(json['created_at']) ?? ''),
      displayName: _stringValue(user?['name']),
      email: _stringValue(user?['email']),
    );
  }

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final userEmail = email?.trim();
    if (userEmail != null && userEmail.isNotEmpty) return userEmail;
    return '신청자 ${_shortUserId(userId)}';
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
      key: AllRoundE2EKeys.clubManagementContent,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        _ClubFlatSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('운영 권한',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                club.isOwner
                    ? '클럽장은 소개글, 소개 사진, 회비, 멤버 권한, 클럽 삭제를 관리할 수 있습니다.'
                    : '부운영자는 소개글, 소개 사진, 일정, 회비를 관리할 수 있습니다.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          variant: AppCardVariant.outlined,
          child: Row(
            children: [
              Icon(Icons.mark_chat_unread_outlined, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '가입 전 문의',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '클럽장·매니저가 함께 답변하는 운영진 문의함',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubInquiryInboxScreen(
                      clubId: club.id,
                      clubName: club.name,
                    ),
                  ),
                ),
                child: const Text('문의함'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ClubIntroManageCard(
          club: club,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        _MonthlyFeeManageCard(
          club: club,
          monthlyFee: monthlyFee,
          onChanged: onMonthlyFeeChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        _JoinRequestManageCard(
          club: club,
          onChanged: onChanged,
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

class _JoinRequestManageCard extends ConsumerStatefulWidget {
  final Club club;
  final VoidCallback onChanged;

  const _JoinRequestManageCard({
    required this.club,
    required this.onChanged,
  });

  @override
  ConsumerState<_JoinRequestManageCard> createState() =>
      _JoinRequestManageCardState();
}

class _JoinRequestManageCardState
    extends ConsumerState<_JoinRequestManageCard> {
  late Future<List<_ClubJoinRequest>> _future;
  final Set<String> _busyRequestIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _JoinRequestManageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.club.id != widget.club.id) {
      _future = _load();
    }
  }

  Future<List<_ClubJoinRequest>> _load() async {
    final rows = await ref.read(apiProvider).pendingJoinRequests(
          widget.club.id,
        );
    return rows
        .map(_ClubJoinRequest.fromJson)
        .where((request) => request.id.isNotEmpty && request.userId.isNotEmpty)
        .toList(growable: false);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<bool> _confirmReject(_ClubJoinRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가입 신청 거절'),
        content: Text('${request.label}님의 가입 신청을 거절할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _review(
    _ClubJoinRequest request, {
    required bool approve,
  }) async {
    if (!approve && !await _confirmReject(request)) return;
    if (!mounted) return;
    setState(() => _busyRequestIds.add(request.id));
    try {
      await ref.read(apiProvider).reviewJoinRequest(
            request.id,
            approve: approve,
          );
      if (!mounted) return;
      widget.onChanged();
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '가입 신청을 승인했습니다' : '가입 신청을 거절했습니다')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? '승인 실패: $e' : '거절 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequestIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return _ClubFlatSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '가입 신청 관리',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '대기 중인 신청자를 확인하고 승인 또는 거절할 수 있습니다.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          FutureBuilder<List<_ClubJoinRequest>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: LinearProgressIndicator(),
                );
              }
              if (snap.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '가입 신청을 불러오지 못했습니다.',
                      style: tt.bodyMedium?.copyWith(color: cs.error),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('다시 시도'),
                    ),
                  ],
                );
              }
              final requests = snap.data ?? const <_ClubJoinRequest>[];
              if (requests.isEmpty) {
                return Text(
                  '대기 중인 가입 신청이 없습니다.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < requests.length; i++) ...[
                    if (i > 0) const Divider(height: AppSpacing.xl),
                    _JoinRequestManageRow(
                      request: requests[i],
                      busy: _busyRequestIds.contains(requests[i].id),
                      onApprove: () => _review(requests[i], approve: true),
                      onReject: () => _review(requests[i], approve: false),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _JoinRequestManageRow extends StatelessWidget {
  final _ClubJoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _JoinRequestManageRow({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final label = request.label;
    final initial = label.characters.isEmpty ? '?' : label.characters.first;
    final message = request.message?.trim();
    final requestedAt = _formatJoinRequestDate(request.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
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
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    requestedAt.isEmpty ? '가입 신청 대기 중' : '신청일 $requestedAt',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (message != null && message.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onApprove,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('승인'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('거절'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClubIntroManageCard extends ConsumerStatefulWidget {
  final Club club;
  final VoidCallback onChanged;

  const _ClubIntroManageCard({
    required this.club,
    required this.onChanged,
  });

  @override
  ConsumerState<_ClubIntroManageCard> createState() =>
      _ClubIntroManageCardState();
}

class _ClubIntroManageCardState extends ConsumerState<_ClubIntroManageCard> {
  late final TextEditingController _descriptionController;
  late List<String> _keptImageUrls;
  final List<_PendingPostImage> _newImages = [];
  bool _busy = false;

  int get _imageCount => _keptImageUrls.length + _newImages.length;
  bool get _canAddImage => !_busy && _imageCount < 5;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.club.description ?? '',
    );
    _keptImageUrls = _cleanIntroImageUrls(widget.club.introImageUrls);
  }

  @override
  void didUpdateWidget(covariant _ClubIntroManageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_busy) return;
    if (oldWidget.club.id != widget.club.id ||
        oldWidget.club.description != widget.club.description) {
      _descriptionController.text = widget.club.description ?? '';
    }
    if (oldWidget.club.introImageUrls != widget.club.introImageUrls) {
      _keptImageUrls = _cleanIntroImageUrls(widget.club.introImageUrls);
      _newImages.clear();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (!_canAddImage) return;
    final remaining = 5 - _imageCount;
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 86,
    );
    if (picked.isEmpty) return;

    final next = <_PendingPostImage>[];
    try {
      for (final file in picked.take(remaining)) {
        final image = await prepareClubImage(file);
        next.add(
          _PendingPostImage(
            bytes: image.bytes,
            extension: image.extension,
            contentType: image.contentType,
          ),
        );
      }
    } on ClubImagePreparationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _newImages.addAll(next));
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    if (description.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소개글은 2000자 이하로 입력해주세요')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final uploadedUrls = <String>[];
      for (final image in _newImages) {
        final url = await ref.read(apiProvider).uploadClubIntroImage(
              bytes: image.bytes,
              extension: image.extension,
              contentType: image.contentType,
            );
        uploadedUrls.add(url);
      }
      final imageUrls = [..._keptImageUrls, ...uploadedUrls];
      await ref.read(apiProvider).updateClubIntro(
            clubId: widget.club.id,
            description: description.isEmpty ? null : description,
            introImageUrls: imageUrls,
          );
      if (!mounted) return;
      setState(() {
        _keptImageUrls = imageUrls;
        _newImages.clear();
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클럽 소개를 저장했습니다')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('소개 저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return _ClubFlatSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '소개 관리',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$_imageCount/5',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '클럽 소개와 소개 사진은 소개 탭에 바로 노출됩니다.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _descriptionController,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '클럽 소개',
              hintText: '클럽 분위기, 활동 방식, 모집 안내를 적어주세요',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_imageCount == 0)
            OutlinedButton.icon(
              onPressed: _canAddImage ? _pickImages : null,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text('소개 사진 추가'),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < _keptImageUrls.length; i++)
                  _ClubIntroManageThumb(
                    imageUrl: _keptImageUrls[i],
                    onRemove: _busy
                        ? null
                        : () => setState(() => _keptImageUrls.removeAt(i)),
                  ),
                for (var i = 0; i < _newImages.length; i++)
                  _ClubIntroManageThumb(
                    image: _newImages[i],
                    onRemove: _busy
                        ? null
                        : () => setState(() => _newImages.removeAt(i)),
                  ),
                if (_canAddImage)
                  InkWell(
                    onTap: _pickImages,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_rounded,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
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
            label: const Text('소개 저장'),
          ),
        ],
      ),
    );
  }
}

class _ClubIntroManageThumb extends StatelessWidget {
  final String? imageUrl;
  final _PendingPostImage? image;
  final VoidCallback? onRemove;

  const _ClubIntroManageThumb({
    this.imageUrl,
    this.image,
    required this.onRemove,
  }) : assert(imageUrl != null || image != null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = image != null
        ? Image.memory(
            image!.bytes,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
          )
        : Image.network(
            imageUrl!,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 92,
              height: 92,
              color: cs.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                color: cs.onSurfaceVariant,
              ),
            ),
          );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: child,
        ),
        Positioned(
          right: 4,
          top: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: AppRadius.pill,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<String> _cleanIntroImageUrls(List<String> urls) {
  return urls
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .take(5)
      .toList(growable: true);
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
    return _ClubFlatSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('회비 관리',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
    return _ClubFlatSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('멤버 권한 관리',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
        content: Text('${_clubMemberDisplayName(widget.member)}를 강퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
              content:
                  Text('${_clubMemberDisplayName(widget.member)}를 강퇴했습니다')),
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
    final displayName = _clubMemberDisplayName(member);
    final initial = displayName.characters.first;
    final permissionLabels = [
      if (member.canCreateEvent) '일정 등록',
      if (member.canPostNotice) '공지 등록',
    ];
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
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  permissionLabels.isEmpty
                      ? member.roleLabel
                      : '${member.roleLabel} · ${permissionLabels.join(' · ')}',
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
        content: Text(
          '${widget.club.name} 클럽을 정말 삭제할까요?\n삭제 후에는 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).deleteClub(widget.club.id);
      if (mounted) {
        ref.invalidate(myClubsProvider);
        ref.invalidate(myFavoriteClubsProvider);
        ref.invalidate(clubFavoriteIdsProvider);
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
    return _ClubFlatSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('클럽 삭제',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
  final Future<List<ClubMember>> membersFuture;
  final bool canCreateEvent;
  final VoidCallback onChanged;
  const _EventsTab({
    required this.club,
    required this.future,
    required this.membersFuture,
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
            return FutureBuilder<List<ClubMember>>(
              future: membersFuture,
              builder: (context, membersSnap) {
                final members = membersSnap.data ?? const <ClubMember>[];
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
                    members: members,
                    onChanged: onChanged,
                  ),
                );
              },
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
  final List<ClubMember> members;
  final VoidCallback onChanged;
  const _EventCard({
    required this.event,
    required this.members,
    required this.onChanged,
  });

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

  void _showResponses() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _EventResponsesSheet(
        event: widget.event,
        members: widget.members,
      ),
    );
  }

  Future<void> _reportEvent() async {
    await showUgcReportSheet(
      context: context,
      ref: ref,
      targetType: UgcTargetType.clubEvent,
      targetId: widget.event.id,
    );
  }

  Future<void> _blockEventAuthor() async {
    final authorId = widget.event.createdBy;
    if (authorId == null) return;
    final blocked = await confirmBlockUser(
      context: context,
      ref: ref,
      userId: authorId,
      displayName: '모임 작성자',
    );
    if (blocked) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final e = widget.event;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final canModerateAuthor =
        e.createdBy != null && e.createdBy != currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        variant: AppCardVariant.outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _InfoChip(
                        icon: Icons.event_available_rounded,
                        label: e.capacity == null
                            ? '${e.goingCount}명 참석'
                            : '${e.goingCount}/${e.capacity}명',
                      ),
                      _InfoChip(
                        icon: Icons.event_busy_rounded,
                        label: '${e.notGoingCount}명 불참',
                      ),
                      if (e.fee != null)
                        _InfoChip(
                          icon: Icons.payments_outlined,
                          label: '${e.fee}원',
                        ),
                      if (e.responseCount > 0)
                        TextButton.icon(
                          onPressed: _showResponses,
                          icon: const Icon(Icons.people_alt_outlined, size: 18),
                          label: const Text('응답자 보기'),
                        ),
                    ],
                  ),
                ),
                if (canModerateAuthor)
                  PopupMenuButton<String>(
                    tooltip: '모임 더보기',
                    onSelected: (value) {
                      if (value == 'report') unawaited(_reportEvent());
                      if (value == 'block') unawaited(_blockEventAuthor());
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'report', child: Text('모임 신고')),
                      PopupMenuItem(value: 'block', child: Text('작성자 차단')),
                    ],
                  ),
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
                    onPressed: _busy || (e.isFull && !e.iAmGoing)
                        ? null
                        : () => _respond(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: e.iAmGoing ? cs.primary : null,
                      foregroundColor: e.iAmGoing ? cs.onPrimary : null,
                    ),
                    child: Text(e.isFull && !e.iAmGoing ? '마감' : '참석'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _respond(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: e.iAmNotGoing ? cs.error : null,
                      side: e.iAmNotGoing ? BorderSide(color: cs.error) : null,
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

class _EventResponsesSheet extends StatelessWidget {
  final ClubEvent event;
  final List<ClubMember> members;

  const _EventResponsesSheet({
    required this.event,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final namesByUserId = {
      for (final member in members)
        member.userId: _clubMemberDisplayName(member),
    };
    final going = event.attendees.where((attendee) => attendee.isGoing);
    final notGoing = event.attendees.where((attendee) => attendee.isNotGoing);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.48,
      minChildSize: 0.34,
      maxChildSize: 0.82,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '일정 응답자',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ResponseGroup(
              icon: Icons.event_available_rounded,
              title: '참석',
              count: event.goingCount,
              attendees: going,
              namesByUserId: namesByUserId,
            ),
            const SizedBox(height: AppSpacing.lg),
            _ResponseGroup(
              icon: Icons.event_busy_rounded,
              title: '불참',
              count: event.notGoingCount,
              attendees: notGoing,
              namesByUserId: namesByUserId,
            ),
          ],
        );
      },
    );
  }
}

class _ResponseGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Iterable<ClubEventAttendance> attendees;
  final Map<String, String?> namesByUserId;

  const _ResponseGroup({
    required this.icon,
    required this.title,
    required this.count,
    required this.attendees,
    required this.namesByUserId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final attendeeList = attendees.toList();

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$title $count명',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (attendeeList.isEmpty)
            Text(
              '아직 $title 응답이 없습니다.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            for (final attendee in attendeeList) ...[
              _ResponseMemberRow(
                name: namesByUserId[attendee.userId] ??
                    '멤버 ${_shortUserId(attendee.userId)}',
              ),
              if (attendee != attendeeList.last)
                Divider(height: AppSpacing.md, color: cs.outlineVariant),
            ],
        ],
      ),
    );
  }
}

class _ResponseMemberRow extends StatelessWidget {
  final String name;

  const _ResponseMemberRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer.withValues(alpha: 0.48),
          child: Icon(Icons.person_rounded, size: 18, color: cs.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
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
  final _fee = TextEditingController();
  final _capacity = TextEditingController();
  DateTime? _startsAt;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    _fee.dispose();
    _capacity.dispose();
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
    final fee =
        _fee.text.trim().isEmpty ? null : int.tryParse(_fee.text.trim());
    final capacity = _capacity.text.trim().isEmpty
        ? null
        : int.tryParse(_capacity.text.trim());
    if ((fee != null && fee < 0) || (capacity != null && capacity < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비용과 제한 인원을 올바르게 입력하세요.')),
      );
      return;
    }
    final allowed = await ensureUgcPermission(
      context,
      ref,
      UgcActionKind.community,
    );
    if (!allowed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).createClubEvent(
            clubId: widget.club.id,
            title: _title.text.trim(),
            description: _desc.text.trim(),
            locationText: _location.text.trim(),
            startsAt: _startsAt!,
            fee: fee,
            capacity: capacity,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ugcActionErrorMessage(e, fallback: '모임을 만들지 못했습니다.'),
            ),
          ),
        );
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
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '참가 비용',
                    suffixText: '원',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '제한 인원',
                    suffixText: '명',
                  ),
                ),
              ),
            ],
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
              minimumSize: const Size.fromHeight(AppSizes.control),
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
  bool get _canPinPosts => widget.club.isOwner || widget.club.isManager;
  bool get _canPostNotice => widget.club.canPostNotice;

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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: _PostWriteEntry(
            canPostNotice: _canPostNotice,
            canPinPosts: _canPinPosts,
            onTap: _openCreatePost,
          ),
        ),
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
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    itemCount: _posts!.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _PostRow(
                        post: _posts![i],
                        onTap: () => _showPostDetail(_posts![i]),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openCreatePost() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _PostCreateSheet(
        club: widget.club,
        canPostNotice: _canPostNotice,
        canPinPosts: _canPinPosts,
      ),
    );
    if (created == true) _load();
  }

  Future<void> _showPostDetail(ClubPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PostDetailSheet(post: post),
    );
    await _load();
  }
}

class _PostDetailSheet extends ConsumerStatefulWidget {
  const _PostDetailSheet({required this.post});

  final ClubPost post;

  @override
  ConsumerState<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends ConsumerState<_PostDetailSheet> {
  final _commentController = TextEditingController();
  List<ClubPostComment>? _comments;
  bool _loadingComments = false;
  bool _sendingComment = false;
  String? _commentError;

  @override
  void initState() {
    super.initState();
    if (widget.post.allowsComments) _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentError = null;
    });
    try {
      final comments = await ref.read(apiProvider).postComments(widget.post.id);
      if (!mounted) return;
      setState(() => _comments = comments);
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentError = '댓글을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _submitComment() async {
    if (_sendingComment || !widget.post.allowsComments) return;
    final body = _commentController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 내용을 입력해주세요.')),
      );
      return;
    }

    final allowed = await ensureUgcPermission(
      context,
      ref,
      UgcActionKind.comment,
    );
    if (!allowed || !mounted) return;

    setState(() => _sendingComment = true);
    try {
      final comment = await ref.read(apiProvider).addComment(
            postId: widget.post.id,
            body: body,
          );
      if (!mounted) return;
      setState(() {
        _comments = [...?_comments, comment];
        _commentController.clear();
        _commentError = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ugcActionErrorMessage(
              error,
              fallback: '댓글을 등록하지 못했습니다. 다시 시도해주세요.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _reportPost() async {
    await showUgcReportSheet(
      context: context,
      ref: ref,
      targetType: UgcTargetType.clubPost,
      targetId: widget.post.id,
    );
  }

  Future<void> _blockPostAuthor() async {
    final authorId = widget.post.authorId;
    if (authorId == null) return;
    final blocked = await confirmBlockUser(
      context: context,
      ref: ref,
      userId: authorId,
      displayName: widget.post.authorDisplayName,
    );
    if (blocked && mounted) Navigator.pop(context);
  }

  Future<void> _reportComment(ClubPostComment comment) async {
    await showUgcReportSheet(
      context: context,
      ref: ref,
      targetType: UgcTargetType.clubComment,
      targetId: comment.id,
    );
  }

  Future<void> _blockCommentAuthor(ClubPostComment comment) async {
    final authorId = comment.authorId;
    if (authorId == null) return;
    final blocked = await confirmBlockUser(
      context: context,
      ref: ref,
      userId: authorId,
      displayName: comment.authorDisplayName,
    );
    if (blocked && mounted) await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final canModerateAuthor =
        post.authorId != null && post.authorId != currentUserId;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.48,
        maxChildSize: 0.94,
        builder: (context, controller) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                children: [
                  Text(
                    post.tagLabel,
                    style: tt.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    post.title,
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${post.authorDisplayName} · ${_postDateText(post.createdAt)}',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (canModerateAuthor)
                        PopupMenuButton<String>(
                          tooltip: '게시글 더보기',
                          onSelected: (value) {
                            if (value == 'report') unawaited(_reportPost());
                            if (value == 'block') {
                              unawaited(_blockPostAuthor());
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'report',
                              child: Text('게시글 신고'),
                            ),
                            PopupMenuItem(
                              value: 'block',
                              child: Text('작성자 차단'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  Text(
                    post.body,
                    style: tt.bodyLarge?.copyWith(height: 1.6),
                  ),
                  for (final url in post.imageUrls) ...[
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: AppRadius.card,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 180,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (!post.allowsComments)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: AppRadius.card,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.campaign_outlined, color: cs.primary),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(
                            child: Text('공지사항은 댓글을 받지 않습니다.'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      '댓글 ${_comments?.length ?? 0}',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_loadingComments)
                      const Center(child: CircularProgressIndicator())
                    else if (_commentError != null)
                      _CommentLoadError(
                        message: _commentError!,
                        onRetry: _loadComments,
                      )
                    else if (_comments?.isEmpty ?? true)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Text(
                          '첫 댓글을 남겨보세요.',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (final comment in _comments!)
                        _CommentRow(
                          comment: comment,
                          canModerate: comment.authorId != null &&
                              comment.authorId != currentUserId,
                          onReport: () => _reportComment(comment),
                          onBlock: () => _blockCommentAuthor(comment),
                        ),
                  ],
                ],
              ),
            ),
            if (post.allowsComments)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        enabled: !_sendingComment,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          hintText: '댓글을 입력하세요',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filled(
                      onPressed: _sendingComment ? null : _submitComment,
                      tooltip: '댓글 등록',
                      icon: _sendingComment
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.canModerate,
    required this.onReport,
    required this.onBlock,
  });

  final ClubPostComment comment;
  final bool canModerate;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Icon(
              Icons.person_rounded,
              size: 18,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.authorDisplayName,
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  _postDateText(comment.createdAt),
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(comment.body, style: tt.bodyMedium),
              ],
            ),
          ),
          if (canModerate)
            PopupMenuButton<String>(
              tooltip: '댓글 더보기',
              onSelected: (value) {
                if (value == 'report') onReport();
                if (value == 'block') onBlock();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('댓글 신고')),
                PopupMenuItem(value: 'block', child: Text('작성자 차단')),
              ],
            ),
        ],
      ),
    );
  }
}

class _CommentLoadError extends StatelessWidget {
  const _CommentLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

String _postDateText(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

class _PostWriteEntry extends StatelessWidget {
  final bool canPostNotice;
  final bool canPinPosts;
  final VoidCallback onTap;

  const _PostWriteEntry({
    required this.canPostNotice,
    required this.canPinPosts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Icon(Icons.edit_note_rounded, color: cs.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '게시글 작성',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  canPinPosts
                      ? '중요 공지와 상단 고정을 사용할 수 있어요.'
                      : canPostNotice
                          ? '공지 글을 작성할 수 있어요.'
                          : '클럽 멤버는 누구나 글을 쓸 수 있어요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _PostCreateSheet extends ConsumerStatefulWidget {
  final Club club;
  final bool canPostNotice;
  final bool canPinPosts;

  const _PostCreateSheet({
    required this.club,
    required this.canPostNotice,
    required this.canPinPosts,
  });

  @override
  ConsumerState<_PostCreateSheet> createState() => _PostCreateSheetState();
}

class _PostCreateSheetState extends ConsumerState<_PostCreateSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final List<_PendingPostImage> _images = [];
  String _tag = 'free';
  bool _isPinned = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력해주세요.')),
      );
      return;
    }
    if (_tag == 'photo' && _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 게시글에는 사진을 1장 이상 추가해주세요.')),
      );
      return;
    }
    if (_images.isNotEmpty) {
      try {
        final hasVerifiedAge =
            await ref.read(apiProvider).hasVerifiedSignupAge();
        if (!hasVerifiedAge) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('생년월일 등록이 필요합니다'),
              content: const Text(
                '사진을 올리려면 프로필에서 생년월일을 등록해주세요. '
                '프로필 화면의 “프로필·생년월일 수정”에서 등록할 수 있습니다.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 업로드 권한을 확인하지 못했습니다.')),
        );
        return;
      }
    }
    if (!mounted) return;
    final allowed = await ensureUgcPermission(
      context,
      ref,
      UgcActionKind.community,
    );
    if (!allowed || !mounted) return;
    setState(() => _busy = true);
    try {
      final imageUrls = <String>[];
      for (final image in _images) {
        final url = await ref.read(apiProvider).uploadPostImage(
              clubId: widget.club.id,
              bytes: image.bytes,
              extension: image.extension,
              contentType: image.contentType,
            );
        imageUrls.add(url);
      }
      await ref.read(apiProvider).createPost(
            clubId: widget.club.id,
            tag: _tag,
            title: title,
            body: body,
            isPinned: widget.canPinPosts && _isPinned,
            imageUrls: imageUrls,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ugcActionErrorMessage(e, fallback: '게시글을 등록하지 못했습니다.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImages() async {
    if (_images.length >= 5) return;
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 86,
    );
    if (picked.isEmpty) return;

    final next = <_PendingPostImage>[];
    try {
      for (final file in picked.take(5 - _images.length)) {
        final image = await prepareClubImage(file);
        next.add(
          _PendingPostImage(
            bytes: image.bytes,
            extension: image.extension,
            contentType: image.contentType,
          ),
        );
      }
    } on ClubImagePreparationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _images.addAll(next));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.48,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '게시글 작성',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.canPinPosts
                    ? '운영진은 중요 공지와 상단 고정을 사용할 수 있어요.'
                    : widget.canPostNotice
                        ? '공지 권한이 있어 중요 공지를 작성할 수 있어요.'
                        : '클럽 멤버는 자유롭게 게시글을 작성할 수 있어요.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _PostTagChoice(
                    label: '자유',
                    selected: _tag == 'free',
                    onTap: () => setState(() {
                      _tag = 'free';
                      _isPinned = false;
                      _images.clear();
                    }),
                  ),
                  _PostTagChoice(
                    label: '모집',
                    selected: _tag == 'recruit',
                    onTap: () => setState(() {
                      _tag = 'recruit';
                      _isPinned = false;
                      _images.clear();
                    }),
                  ),
                  _PostTagChoice(
                    label: '사진',
                    selected: _tag == 'photo',
                    onTap: () => setState(() {
                      _tag = 'photo';
                      _isPinned = false;
                    }),
                  ),
                  if (widget.canPostNotice)
                    _PostTagChoice(
                      label: '중요 공지',
                      selected: _tag == 'notice',
                      onTap: () => setState(() {
                        _tag = 'notice';
                        _images.clear();
                      }),
                    ),
                ],
              ),
              if (widget.canPinPosts) ...[
                const SizedBox(height: AppSpacing.md),
                SwitchListTile.adaptive(
                  value: _isPinned,
                  onChanged: (value) => setState(() => _isPinned = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('상단 고정'),
                  subtitle: Text(
                    '중요한 글을 게시판 맨 위에 고정합니다.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_tag == 'photo') ...[
                _PostPhotoPicker(
                  images: _images,
                  busy: _busy,
                  onAdd: _pickImages,
                  onRemove: (index) => setState(() => _images.removeAt(index)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: _title,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '제목',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _body,
                enabled: !_busy,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '내용',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_busy ? '등록 중' : '등록하기'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingPostImage {
  final Uint8List bytes;
  final String extension;
  final String contentType;

  const _PendingPostImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });
}

class _PostPhotoPicker extends StatelessWidget {
  final List<_PendingPostImage> images;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _PostPhotoPicker({
    required this.images,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canAdd = !busy && images.length < 5;

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '사진 추가',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${images.length}/5',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '사진과 글을 함께 올릴 수 있어요.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          if (images.isEmpty)
            OutlinedButton.icon(
              onPressed: canAdd ? onAdd : null,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text('사진 선택하기'),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < images.length; i++)
                  _PostPhotoThumb(
                    image: images[i],
                    onRemove: busy ? null : () => onRemove(i),
                  ),
                if (canAdd)
                  InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_rounded,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PostPhotoThumb extends StatelessWidget {
  final _PendingPostImage image;
  final VoidCallback? onRemove;

  const _PostPhotoThumb({
    required this.image,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Image.memory(
            image.bytes,
            width: 86,
            height: 86,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: AppRadius.pill,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostTagChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PostTagChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
  final VoidCallback onTap;
  const _PostRow({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNotice = post.tag == 'notice';
    final background = isNotice
        ? cs.errorContainer.withValues(alpha: 0.28)
        : post.isPinned
            ? cs.primaryContainer.withValues(alpha: 0.24)
            : cs.surface;
    final borderColor = isNotice
        ? cs.error.withValues(alpha: 0.34)
        : post.isPinned
            ? cs.primary.withValues(alpha: 0.38)
            : cs.outlineVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.card,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.card,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNotice) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.campaign_rounded,
                    size: 20, color: cs.onErrorContainer),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (post.isPinned)
                        _PostMetaChip(
                          icon: Icons.push_pin_rounded,
                          label: '상단 고정',
                          color: cs.primary,
                          background: cs.primaryContainer,
                        ),
                      _PostMetaChip(
                        icon: isNotice
                            ? Icons.campaign_rounded
                            : Icons.article_outlined,
                        label: isNotice ? '중요 공지' : post.tagLabel,
                        color: isNotice ? cs.error : cs.onSurfaceVariant,
                        background: isNotice
                            ? cs.errorContainer
                            : cs.surfaceContainerHighest,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isNotice ? cs.onErrorContainer : cs.onSurface,
                    ),
                  ),
                  if (post.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _PostImagePreview(urls: post.imageUrls),
                  ],
                  if (isNotice || post.tag == 'photo') ...[
                    const SizedBox(height: 4),
                    Text(
                      post.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: isNotice
                            ? cs.onErrorContainer.withValues(alpha: 0.76)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${post.authorDisplayName} · ${_timeAgo(post.createdAt)}${post.allowsComments && post.commentCount > 0 ? ' · 댓글 ${post.commentCount}' : ''}',
                    style: tt.bodySmall?.copyWith(
                      color: isNotice
                          ? cs.onErrorContainer.withValues(alpha: 0.76)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _PostImagePreview extends StatelessWidget {
  final List<String> urls;

  const _PostImagePreview({required this.urls});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstUrl = urls.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              firstUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (urls.length > 1)
            Positioned(
              right: AppSpacing.xs,
              bottom: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  '+${urls.length - 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  const _PostMetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

String _fmtDateTime(DateTime dt) {
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  final w = wd[(dt.weekday - 1) % 7];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.month}월 ${dt.day}일 ($w) $h:$m';
}
