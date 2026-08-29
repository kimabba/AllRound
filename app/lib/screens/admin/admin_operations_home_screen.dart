import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';
import 'admin_shell.dart';

class AdminOperationsHomeScreen extends StatelessWidget {
  const AdminOperationsHomeScreen({super.key});

  static const double _contentMaxWidth = 1120;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: adminShellLeading(context),
        title: const Text('운영 홈'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('운영 작업의 시작점', style: textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '검수부터 공개, 수집 확인까지 흐름대로 이동하고 다른 운영 도구도 한곳에서 찾을 수 있습니다.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const _TournamentWorkflowPanel(),
                  const SizedBox(height: AppSpacing.xxxl),
                  Text('운영 영역', style: textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '각 영역의 실제 상태와 처리 결과는 해당 관리 화면에서 확인합니다.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _OperationsAreaPanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentWorkflowPanel extends StatelessWidget {
  const _TournamentWorkflowPanel();

  static const _steps = <_WorkflowStepData>[
    _WorkflowStepData(
      keyName: 'admin-home-drafts',
      title: '제보 · Draft 검수',
      description: '사용자 제보와 검수 대기 대회를 확인해 승인하거나 반려합니다.',
      path: '/admin/drafts',
      icon: Icons.fact_check_rounded,
    ),
    _WorkflowStepData(
      keyName: 'admin-home-format-review',
      title: '요강 정형화 검수',
      description: '원문과 정리된 요강을 비교하고 적용 여부를 결정합니다.',
      path: '/admin/format-review',
      icon: Icons.rule_folder_rounded,
    ),
    _WorkflowStepData(
      keyName: 'admin-home-tournaments',
      title: '공개 대회 관리',
      description: '공개 상태와 등록 정보를 확인하고 필요한 대회를 편집합니다.',
      path: '/admin/tournaments',
      icon: Icons.event_note_rounded,
    ),
    _WorkflowStepData(
      keyName: 'admin-home-crawl-status',
      title: '수집 상태',
      description: '최근 크롤 실행 기록과 오류를 확인합니다.',
      path: '/admin/crawl-status',
      icon: Icons.monitor_heart_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppSpacing.cardInner,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                Text('대회 운영', style: textTheme.titleLarge),
                TextButton.icon(
                  onPressed: () => context.go('/admin/sources'),
                  icon: const Icon(Icons.settings_input_antenna_rounded),
                  label: const Text('수집 소스 설정'),
                ),
              ],
            ),
          ),
          const Divider(),
          for (var index = 0; index < _steps.length; index++) ...[
            _WorkflowStep(index: index, data: _steps[index]),
            if (index != _steps.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.index, required this.data});

  final int index;
  final _WorkflowStepData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '${index + 1}단계 ${data.title}',
      child: InkWell(
        key: ValueKey(data.keyName),
        onTap: () => context.go(data.path),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.listRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: AppSizes.touchTarget,
                  height: AppSizes.touchTarget,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    data.icon,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              data.title,
                              style: textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        data.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationsAreaPanel extends StatelessWidget {
  const _OperationsAreaPanel();

  static const _areas = <_OperationsAreaData>[
    _OperationsAreaData(
      title: '지식베이스',
      description: '룰북 문서의 게시 상태와 임베딩 상태를 확인하고 문서를 편집합니다.',
      icon: Icons.menu_book_rounded,
      actions: [_AreaAction(label: '문서 관리', path: '/admin/kb')],
    ),
    _OperationsAreaData(
      title: '협회 · 랭킹',
      description: '현재는 선수 랭킹 연결 신청을 심사합니다. 협회·부서 사전 편집은 후속 범위입니다.',
      icon: Icons.workspace_premium_rounded,
      actions: [_AreaAction(label: '랭킹 연결 심사', path: '/admin/ranking-claims')],
    ),
    _OperationsAreaData(
      title: '클럽 · 커뮤니티',
      description: '클럽 개설 신청을 검수하고 사용자 신고와 제재 상태를 관리합니다.',
      icon: Icons.groups_rounded,
      actions: [
        _AreaAction(label: '클럽 승인', path: '/admin/clubs'),
        _AreaAction(label: '신고 · 제재', path: '/admin/reports'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          for (var index = 0; index < _areas.length; index++) ...[
            _OperationsAreaRow(data: _areas[index]),
            if (index != _areas.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _OperationsAreaRow extends StatelessWidget {
  const _OperationsAreaRow({required this.data});

  final _OperationsAreaData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: AppSpacing.cardInner,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(data.icon, size: 22, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title, style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      data.description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final action in data.actions)
                OutlinedButton(
                  key: ValueKey('admin-home-${action.path}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.touchTarget),
                  ),
                  onPressed: () => context.go(action.path),
                  child: Text(action.label),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppSpacing.md),
                Align(alignment: Alignment.centerLeft, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSpacing.xxl),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _WorkflowStepData {
  const _WorkflowStepData({
    required this.keyName,
    required this.title,
    required this.description,
    required this.path,
    required this.icon,
  });

  final String keyName;
  final String title;
  final String description;
  final String path;
  final IconData icon;
}

class _OperationsAreaData {
  const _OperationsAreaData({
    required this.title,
    required this.description,
    required this.icon,
    required this.actions,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<_AreaAction> actions;
}

class _AreaAction {
  const _AreaAction({required this.label, required this.path});

  final String label;
  final String path;
}
