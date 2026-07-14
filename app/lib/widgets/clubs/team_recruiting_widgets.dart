import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/club_recruiting.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../app_card.dart';
import 'club_tiles.dart';

class TeamRecruitingBoard extends StatelessWidget {
  final List<RecruitingPostPreview> posts;
  final bool showOpenOnly;
  final bool isLoading;
  final Set<String> managedClubIds;
  final ValueChanged<bool> onShowOpenOnlyChanged;
  final ValueChanged<RecruitingPostPreview> onClosePost;
  final ValueChanged<RecruitingPostPreview> onOpenPost;

  const TeamRecruitingBoard({
    super.key,
    required this.posts,
    required this.showOpenOnly,
    required this.isLoading,
    required this.managedClubIds,
    required this.onShowOpenOnlyChanged,
    required this.onClosePost,
    required this.onOpenPost,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final openCount = posts.where((post) => !post.isClosed).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '팀원모집 글',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            showOpenOnly ? '모집중인 글만 보고 있어요.' : '모집중 글과 마감글을 함께 보여줘요.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: showOpenOnly,
              label: Text('모집중만 $openCount'),
              onSelected: onShowOpenOnlyChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (posts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                '선택한 관심 종목에 맞는 팀원모집 글이 없습니다.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final post in posts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TeamRecruitingPostCard(
                  post: post,
                  canManage: managedClubIds.contains(post.clubId),
                  onClose: () => onClosePost(post),
                  onTap: () => onOpenPost(post),
                ),
              ),
        ],
      ),
    );
  }
}

class TeamRecruitingPostCard extends StatelessWidget {
  final RecruitingPostPreview post;
  final bool canManage;
  final VoidCallback onClose;
  final VoidCallback onTap;

