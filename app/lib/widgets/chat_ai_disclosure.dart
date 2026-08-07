import 'package:flutter/material.dart';

/// 생성형 AI 이용 사실 고지 (인공지능기본법 §31·§43).
///
/// 입력창 바로 아래에 **상시** 둔다. 첫 진입 팝업은 한 번 닫으면 다시 안 보여
/// "이용자가 명확히 인식"에 기대기 어렵다. 답변 말풍선마다 붙이면 대화가
/// 문구로 덮인다 — 입력창 옆 한 줄이 항상 보이면서 가장 덜 방해한다.
///
/// 문구를 바꿀 때: `docs/legal/terms-of-service.html` 의 AI 조항,
/// `docs/legal/privacy-policy.html` 의 생성형 AI 고지와 말이 어긋나지 않게 한다.
class ChatAiDisclosure extends StatelessWidget {
  const ChatAiDisclosure({super.key});

  static const text = 'AI가 만든 답변이라 사실과 다를 수 있어요. 대회 정보는 원문 공고를 확인해 주세요.';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      // 스크린리더 사용자에게도 고지가 닿아야 한다. liveRegion 은 아니다 —
      // 화면이 갱신될 때마다 다시 읽히면 대화를 방해한다.
      label: text,
      child: ExcludeSemantics(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
