import 'package:flutter/material.dart';

// ── Phase 3: 검수 큐 필터 + submission_kind 배지 ─────────────────────────────

enum DraftFilter { all, crawler, user }

class SubmissionKindBadge extends StatelessWidget {
  const SubmissionKindBadge({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final isUser = kind == 'user';
    final color = isUser ? Colors.green.shade700 : Colors.blue.shade700;
    final label = isUser ? '사용자 제보' : '크롤러';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
