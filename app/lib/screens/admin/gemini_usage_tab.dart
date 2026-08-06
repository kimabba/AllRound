import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

// ponytail: Gemini 무료 티어 일일 요청 한도(RPD). 실제 값은 Google AI Studio
// 콘솔의 "Rate limits / 요금제"에서 확인 후 조정. 미등록 모델은 _defaultDailyLimit.
// 무료 한도는 구글이 수시로 바꾸므로 여기 상수를 유일한 기준값으로 유지한다.
const Map<String, int> _dailyRequestLimits = {
  'gemini-3.1-flash-lite': 1000,
  'gemini-embedding-2': 1000,
};
const int _defaultDailyLimit = 1000;

int _limitFor(String model) => _dailyRequestLimits[model] ?? _defaultDailyLimit;

/// 천단위 콤마. 집계값은 항상 0 이상이므로 음수 처리 불필요.
String _comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 관리자 대시보드 "Gemini 사용량" 탭. 오늘(로컬 자정 이후) 사용량을
/// kind·model 별로 무료 일일 한도 대비 게이지로 표시. 자체 로드.
class GeminiUsageTab extends ConsumerStatefulWidget {
  const GeminiUsageTab({super.key});

  @override
  ConsumerState<GeminiUsageTab> createState() => _GeminiUsageTabState();
}

class _GeminiUsageTabState extends ConsumerState<GeminiUsageTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    if (AppConfig.adminDesignPreview) return Future.value(const []);
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day); // 오늘 로컬 자정
    return ref.read(apiProvider).geminiUsageStats(since);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('로드 실패: ${snap.error}')),
                ),
              ],
            );
          }
          return _buildContent(context, snap.data ?? const []);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Map<String, dynamic>> rows) {
    final theme = Theme.of(context);
    final totalReqs = rows.fold<int>(
      0,
      (a, r) => a + ((r['request_count'] as num?)?.toInt() ?? 0),
    );
    final totalTok = rows.fold<int>(
      0,
      (a, r) => a + ((r['total_tokens'] as num?)?.toInt() ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘 사용량', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '요청 ${_comma(totalReqs)}회 · 토큰 ${_comma(totalTok)}',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '로컬 자정 이후 · 게이지는 무료 티어 일일 요청 한도(RPD) 기준',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: Text('오늘 사용 기록이 없습니다')),
          )
        else
          ...rows.map((r) => _usageCard(context, r)),
        const SizedBox(height: AppSpacing.md),
        Text(
          '※ 무료 한도는 Google AI Studio 콘솔(Rate limits)에서 확인 후 '
          'gemini_usage_tab.dart 의 _dailyRequestLimits 상수를 조정하세요.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _usageCard(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kind = r['kind'] as String? ?? '';
    final model = r['model'] as String? ?? '(unknown)';
    final reqs = (r['request_count'] as num?)?.toInt() ?? 0;
    final inTok = (r['input_tokens'] as num?)?.toInt() ?? 0;
    final outTok = (r['output_tokens'] as num?)?.toInt() ?? 0;
    final totTok = (r['total_tokens'] as num?)?.toInt() ?? 0;
    final limit = _limitFor(model);
    final ratio = limit > 0 ? (reqs / limit).clamp(0.0, 1.0) : 0.0;
    final pct = ratio * 100;
    final barColor = pct >= 90
        ? Colors.red
        : pct >= 70
        ? Colors.orange
        : cs.primary;
    final kindLabel = kind == 'llm'
        ? 'LLM'
        : kind == 'embedding'
        ? '임베딩'
        : kind;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(model, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    kindLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('요청 ${_comma(reqs)} / ${_comma(limit)}'),
                const Spacer(),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: theme.textTheme.bodyMedium?.copyWith(color: barColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: barColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '토큰 · 입력 ${_comma(inTok)} · 출력 ${_comma(outTok)} · 합 ${_comma(totTok)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
