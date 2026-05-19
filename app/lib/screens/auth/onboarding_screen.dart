import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/app_toast.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // 종목·등급
  final Map<Sport, String?> _selectedGrade = {
    Sport.tennis: null,
    Sport.futsal: null,
  };
  Sport _primarySport = Sport.tennis;

  // 권역 (테니스 한정, 선택)
  String? _regionCode;

  // Multi-org (테니스 한정, 다중)
  final List<_OrgDraft> _orgs = [];
  String? _primaryOrg;

  bool _busy = false;
  String? _error;

  bool get _canSubmit =>
      _selectedGrade.values.any((v) => v != null) &&
      _selectedGrade[_primarySport] != null;

  bool get _tennisRegistered => _selectedGrade[Sport.tennis] != null;

  // ───────────────────────────────────────────────────
  // org 추가/삭제/수정
  // ───────────────────────────────────────────────────
  Future<void> _addOrg() async {
    final used = _orgs.map((o) => o.org).toSet();
    final available =
        tennisOrgs.where((o) => !used.contains(o)).toList(growable: false);
    if (available.isEmpty) {
      AppToast.show(context, '등록할 수 있는 협회를 모두 추가했어요',
          kind: AppToastKind.info);
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '협회 선택',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final org = available[i];
                  return ListTile(
                    title: Text(tennisOrgLabel(org)),
                    onTap: () => Navigator.of(c).pop(org),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        _orgs.add(_OrgDraft(org: picked));
        _primaryOrg ??= picked;
      });
    }
  }

  void _removeOrg(String org) {
    setState(() {
      _orgs.removeWhere((o) => o.org == org);
      if (_primaryOrg == org) {
        _primaryOrg = _orgs.isEmpty ? null : _orgs.first.org;
      }
    });
  }

  void _setPrimaryOrg(String org) {
    setState(() => _primaryOrg = org);
  }

  // ───────────────────────────────────────────────────
  // submit
  // ───────────────────────────────────────────────────
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);

      // 1) user_sports
      final sports = <UserSport>[];
      for (final s in Sport.values) {
        final grade = _selectedGrade[s];
        if (grade == null) continue;
        sports.add(UserSport(
          sport: sportToString(s),
          grade: grade,
          isPrimary: s == _primarySport,
        ));
      }
      await api.saveUserSports(sports);

      // 2) user_tennis_orgs (테니스 등록자만)
      if (_tennisRegistered && _orgs.isNotEmpty) {
        final orgRows = _orgs.map((o) {
          return UserTennisOrg(
            org: o.org,
            divisionLocal: o.divisionLocal.text.trim().isEmpty
                ? null
                : o.divisionLocal.text.trim(),
            score: double.tryParse(o.score.text.trim()),
            regionCode: _regionCode,
            isPrimary: o.org == _primaryOrg,
          );
        }).toList();
        await api.saveTennisOrgs(orgRows);
      }

      ref.invalidate(userSportsProvider);
      ref.invalidate(userTennisOrgsProvider);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final o in _orgs) {
      o.divisionLocal.dispose();
      o.score.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────────────────────────────
  // build
  // ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('종목·등급 등록')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    '활동하시는 종목과 등급을 알려주세요.\n등록한 등급으로 출전 가능한 대회만 자동으로 보여드립니다.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // 종목·등급 카드
                  _buildSportCard(Sport.tennis),
                  const SizedBox(height: AppSpacing.md),
                  _buildSportCard(Sport.futsal),

                  // 권역 선택 (테니스 등록 시)
                  if (_tennisRegistered) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildRegionCard(),
                  ],

                  // Multi-org 협회 등록 (테니스 등록 시)
                  if (_tennisRegistered) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildOrgsSection(),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      variant: AppCardVariant.outlined,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: cs.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: tt.bodyMedium?.copyWith(color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.huge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppPrimaryButton(
                label: '시작하기',
                onPressed: _canSubmit && !_busy ? _submit : null,
                loading: _busy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────
  // sub-widgets
  // ───────────────────────────────────────────────────
  Widget _buildSportCard(Sport sport) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grades = gradesFor(sport);
    final selected = _selectedGrade[sport];
    final accent = AppSportColors.forSport(sportToString(sport));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  sport == Sport.tennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(sportLabel(sport), style: tt.titleLarge),
              const Spacer(),
              if (selected != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<Sport>(
                      // ignore: deprecated_member_use
                      groupValue: _primarySport,
                      value: sport,
                      // ignore: deprecated_member_use
                      onChanged: (v) =>
                          setState(() => _primarySport = v ?? sport),
                    ),
                    Text(
                      '앱 기본 종목 (대회·클럽·룰북 필터에 사용됩니다)',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppChip(
                label: '등록 안 함',
                selected: selected == null,
                leadingIcon: selected == null ? Icons.check_rounded : null,
                onTap: () => setState(() => _selectedGrade[sport] = null),
              ),
              for (final g in grades)
                AppChip(
                  label: gradeLabel(g),
                  selected: selected == g,
                  leadingIcon: selected == g ? Icons.check_rounded : null,
                  onTap: () => setState(() => _selectedGrade[sport] = g),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegionCard() {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주 활동 권역', style: tt.titleLarge),
          const SizedBox(height: 4),
          Text(
            '대회·동호회 자동 매칭에 사용해요. (선택)',
            style: tt.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final code in regionCodes)
                AppChip(
                  label: regionLabel(code),
                  selected: _regionCode == code,
                  onTap: () => setState(() {
                    _regionCode = (_regionCode == code) ? null : code;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrgsSection() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              Text('테니스 협회 등록', style: tt.titleLarge),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '(선택, 다중)',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'KATA·KATO·광주협회 등 여러 협회에 등록한 경우 협회별 등급을 따로 입력하세요.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final o in _orgs) ...[
          _buildOrgCard(o),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          variant: AppCardVariant.outlined,
          onTap: _addOrg,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('협회 추가', style: tt.labelLarge?.copyWith(color: cs.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrgCard(_OrgDraft draft) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPrimary = _primaryOrg == draft.org;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tennisOrgLabel(draft.org), style: tt.titleMedium),
              ),
              IconButton(
                onPressed: () => _removeOrg(draft.org),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                tooltip: '삭제',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.divisionLocal,
            decoration: const InputDecoration(
              labelText: '부서·등급 (자유 입력)',
              hintText: '예: 챌린저부 / 골드부 / 4부',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.score,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '점수 (선택, 0.0 ~ 10.0)',
              hintText: '예: 5.0',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Radio<String>(
                // ignore: deprecated_member_use
                groupValue: _primaryOrg,
                value: draft.org,
                // ignore: deprecated_member_use
                onChanged: (_) => _setPrimaryOrg(draft.org),
              ),
              Text(
                '주 협회',
                style: tt.labelMedium?.copyWith(
                  color: isPrimary ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrgDraft {
  final String org;
  final TextEditingController divisionLocal = TextEditingController();
  final TextEditingController score = TextEditingController();

  _OrgDraft({required this.org});
}
