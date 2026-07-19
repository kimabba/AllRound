import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/format_review.dart';
import '../../services/api.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

final formatReviewQueueProvider =
    FutureProvider.autoDispose<List<FormatReviewItem>>((ref) async {
  return ref.read(apiProvider).formatReviewQueue();
});

abstract interface class FormatReviewActions {
  Future<bool> approve(FormatReviewItem item);

  Future<bool> reject(FormatReviewItem item, String reason);
}

class _ApiFormatReviewActions implements FormatReviewActions {
  const _ApiFormatReviewActions(this.api);

  final ApiService api;

  @override
  Future<bool> approve(FormatReviewItem item) => api.applyStaged(item);

  @override
  Future<bool> reject(FormatReviewItem item, String reason) {
    return api.rejectStaged(item, reason);
  }
}

final formatReviewActionsProvider = Provider<FormatReviewActions>((ref) {
  return _ApiFormatReviewActions(ref.read(apiProvider));
});

class FormatReviewScreen extends ConsumerWidget {
  const FormatReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(formatReviewQueueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('요강 검수')),
      body: queue.when(
        loading: () => const _ReviewLoading(),
        error: (_, __) => _ReviewStateMessage(
          icon: Icons.cloud_off_outlined,
          title: '검수 목록을 불러오지 못했습니다',
          description: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(formatReviewQueueProvider),
        ),
        data: (items) => items.isEmpty
            ? const _ReviewStateMessage(
                icon: Icons.task_alt_outlined,
                title: '검수할 요강이 없습니다',
                description: '새 검수 항목이 생기면 이곳에 표시됩니다.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxl,
                  AppSpacing.xl,
                  AppSpacing.xxxl,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xxl),
                itemBuilder: (_, index) => _ReviewPanel(item: items[index]),
              ),
      ),
    );
  }
}

class _ReviewPanel extends ConsumerStatefulWidget {
  const _ReviewPanel({required this.item});

  final FormatReviewItem item;

  @override
  ConsumerState<_ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends ConsumerState<_ReviewPanel> {
  _ReviewOperation? _operation;

  bool get _busy => _operation != null;

  Future<void> _approve() async {
    await _run(
      operation: _ReviewOperation.approve,
      successMessage: '요강을 승인했습니다.',
      action: () => ref.read(formatReviewActionsProvider).approve(widget.item),
    );
  }

  Future<void> _reject() async {
    final reason = await _requestRejectionReason();
    if (reason == null || !mounted) return;
    await _run(
      operation: _ReviewOperation.reject,
      successMessage: '요강을 반려했습니다.',
      action: () =>
          ref.read(formatReviewActionsProvider).reject(widget.item, reason),
    );
  }

  Future<void> _run({
    required _ReviewOperation operation,
    required String successMessage,
    required Future<bool> Function() action,
  }) async {
    if (_busy) return;
    setState(() => _operation = operation);
    try {
      final applied = await action();
      if (!mounted) return;
      if (!applied) {
        _showMessage('원문이 변경됐습니다. 목록을 새로 불러온 뒤 다시 확인해 주세요.');
        ref.invalidate(formatReviewQueueProvider);
        return;
      }
      _showMessage(successMessage);
      ref.invalidate(formatReviewQueueProvider);
    } catch (_) {
      if (mounted) {
        _showMessage('처리하지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<String?> _requestRejectionReason() async {
    var input = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('요강 반려'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => input = value,
          maxLength: 200,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '반려 사유',
            hintText: '다시 확인할 내용을 적어 주세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: const Text('반려 확정'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSource() async {
    final sourceUrl = widget.item.sourceUrl;
    if (sourceUrl == null) return;
    final opened = await launchUrl(sourceUrl);
    if (!opened && mounted) {
      _showMessage('원문 링크를 열지 못했습니다.');
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final staged = item.staged;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: AppSpacing.cardInner,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (item.sourceUrl != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _busy ? null : _openSource,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('원문 공고 보기'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.touchTarget),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.lg),
            if (staged != null)
              _StagedContent(staged: staged)
            else
              _ValidationFailure(flags: item.flags),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.control),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                  child: _operation == _ReviewOperation.reject
                      ? const _ButtonProgress()
                      : const Text('반려'),
                ),
                if (staged != null)
                  FilledButton(
                    onPressed: _busy ? null : _approve,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSizes.control),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                    child: _operation == _ReviewOperation.approve
                        ? const _ButtonProgress()
                        : const Text('승인'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StagedContent extends StatelessWidget {
  const _StagedContent({required this.staged});

  final StagedRegulation staged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final hasContent = staged.fields.isNotEmpty ||
        staged.description != null ||
        staged.notes.isNotEmpty ||
        staged.body != null ||
        staged.prize != null ||
        staged.format != null;

    if (!hasContent) {
      return Text(
        'AI가 제안한 내용이 비어 있습니다. 원문을 확인해 주세요.',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI 정형화 제안', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        ...staged.fields.map(
          (field) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${field.label}  ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: field.value),
                ],
              ),
              style: textTheme.bodyMedium,
            ),
          ),
        ),
        if (staged.format != null)
          _LabeledParagraph(label: '진행 방식', value: staged.format!),
        if (staged.prize != null)
          _LabeledParagraph(label: '시상', value: staged.prize!),
        if (staged.description != null)
          _LabeledParagraph(label: '요약', value: staged.description!),
        if (staged.notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('유의 사항', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ...staged.notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• $note', style: textTheme.bodyMedium),
            ),
          ),
        ],
        if (staged.body != null)
          _LabeledParagraph(label: '상세 요강', value: staged.body!),
      ],
    );
  }
}

class _LabeledParagraph extends StatelessWidget {
  const _LabeledParagraph({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ValidationFailure extends StatelessWidget {
  const _ValidationFailure({required this.flags});

  final List<FormatReviewFlag> flags;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.35)),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Padding(
        padding: AppSpacing.cardInner,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '자동 검증을 통과하지 못했습니다',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '원문을 확인한 뒤 반려해 다시 처리해 주세요.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ...flags.map((flag) {
                final masked = flag.masked == null ? '' : ' (${flag.masked})';
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '${flag.field} · ${flag.code}$masked',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewLoading extends StatelessWidget {
  const _ReviewLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: AppSpacing.cardInner,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('검수 목록을 불러오는 중입니다'),
          ],
        ),
      ),
    );
  }
}

class _ReviewStateMessage extends StatelessWidget {
  const _ReviewStateMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.control),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

enum _ReviewOperation { approve, reject }
