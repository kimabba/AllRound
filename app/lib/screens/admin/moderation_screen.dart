import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/moderation.dart';
import '../../state/providers.dart';

class ModerationScreen extends ConsumerStatefulWidget {
  const ModerationScreen({super.key});

  @override
  ConsumerState<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends ConsumerState<ModerationScreen> {
  String _status = 'pending';
  late Future<List<UgcReport>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiProvider).adminUgcReports(status: _status);
  }

  void _changeStatus(String status) {
    setState(() {
      _status = status;
      _reload();
    });
  }

  Future<void> _open(UgcReport report) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReportDetailDialog(report: report),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('신고 · 제재 관리'),
        actions: [
          IconButton(
            onPressed: () => setState(_reload),
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('대기')),
                ButtonSegment(value: 'reviewing', label: Text('검토 중')),
                ButtonSegment(value: 'actioned', label: Text('처리')),
                ButtonSegment(value: 'dismissed', label: Text('기각')),
              ],
              selected: {_status},
              onSelectionChanged: (value) => _changeStatus(value.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<UgcReport>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('신고 목록 오류: ${snapshot.error}'));
                }
                final reports = snapshot.data ?? const [];
                if (reports.isEmpty) {
                  return const Center(child: Text('해당 상태의 신고가 없습니다.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(_reasonIcon(report.reason)),
                        ),
                        title: Text(
                          '${report.reason.label} · ${_targetLabel(report.targetType)}',
                        ),
                        subtitle: Text(
                          '신고자 ${report.reporterName ?? '사용자'} → '
                          '${report.reportedUserName ?? '확인 필요'}\n'
                          '${_dateTime(report.createdAt)}'
                          '${report.evidencePaths.isEmpty ? '' : ' · 캡처 ${report.evidencePaths.length}장'}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(report),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportDetailDialog extends ConsumerStatefulWidget {
  const _ReportDetailDialog({required this.report});

  final UgcReport report;

  @override
  ConsumerState<_ReportDetailDialog> createState() =>
      _ReportDetailDialogState();
}

class _ReportDetailDialogState extends ConsumerState<_ReportDetailDialog> {
  bool _busy = false;

  Future<void> _dismiss() async {
    final note = await _requestNote('신고 기각', '기각 사유');
    if (note == null) return;
    await _resolve(
      dismiss: true,
      deleteContent: false,
      note: note,
    );
  }

  Future<void> _takeAction() async {
    final decision = await showDialog<_ModerationDecision>(
      context: context,
      builder: (_) => _ModerationDecisionDialog(
        allowPenalty: widget.report.reportedUserId != null,
        allowDelete: const {
          'club_post',
          'club_comment',
          'club_event',
        }.contains(widget.report.targetType),
      ),
    );
    if (decision == null) return;
    await _resolve(
      dismiss: false,
      deleteContent: decision.deleteContent,
      penaltyType: decision.penaltyType,
      durationDays: decision.durationDays,
      note: decision.note,
    );
  }

  Future<void> _resolve({
    required bool dismiss,
    required bool deleteContent,
    UgcPenaltyType? penaltyType,
    int? durationDays,
    required String note,
  }) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).resolveUgcReport(
            reportId: widget.report.id,
            dismiss: dismiss,
            deleteContent: deleteContent,
            penaltyType: penaltyType,
            durationDays: durationDays,
            note: note,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _requestNote(String title, String hint) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
    controller.dispose();
    return note;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final prettySnapshot =
        const JsonEncoder.withIndent('  ').convert(report.snapshot);
    return AlertDialog(
      title: Text('${report.reason.label} 신고'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: '대상', value: _targetLabel(report.targetType)),
              _InfoRow(label: '신고자', value: report.reporterName ?? '사용자'),
              _InfoRow(
                label: '신고 대상',
                value: report.reportedUserName ?? '확인 필요',
              ),
              _InfoRow(label: '신고 시각', value: _dateTime(report.createdAt)),
              if (report.details?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                const Text('상황 설명',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(report.details!),
              ],
              if (report.evidencePaths.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('신고 캡처',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final path in report.evidencePaths)
                      _EvidencePreview(path: path),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '서버 보존 원문 · 주변 대화',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SelectableText(prettySnapshot),
              ),
              if (report.reportedUserId != null) ...[
                const SizedBox(height: 16),
                _ActivePenalties(userId: report.reportedUserId!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
        if (report.isOpen) ...[
          OutlinedButton(
            onPressed: _busy ? null : _dismiss,
            child: const Text('기각'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _takeAction,
            icon: const Icon(Icons.gavel_rounded),
            label: Text(_busy ? '처리 중…' : '삭제 · 제재 처리'),
          ),
        ],
      ],
    );
  }
}

class _ModerationDecisionDialog extends StatefulWidget {
  const _ModerationDecisionDialog({
    required this.allowPenalty,
    required this.allowDelete,
  });

  final bool allowPenalty;
  final bool allowDelete;

  @override
  State<_ModerationDecisionDialog> createState() =>
      _ModerationDecisionDialogState();
}

class _ModerationDecisionDialogState extends State<_ModerationDecisionDialog> {
  final _note = TextEditingController();
  late bool _deleteContent;
  UgcPenaltyType? _penaltyType;
  int? _durationDays = 7;

  @override
  void initState() {
    super.initState();
    _deleteContent = widget.allowDelete;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('관리자 처리'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _deleteContent,
              onChanged: widget.allowDelete
                  ? (value) => setState(() => _deleteContent = value)
                  : null,
              title: const Text('신고된 콘텐츠 삭제'),
            ),
            DropdownButtonFormField<UgcPenaltyType?>(
              initialValue: _penaltyType,
              decoration: const InputDecoration(labelText: '사용자 제재'),
              items: [
                const DropdownMenuItem(value: null, child: Text('제재 없음')),
                for (final type in UgcPenaltyType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: widget.allowPenalty
                  ? (value) => setState(() => _penaltyType = value)
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _durationDays,
              decoration: const InputDecoration(labelText: '제재 기간'),
              items: const [
                DropdownMenuItem(value: 7, child: Text('7일')),
                DropdownMenuItem(value: 30, child: Text('30일')),
                DropdownMenuItem(value: null, child: Text('영구')),
              ],
              onChanged: _penaltyType == null
                  ? null
                  : (value) => setState(() => _durationDays = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '처리 사유 및 근거 *',
                hintText: '운영 정책 위반 내용을 기록하세요.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final note = _note.text.trim();
            if (note.isEmpty) return;
            Navigator.pop(
              context,
              _ModerationDecision(
                deleteContent: _deleteContent,
                penaltyType: _penaltyType,
                durationDays: _penaltyType == null ? null : _durationDays,
                note: note,
              ),
            );
          },
          child: const Text('처리 확정'),
        ),
      ],
    );
  }
}

class _ActivePenalties extends ConsumerStatefulWidget {
  const _ActivePenalties({required this.userId});

  final String userId;

  @override
  ConsumerState<_ActivePenalties> createState() => _ActivePenaltiesState();
}

class _ActivePenaltiesState extends ConsumerState<_ActivePenalties> {
  late Future<List<UserPenalty>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiProvider).adminUserPenalties(widget.userId);
  }

  Future<void> _revoke(UserPenalty penalty) async {
    await ref.read(apiProvider).revokeUserPenalty(penalty.id, '관리자 수동 해제');
    if (mounted) {
      setState(() {
        _future = ref.read(apiProvider).adminUserPenalties(widget.userId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UserPenalty>>(
      future: _future,
      builder: (context, snapshot) {
        final penalties = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (penalties.isEmpty) return const Text('현재 제재: 없음');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('현재 제재', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final penalty in penalties)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${penalty.type.label} · ${penalty.periodLabel}'),
                subtitle: Text(penalty.reason),
                trailing: TextButton(
                  onPressed: () => _revoke(penalty),
                  child: const Text('해제'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EvidencePreview extends ConsumerWidget {
  const _EvidencePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.read(apiProvider).reportEvidenceUrl(path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 180,
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(child: Image.network(snapshot.data!)),
          ),
          child: Image.network(
            snapshot.data!,
            width: 180,
            height: 140,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 180,
              height: 140,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _ModerationDecision {
  const _ModerationDecision({
    required this.deleteContent,
    required this.penaltyType,
    required this.durationDays,
    required this.note,
  });

  final bool deleteContent;
  final UgcPenaltyType? penaltyType;
  final int? durationDays;
  final String note;
}

IconData _reasonIcon(UgcReportReason reason) => switch (reason) {
      UgcReportReason.spam => Icons.campaign_outlined,
      UgcReportReason.privacy => Icons.privacy_tip_outlined,
      UgcReportReason.violence => Icons.warning_amber_rounded,
      _ => Icons.flag_outlined,
    };

String _targetLabel(String value) => switch (value) {
      'club_post' => '클럽 게시글',
      'club_comment' => '클럽 댓글',
      'club_event' => '클럽 모임',
      'club' => '클럽',
      'user' => '사용자',
      'ai_message' => 'AI 답변',
      _ => value,
    };

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}.${local.month}.${local.day} $hour:$minute';
}