  const TeamRecruitingPostCard({
    super.key,
    required this.post,
    required this.canManage,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isFutsal = post.sport == 'futsal';
    final accent = post.isClosed ? cs.outline : cs.primary;
    final chipColor = post.isClosed
        ? cs.surfaceContainerHighest
        : (isFutsal ? const Color(0xFFE6F7C7) : const Color(0xFFE8EEFF));

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: BorderRadius.circular(20),
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isFutsal
                          ? Icons.sports_soccer_rounded
                          : Icons.sports_tennis_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RecruitingStatusPill(isClosed: post.isClosed),
                            Text(
                              sportLabelFromString(post.sport),
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          post.clubName,
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
              if (canManage && !post.isClosed) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('마감하기'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MiniInfoChip(icon: Icons.place_rounded, label: post.region),
              MiniInfoChip(icon: Icons.schedule_rounded, label: post.schedule),
              MiniInfoChip(icon: Icons.stars_rounded, label: post.grade),
              MiniInfoChip(icon: Icons.groups_rounded, label: post.countLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${post.place} · ${post.gender} · ${post.age} · ${post.cost}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class RecruitingStatusPill extends StatelessWidget {
  final bool isClosed;

  const RecruitingStatusPill({super.key, required this.isClosed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isClosed ? cs.surfaceContainerHighest : const Color(0xFFE6F7C7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isClosed ? '마감' : '모집중',
        style: TextStyle(
          color: isClosed ? cs.onSurfaceVariant : const Color(0xFF4F8F00),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class MiniInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const MiniInfoChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class TeamRecruitingDetailScreen extends ConsumerStatefulWidget {
  final RecruitingPostPreview post;
  final Club? club;

  const TeamRecruitingDetailScreen({super.key, required this.post, this.club});

  @override
  ConsumerState<TeamRecruitingDetailScreen> createState() =>
      _TeamRecruitingDetailScreenState();
}

class _TeamRecruitingDetailScreenState
    extends ConsumerState<TeamRecruitingDetailScreen> {
  bool _busy = false;
  bool _applied = false;

  RecruitingPostPreview get post => widget.post;
  Club? get club => widget.club;

  Future<void> _contactForParticipation() async {
    final targetClub = club;
    if (targetClub == null || post.isClosed || _busy) return;
    if (targetClub.isMember || _applied) {
      await context.push('/clubs/${targetClub.id}', extra: targetClub);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).joinClub(
            targetClub.id,
            message: '팀원모집 참여 신청: ${post.title}',
          );
      if (!mounted) return;
      setState(() => _applied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('운영진에게 참여 신청을 보냈습니다.')),
      );
      await context.push('/clubs/${targetClub.id}', extra: targetClub);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('참여 신청을 보내지 못했습니다. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isFutsal = post.sport == 'futsal';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('팀원모집 상세'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            AppCard(
              variant: AppCardVariant.elevated,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (club != null)
                        SimpleClubAvatar(club: club!, size: 58)
                      else
                        _RecruitingFallbackBadge(sport: post.sport),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                RecruitingStatusPill(isClosed: post.isClosed),
                                MiniInfoChip(
                                  icon: isFutsal
                                      ? Icons.sports_soccer_rounded
                                      : Icons.sports_tennis_rounded,
                                  label: sportLabelFromString(post.sport),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              post.clubName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              post.title,
                              style: tt.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    post.introText,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _RecruitingDetailSection(
              title: '모집 조건',
              children: [
                _RecruitingDetailRow(
                  icon: Icons.people_alt_rounded,
                  label: '성별',
                  value: post.gender,
                ),
                _RecruitingDetailRow(
                  icon: Icons.badge_rounded,
                  label: '실력',
                  value: post.grade,
                ),
                _RecruitingDetailRow(
                  icon: Icons.groups_rounded,
                  label: '모집 인원',
                  value: post.countLabel,
                ),
                _RecruitingDetailRow(
                  icon: Icons.cake_rounded,
                  label: '나이대',
                  value: post.age,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _RecruitingDetailSection(
              title: '운동 정보',
              children: [
                _RecruitingDetailRow(
                  icon: Icons.schedule_rounded,
                  label: '일정',
                  value: post.schedule,
                ),
                _RecruitingDetailRow(
                  icon: Icons.place_rounded,
                  label: '장소',
                  value: post.place,
                ),
                _RecruitingDetailRow(
                  icon: Icons.payments_rounded,
                  label: '비용',
                  value: post.cost,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _RecruitingDetailSection(
              title: '작성자 소개',
              children: [
                _RecruitingDetailRow(
                  icon: Icons.info_outline_rounded,
                  label: '안내',
                  value: club?.description ?? '클럽 운영자가 작성한 팀원모집 글입니다.',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: club == null
                  ? null
                  : () {
                      context.push('/clubs/${club!.id}', extra: club);
                    },
              icon: const Icon(Icons.groups_rounded),
              label: const Text('클럽 상세 보기'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: post.isClosed || club == null || _busy
                  ? null
                  : _contactForParticipation,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(
                post.isClosed
                    ? '모집이 마감되었습니다'
                    : club?.isMember == true
                        ? '클럽에서 문의하기'
                        : _applied
                            ? '가입 승인 상태 확인'
                            : '참여 신청하기',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecruitingFallbackBadge extends StatelessWidget {
  final String sport;

  const _RecruitingFallbackBadge({required this.sport});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFutsal = sport == 'futsal';
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: isFutsal ? const Color(0xFFE6F7C7) : const Color(0xFFE8EEFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        isFutsal ? Icons.sports_soccer_rounded : Icons.sports_tennis_rounded,
        color: cs.primary,
      ),
    );
  }
}

class _RecruitingDetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _RecruitingDetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardInner,
      decoration: BoxDecoration(
        color: isLight ? Colors.white : cs.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border.all(color: cs.outlineVariant),
        boxShadow: isLight ? AppShadows.card : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _RecruitingDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RecruitingDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class TeamRecruitingDraftSheet extends ConsumerStatefulWidget {
  final List<Club> managedClubs;

  const TeamRecruitingDraftSheet({super.key, required this.managedClubs});

  @override
  ConsumerState<TeamRecruitingDraftSheet> createState() =>
      _TeamRecruitingDraftSheetState();
}

class _TeamRecruitingDraftSheetState
    extends ConsumerState<TeamRecruitingDraftSheet> {
  static const _genders = ['무관', '여성', '남성', '혼성'];
  static const _ages = ['무관', '20대', '30대', '40대', '50대 이상'];
  static const _futsalPositions = ['필드·키퍼', '필드', '키퍼'];
  static const _futsalGrades = ['무관', '입문', '초급', '중급', '고급', '선출'];
  static const _tennisGrades = ['무관', '신입', '5부', '4부', '3부', '2부', '1부'];

  late String _selectedClubId = widget.managedClubs.first.id;
  String _gender = _genders.first;
  String _age = _ages.first;
  String _position = _futsalPositions.first;
  String _grade = _futsalGrades.first;
  int _fieldCount = 4;
  int _keeperCount = 1;
  int _tennisCount = 2;
  bool _busy = false;

  late final TextEditingController _titleController;
  late final TextEditingController _placeController;
  late final TextEditingController _dateController;
  late final TextEditingController _timeController;
  late final TextEditingController _costController;
  late final TextEditingController _introController;

  Club get _selectedClub =>
      widget.managedClubs.firstWhere((club) => club.id == _selectedClubId);

  bool get _isFutsal => _selectedClub.sport == 'futsal';

  List<String> get _gradeOptions => _isFutsal ? _futsalGrades : _tennisGrades;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _placeController = TextEditingController(text: _selectedClub.address ?? '');
    _dateController = TextEditingController();
    _timeController = TextEditingController();
    _costController = TextEditingController();
    _introController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _placeController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _costController.dispose();
    _introController.dispose();
    super.dispose();
  }

  Future<void> _showClubPicker() async {
    final selected = await showModalBottomSheet<Club>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _ManagedClubPickerSheet(
        clubs: widget.managedClubs,
        selectedClubId: _selectedClubId,
      ),
    );
    if (selected == null) return;
    final previousAddress = _selectedClub.address?.trim() ?? '';
    setState(() {
      _selectedClubId = selected.id;
      _grade = _gradeOptions.first;
      if (_placeController.text.trim().isEmpty ||
          _placeController.text.trim() == previousAddress) {
        _placeController.text = selected.address ?? '';
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final title = _titleController.text.trim();
    final place = _placeController.text.trim();
    final date = _dateController.text.trim();
    final time = _timeController.text.trim();
    if (title.isEmpty || place.isEmpty || date.isEmpty || time.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목, 장소, 날짜, 시간을 모두 입력해주세요.')),
      );
      return;
    }

    final fieldCount = _isFutsal && _position != '키퍼' ? _fieldCount : 0;
    final keeperCount = _isFutsal && _position != '필드' ? _keeperCount : 0;
    final totalCount = _isFutsal ? fieldCount + keeperCount : _tennisCount;
    if (totalCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집 인원을 1명 이상 선택해주세요.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).createTeamRecruitingPost(
            clubId: _selectedClub.id,
            title: title,
            place: place,
            schedule: '$date $time',
            skillLevel: _grade,
            gender: _gender,
            age: _age,
            position: _isFutsal ? _position : null,
            fieldCount: fieldCount,
            keeperCount: keeperCount,
            totalCount: totalCount,
            cost: _costController.text,
            intro: _introController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집글을 올리지 못했습니다. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7F1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '팀원모집 글쓰기',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '운영 중인 클럽 기준으로 모집글을 작성해요.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _ManagedClubSelectorField(
                club: _selectedClub,
                onTap: _showClubPicker,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _titleController,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '모집글 제목',
                  hintText: '예: 토요일 저녁 함께 뛸 팀원 모집해요',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              RecruitingSection(
                title: '모집 조건',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '성별',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final gender in _genders)
                          ChoiceChip(
                            label: Text(gender),
                            selected: _gender == gender,
                            onSelected: (_) => setState(() {
                              _gender = gender;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '연령',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final age in _ages)
                          ChoiceChip(
                            label: Text(age),
                            selected: _age == age,
                            onSelected: (_) => setState(() {
                              _age = age;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              RecruitingSection(
                title: _isFutsal ? '풋살 모집 상세' : '테니스 모집 상세',
                child: _isFutsal
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '포지션',
                            style: tt.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final position in _futsalPositions)
                                ChoiceChip(
                                  label: Text(position),
                                  selected: _position == position,
                                  onSelected: (_) => setState(() {
                                    _position = position;
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          GradeSelector(
                            title: '등급',
                            options: _gradeOptions,
                            selected: _grade,
                            onSelected: (grade) => setState(() {
                              _grade = grade;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: CountStepper(
                                  label: '필드',
                                  value: _fieldCount,
                                  onChanged: (value) => setState(() {
                                    _fieldCount = value;
                                  }),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: CountStepper(
                                  label: '키퍼',
                                  value: _keeperCount,
                                  onChanged: (value) => setState(() {
                                    _keeperCount = value;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GradeSelector(
                            title: '등급',
                            options: _gradeOptions,
                            selected: _grade,
                            onSelected: (grade) => setState(() {
                              _grade = grade;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          CountStepper(
                            label: '모집 인원',
                            value: _tennisCount,
                            onChanged: (value) => setState(() {
                              _tennisCount = value;
                            }),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              RecruitingSection(
                title: '운동 정보',
                child: Column(
                  children: [
                    TextField(
                      controller: _placeController,
                      decoration: const InputDecoration(
                        labelText: '운동하는 장소',
                        hintText: '예: 광주 북구 풋살파크 A구장',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dateController,
                            decoration: const InputDecoration(
                              labelText: '날짜',
                              hintText: '6/22 (토)',
                              prefixIcon: Icon(Icons.calendar_month_rounded),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _timeController,
                            decoration: const InputDecoration(
                              labelText: '시간',
                              hintText: '19:00',
                              prefixIcon: Icon(Icons.schedule_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _costController,
                      decoration: const InputDecoration(
                        labelText: '비용',
                        hintText: '예: 10,000원 또는 무료',
                        prefixIcon: Icon(Icons.payments_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              RecruitingSection(
                title: '상세 내용',
                child: TextField(
                  controller: _introController,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    hintText: '필요 포지션, 준비물, 경기 수준, 연락 방식 등을 적어주세요.',
                    alignLabelWithHint: true,
                    labelText: '기타 내용',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_note_rounded),
                      label: Text(_busy ? '올리는 중...' : '모집글 올리기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagedClubSelectorField extends StatelessWidget {
  const _ManagedClubSelectorField({
    required this.club,
    required this.onTap,
  });

  final Club club;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Text(
            '모집할 클럽',
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                SimpleClubAvatar(club: club, size: 46),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        club.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'} · 운영진',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ManagedClubPickerSheet extends StatelessWidget {
  const _ManagedClubPickerSheet({
    required this.clubs,
    required this.selectedClubId,
  });

  final List<Club> clubs;
  final String selectedClubId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.54,
      minChildSize: 0.36,
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
              '모집할 클럽 선택',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '운영 중인 클럽 중 모집글을 올릴 클럽을 선택하세요.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final club in clubs) ...[
              _ManagedClubOptionTile(
                club: club,
                selected: club.id == selectedClubId,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _ManagedClubOptionTile extends StatelessWidget {
  const _ManagedClubOptionTile({
    required this.club,
    required this.selected,
  });

  final Club club;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => Navigator.pop(context, club),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.34)
              : cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            SimpleClubAvatar(club: club, size: 48),
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
                  const SizedBox(height: 2),
                  Text(
                    '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'} · 운영진',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: cs.primary)
            else
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class GradeSelector extends StatelessWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const GradeSelector({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: selected == option,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class CountStepper extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const CountStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              StepperButton(
                icon: Icons.remove_rounded,
                onTap: value > 0 ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value명',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              StepperButton(
                icon: Icons.add_rounded,
                onTap: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const StepperButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap == null ? cs.surfaceContainerHighest : cs.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? cs.onSurfaceVariant : cs.onPrimary,
        ),
      ),
    );
  }
}

class RecruitingSection extends StatelessWidget {
  final String title;
  final Widget child;

  const RecruitingSection({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class OptionalPhotoPicker extends StatelessWidget {
  const OptionalPhotoPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진 선택 UI 미리보기입니다.')));
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.add_photo_alternate_rounded, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '사진 추가',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '선택 사항 · 경기장 사진이나 팀 이미지를 넣을 수 있어요.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
