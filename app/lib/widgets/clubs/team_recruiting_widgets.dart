import 'package:flutter/material.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import 'club_tiles.dart';

class RecruitingPostPreview {
  final String id;
  final String sport;
  final String clubName;
  final String title;
  final String region;
  final String place;
  final String schedule;
  final String grade;
  final String gender;
  final String age;
  final int fieldCount;
  final int keeperCount;
  final int totalCount;
  final String cost;
  final bool isClosed;
  final DateTime? closedAt;

  const RecruitingPostPreview({
    required this.id,
    required this.sport,
    required this.clubName,
    required this.title,
    required this.region,
    required this.place,
    required this.schedule,
    required this.grade,
    required this.gender,
    required this.age,
    required this.fieldCount,
    required this.keeperCount,
    required this.totalCount,
    required this.cost,
    this.isClosed = false,
    this.closedAt,
  });

  RecruitingPostPreview copyWith({
    bool? isClosed,
    DateTime? closedAt,
  }) {
    return RecruitingPostPreview(
      id: id,
      sport: sport,
      clubName: clubName,
      title: title,
      region: region,
      place: place,
      schedule: schedule,
      grade: grade,
      gender: gender,
      age: age,
      fieldCount: fieldCount,
      keeperCount: keeperCount,
      totalCount: totalCount,
      cost: cost,
      isClosed: isClosed ?? this.isClosed,
      closedAt: closedAt ?? this.closedAt,
    );
  }

  String get countLabel {
    if (sport == 'futsal') {
      return '필드 $fieldCount명 · 키퍼 $keeperCount명';
    }
    return '$totalCount명';
  }
}

class TeamRecruitingBoard extends StatelessWidget {
  final List<RecruitingPostPreview> posts;
  final bool showOpenOnly;
  final bool canManage;
  final ValueChanged<bool> onShowOpenOnlyChanged;
  final ValueChanged<RecruitingPostPreview> onClosePost;

  const TeamRecruitingBoard({
    super.key,
    required this.posts,
    required this.showOpenOnly,
    required this.canManage,
    required this.onShowOpenOnlyChanged,
    required this.onClosePost,
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
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
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
          if (posts.isEmpty)
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
            for (final post in posts.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TeamRecruitingPostCard(
                  post: post,
                  canManage: canManage,
                  onClose: () => onClosePost(post),
                ),
              ),
          Text(
            '마감된 글은 일정 시간이 지나면 목록에서 내려가는 흐름으로 설계했습니다.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

  const TeamRecruitingPostCard({
    super.key,
    required this.post,
    required this.canManage,
    required this.onClose,
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
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

  const MiniInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

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

class TeamRecruitingDraftSheet extends StatefulWidget {
  final List<Club> managedClubs;

  const TeamRecruitingDraftSheet({super.key, required this.managedClubs});

  @override
  State<TeamRecruitingDraftSheet> createState() =>
      _TeamRecruitingDraftSheetState();
}

class _TeamRecruitingDraftSheetState extends State<TeamRecruitingDraftSheet> {
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

  Club get _selectedClub =>
      widget.managedClubs.firstWhere((club) => club.id == _selectedClubId);

  bool get _isFutsal => _selectedClub.sport == 'futsal';

  List<String> get _gradeOptions => _isFutsal ? _futsalGrades : _tennisGrades;

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
              DropdownButtonFormField<String>(
                initialValue: _selectedClubId,
                decoration: const InputDecoration(
                  labelText: '모집할 클럽',
                  prefixIcon: Icon(Icons.groups_rounded),
                ),
                items: [
                  for (final club in widget.managedClubs)
                    DropdownMenuItem(
                      value: club.id,
                      child: Text(club.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedClubId = value;
                    _grade = _gradeOptions.first;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              RecruitingPreviewClub(club: _selectedClub),
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
              const RecruitingSection(
                title: '운동 정보',
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
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
                            decoration: InputDecoration(
                              labelText: '날짜',
                              hintText: '6/22 (토)',
                              prefixIcon: Icon(Icons.calendar_month_rounded),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
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
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '비용',
                        hintText: '예: 10,000원 또는 무료',
                        prefixIcon: Icon(Icons.payments_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const RecruitingSection(
                title: '상세 내용',
                child: TextField(
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '필요 포지션, 준비물, 경기 수준, 연락 방식 등을 적어주세요.',
                    alignLabelWithHint: true,
                    labelText: '기타 내용',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OptionalPhotoPicker(),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('팀원모집 글쓰기 UI 미리보기입니다.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('모집글 올리기'),
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

class RecruitingPreviewClub extends StatelessWidget {
  final Club club;

  const RecruitingPreviewClub({super.key, required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          SimpleClubAvatar(club: club, size: 54),
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
                  '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'} · 운영진',
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

  const StepperButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 선택 UI 미리보기입니다.')),
        );
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
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
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
