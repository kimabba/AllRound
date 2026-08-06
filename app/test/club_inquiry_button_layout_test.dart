import 'package:allround/theme/app_theme.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// club_detail_screen.dart:1517-1556 '가입 전 문의' 카드를 실제 앱 테마로 재현한다.
// 회귀 방지: full-width(Size.fromHeight) FilledButton 테마 + Row 배치 조합.
Widget _inquiryCard(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return AppCard(
    variant: AppCardVariant.outlined,
    child: Row(
      children: [
        Icon(Icons.mark_chat_unread_outlined, color: cs.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('가입 전 문의',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text('클럽장·매니저가 함께 답변하는 운영진 문의함',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppSizes.control),
          ),
          onPressed: () {},
          child: const Text('문의함'),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('실제 앱 테마에서 가입 전 문의 카드가 레이아웃 예외 없이 렌더된다',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxxl),
            children: [Builder(builder: _inquiryCard)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('문의함'), findsOneWidget);
  });
}
