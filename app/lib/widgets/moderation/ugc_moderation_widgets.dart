import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/moderation.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/club_image_upload.dart';

const _termsUrl =
    'https://kimabba.github.io/AllRound/legal/terms-of-service.html';

enum UgcActionKind { comment, clubJoin, community }

String ugcActionErrorMessage(Object error, {required String fallback}) {
  final text = error.toString();
  if (text.contains('UGC_CONTENT_BLOCKED')) {
    return '욕설·혐오·유해 표현이 포함되어 등록할 수 없습니다.';
  }
  if (text.contains('UGC_SPAM_BLOCKED')) {
    return '광고·도배 방지를 위해 링크는 2개까지만 등록할 수 있습니다.';
  }
  if (text.contains('UGC_TERMS_REQUIRED')) {
    return '커뮤니티 이용약관 동의가 필요합니다.';
  }
  if (text.contains('UGC_ACTION_RESTRICTED')) {
    return '커뮤니티 이용이 제한된 계정입니다.';
  }
  return fallback;
}

Future<bool> ensureUgcPermission(
  BuildContext context,
  WidgetRef ref,
  UgcActionKind action,
) async {
  try {
    var access = await ref.read(apiProvider).myUgcAccess();
    if (!access.termsAccepted) {
      if (!context.mounted) return false;
      final accepted = await _showUgcTermsDialog(context);
      if (!accepted || !context.mounted) return false;
      await ref.read(apiProvider).acceptCurrentUgcTerms();
      access = await ref.read(apiProvider).myUgcAccess();
    }

    UserPenalty? blockingPenalty;
    for (final penalty in access.penalties) {
      if (_blocksAction(penalty.type, action)) {
        blockingPenalty = penalty;
        break;
      }
    }
    final penalty = blockingPenalty;
    if (penalty != null && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('커뮤니티 이용이 제한됐습니다'),
          content: Text(
            '${penalty.type.label} 상태입니다.\n'
            '${penalty.periodLabel}\n\n'
            '사유: ${penalty.reason}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('커뮤니티 이용 권한을 확인하지 못했습니다.')),
      );
    }
    return false;
  }
}

bool _blocksAction(UgcPenaltyType type, UgcActionKind action) {
  if (type == UgcPenaltyType.communityRestriction) return true;
  return switch (action) {
    UgcActionKind.comment => type == UgcPenaltyType.commentRestriction,
    UgcActionKind.clubJoin => type == UgcPenaltyType.clubJoinRestriction,
    UgcActionKind.community => false,
  };
}

Future<bool> _showUgcTermsDialog(BuildContext context) async {
  var checked = false;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('커뮤니티 이용약관 동의'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '글·댓글·모임 등 커뮤니티 콘텐츠를 작성하려면 운영정책에 동의해야 합니다. '
              '욕설, 괴롭힘, 혐오, 성적 콘텐츠, 개인정보 노출, 광고·도배는 제한됩니다.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_termsUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('이용약관 전체 보기'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: (value) =>
                  setDialogState(() => checked = value ?? false),
              title: const Text('커뮤니티 이용약관에 동의합니다. (필수)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed:
                checked ? () => Navigator.pop(dialogContext, true) : null,
            child: const Text('동의하고 계속'),
          ),
        ],
      ),
    ),
  );
  return accepted == true;
}

Future<bool> showUgcReportSheet({
  required BuildContext context,
  required WidgetRef ref,
  required UgcTargetType targetType,
  required String targetId,
}) async {
  final reported = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _UgcReportSheet(
      targetType: targetType,
      targetId: targetId,
    ),
  );
  return reported == true;
}

Future<bool> confirmBlockUser({
  required BuildContext context,
  required WidgetRef ref,
  required String userId,
  required String displayName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('사용자 차단'),
      content: Text(
        '$displayName 님을 차단할까요?\n'
        '서로의 게시글·댓글·모임이 보이지 않으며 언제든 차단 관리에서 해제할 수 있습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('차단'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await ref.read(apiProvider).blockUser(userId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName 님을 차단했습니다.')),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자를 차단하지 못했습니다.')),
      );
    }
    return false;
  }
}

class _UgcReportSheet extends ConsumerStatefulWidget {
  const _UgcReportSheet({required this.targetType, required this.targetId});

  final UgcTargetType targetType;
  final String targetId;

  @override
  ConsumerState<_UgcReportSheet> createState() => _UgcReportSheetState();
}

class _UgcReportSheetState extends ConsumerState<_UgcReportSheet> {
  final _details = TextEditingController();
  final List<_EvidenceImage> _images = [];
  UgcReportReason _reason = UgcReportReason.abusiveLanguage;
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_images.length >= 3) return;
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (files.isEmpty) return;
    final next = <_EvidenceImage>[];
    try {
      for (final file in files.take(3 - _images.length)) {
        final image = await prepareClubImage(file);
        if (image.bytes.lengthInBytes > 5 * 1024 * 1024) {
          throw const ClubImagePreparationException(
            '신고 사진은 한 장당 5MB 이하여야 합니다.',
          );
        }
        next.add(
          _EvidenceImage(
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

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    final paths = <String>[];
    try {
      for (final image in _images) {
        paths.add(await api.uploadReportEvidence(
          bytes: image.bytes,
          extension: image.extension,
          contentType: image.contentType,
        ));
      }
      await api.createUgcReport(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _reason,
        details: _details.text,
        evidencePaths: paths,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('신고가 접수되었습니다. 관리자가 확인합니다.')),
      );
    } catch (error) {
      try {
        await api.deleteReportEvidence(paths);
      } catch (_) {
        // 신고 접수 실패 안내가 임시 파일 정리 오류에 가려지지 않게 한다.
      }
      if (!mounted) return;
      final message = error.toString().contains('REPORT_ALREADY_OPEN')
          ? '이미 접수되어 처리 중인 신고입니다.'
          : error.toString().contains('REPORT_RATE_LIMITED')
              ? '하루 신고 가능 횟수를 초과했습니다.'
              : '신고를 접수하지 못했습니다. 잠시 후 다시 시도해주세요.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          bottomInset + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '신고하기',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('신고 시 원문과 주변 대화가 자동으로 보존됩니다.'),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<UgcReportReason>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: '신고 사유'),
              items: [
                for (final reason in UgcReportReason.values)
                  DropdownMenuItem(value: reason, child: Text(reason.label)),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(
                        () => _reason = value ?? UgcReportReason.other,
                      ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _details,
              enabled: !_busy,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '상황 설명 (선택)',
                hintText: '언제 어떤 문제가 있었는지 알려주세요.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '상황 캡처 ${_images.length}/3',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _images.length >= 3 ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('사진 추가'),
                ),
              ],
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _images[index].bytes,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () => setState(() => _images.removeAt(index)),
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined),
                label: Text(_busy ? '접수 중…' : '신고 접수'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceImage {
  const _EvidenceImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}
