import 'package:allround/models/moderation.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/moderation/ugc_moderation_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 회귀 방지: 앱 테마의 버튼 minimumSize(Size.fromHeight=폭 무한)가 Row 안
  // 버튼에서 레이아웃 크래시를 냈던 버그(신고 시트 먹통). 실제 테마로 검증한다.
  testWidgets('앱 테마에서 중첩 모달(채팅 시트) 안 신고 시트가 열린다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    // 채팅 시트 재현: showModalBottomSheet + DraggableScrollableSheet
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (sheetContext) => DraggableScrollableSheet(
                        initialChildSize: 0.62,
                        expand: false,
                        builder: (bodyContext, scrollController) => Consumer(
                          builder: (c, ref, _) => ListView(
                            controller: scrollController,
                            children: [
                              TextButton(
                                onPressed: () => showUgcReportSheet(
                                  context: bodyContext,
                                  ref: ref,
                                  targetType: UgcTargetType.aiMessage,
                                  targetId: 'msg-1',
                                ),
                                child: const Text('AI 답변 신고'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('채팅 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 답변 신고'));
    await tester.pumpAndSettle();

    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('신고 사유'), findsOneWidget);
  });
}
