import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/allround_logo.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _nickname = TextEditingController();
  int _step = 0;
  bool _nicknameReady = false;

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

  bool get _canAdvance => switch (_step) {
        0 => _nickname.text.trim().length >= 2,
        1 => _regionCode != null,
        _ => _canSubmit,
      };

  void _prepareNickname() {
    if (_nicknameReady) return;
    final user = ref.read(currentUserProvider);
    final metadataName = user?.userMetadata?['display_name'];
    _nickname.text = metadataName is String && metadataName.trim().isNotEmpty
        ? metadataName.trim()
        : (user?.email?.split('@').first ?? '');
    _nicknameReady = true;
  }

  void _selectGrade(Sport sport, String? grade) {
    setState(() {
      _selectedGrade[sport] = grade;
      if (grade != null && _selectedGrade[_primarySport] == null) {
        _primarySport = sport;
      }
      if (grade == null && _primarySport == sport) {
        _primarySport = _selectedGrade.entries
                .where((entry) => entry.value != null)
                .map((entry) => entry.key)
                .firstOrNull ??
            sport;
      }
    });
  }

  // ───────────────────────────────────────────────────
  // org 추가/삭제/수정
  // ───────────────────────────────────────────────────
  Future<void> _addOrg() async {
    final used = _orgs.map((o) => o.org).toSet();
    final available =
        tennisOrgs.where((o) => !used.contains(o)).toList(growable: false);
    if (available.isEmpty) {
      AppToast.show(context, '등록할 수 있는 협회를 모두 추가했어요', kind: AppToastKind.info);
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
                child: Text('협회 선택', style: Theme.of(c).textTheme.titleLarge),
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
    if (AppConfig.userDesignPreview) {
      context.go('/');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);

      await api.saveDisplayName(_nickname.text.trim());

      // 1) user_sports
      final sports = <UserSport>[];
      for (final s in Sport.values) {
        final grade = _selectedGrade[s];
        if (grade == null) continue;
        sports.add(
          UserSport(
            sport: sportToString(s),
            grade: grade,
            isPrimary: s == _primarySport,
          ),
        );
      }
      await api.saveUserSports(sports);

      // 2) user_tennis_orgs (테니스 등록자만)
      if (_tennisRegistered && _orgs.isNotEmpty) {
        final orgRows = _orgs.map((o) {
          return UserTennisOrg(
            org: o.org,
            division: o.divisionLocal.text.trim().isEmpty
                ? 'default'
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

  void _handleBack() {
    if (_step > 0) {
      setState(() => _step--);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/more');
  }

  @override
  void dispose() {
    _nickname.dispose();
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
    _prepareNickname();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingTopBar(
              step: _step,
              onBack: _handleBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.huge,
                ),
                children: [
                  _StepProgress(current: _step),
                  const SizedBox(height: AppSpacing.xl),
                  if (_step == 0) _buildNicknameStep(cs, tt),
                  if (_step == 1) _buildRegionStep(cs, tt),
                  if (_step == 2) ...[
                    _buildSportStepHeader(cs, tt),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSportCard(Sport.futsal),
                    const SizedBox(height: AppSpacing.md),
                    _buildSportCard(Sport.tennis),
                    if (_tennisRegistered) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _buildOrgsSection(),
                    ],
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
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
                boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
              ),
              child: SafeArea(
                top: false,
                child: AppPrimaryButton(
                  label: _step == 2 ? '시작하기' : '다음',
                  icon: _step == 2
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _canAdvance && !_busy
                      ? () {
                          if (_step < 2) {
                            setState(() => _step++);
                          } else {
                            _submit();
                          }
                        }
                      : null,
                  loading: _busy,
                ),
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
  Widget _buildNicknameStep(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnboardingHeroPanel(
          title: '내 운동 생활을\n가볍게 시작해요',
          subtitle: '닉네임과 활동 조건만 정하면 대회, 클럽, 룰북을 맞춤으로 볼 수 있어요.',
          icon: Icons.sports_soccer_rounded,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          '프로필 이름',
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '앱 안에서 표시될 닉네임이에요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.secondary.withValues(alpha: 0.18),
                width: 4,
              ),
            ),
            child: Icon(Icons.person_rounded, size: 48, color: cs.secondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _nickname,
          maxLength: 10,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '닉네임을 입력하세요',
            prefixIcon: Icon(Icons.badge_outlined),
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '원하시면 닉네임을 수정할 수 있어요.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildRegionStep(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주로 활동하는\n지역을 알려주세요',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.22,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '근처 대회와 클럽을 추천해드릴게요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _SportHintCard(
          icon: Icons.location_on_rounded,
          title: '지역 기반 추천',
          description: '선택한 권역은 대회·클럽 추천과 기본 필터에 사용됩니다.',
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 2.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final code in regionCodes)
              _RegionOption(
                label: regionLabel(code),
                selected: _regionCode == code,
                onTap: () => setState(() => _regionCode = code),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSportStepHeader(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '어떤 운동을\n주로 하세요?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.22,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_regionCode == null ? '' : '${regionLabel(_regionCode!)}에서 '}활동할 종목과 경력을 선택하세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SportHintCard(
          icon: Icons.auto_awesome_rounded,
          title: '맞춤 추천 준비',
          description: '선택한 종목과 등급으로 대회, 클럽, 룰북 추천을 정리합니다.',
        ),
      ],
    );
  }

  Widget _buildSportCard(Sport sport) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grades = gradesFor(sport);
    final selected = _selectedGrade[sport];
    final accent = AppSportColors.forSport(sportToString(sport));

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  sport == Sport.tennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                sportLabel(sport),
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
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
                      '기본 종목',
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
                onTap: () => _selectGrade(sport, null),
              ),
              for (final g in grades)
                AppChip(
                  label: gradeLabel(g),
                  selected: selected == g,
                  leadingIcon: selected == g ? Icons.check_rounded : null,
                  selectedColor: accent.withValues(alpha: 0.18),
                  onTap: () => _selectGrade(sport, g),
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
          Text('출전 부서 선택', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: tennisDivisions.where((d) => d.org == draft.org).map((d) {
              final selected = draft.selectedDivisionCodes.contains(d.code);
              return FilterChip(
                label: Text(d.label),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      draft.selectedDivisionCodes.add(d.code);
                    } else {
                      draft.selectedDivisionCodes.remove(d.code);
                    }
                    draft.divisionLocal.text = tennisDivisions
                        .where((td) =>
                            draft.selectedDivisionCodes.contains(td.code))
                        .map((td) => td.label)
                        .join(' · ');
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.score,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const labels = ['프로필', '지역', '종목'];

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (var index = 0; index < 3; index++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: index == current
                      ? cs.primaryContainer
                      : Colors.transparent,
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            index <= current ? cs.primary : cs.outlineVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: tt.labelSmall?.copyWith(
                          color: index <= current ? cs.onPrimary : cs.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(
                          color: index == current
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index < 2) const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({
    required this.step,
    required this.onBack,
  });

  final int step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final titles = ['프로필 설정', '활동 지역', '종목·경력'];

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(onBack == null
                ? Icons.close_rounded
                : Icons.arrow_back_rounded),
            tooltip: onBack == null ? '닫기' : '이전',
          ),
          const SizedBox(width: AppSpacing.sm),
          const AllRoundLogo(fontSize: 18),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 18, color: cs.outlineVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              titles[step],
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingHeroPanel extends StatelessWidget {
  const _OnboardingHeroPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary,
            const Color(0xFF1E40AF),
            AppSportColors.futsal,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.elevatedFor(Theme.of(context).brightness),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(
              Icons.sports_tennis_rounded,
              size: 112,
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            right: 54,
            top: 40,
            child: Icon(
              Icons.sports_soccer_rounded,
              size: 72,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                style: tt.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.22,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: tt.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SportHintCard extends StatelessWidget {
  const _SportHintCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
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

class _RegionOption extends StatelessWidget {
  const _RegionOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected ? cs.primary : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: tt.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrgDraft {
  final String org;
  final TextEditingController divisionLocal = TextEditingController();
  final TextEditingController score = TextEditingController();
  final Set<String> selectedDivisionCodes = {};

  _OrgDraft({required this.org});
}
