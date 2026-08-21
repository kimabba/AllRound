import '../utils/kst.dart';

class RuleQuiz {
  const RuleQuiz({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

const futsalRuleQuizzes = <RuleQuiz>[
  RuleQuiz(
    question: '풋살에서 골키퍼가 볼을 컨트롤할 수 있는 제한 시간은?',
    options: ['2초', '4초', '6초', '제한 없음'],
    correctIndex: 1,
    explanation: '풋살에서 골키퍼는 자기 진영에서 볼을 4초 넘게 컨트롤할 수 없습니다.',
  ),
  RuleQuiz(
    question: '풋살 경기 중 선수 교체 횟수는 몇 번까지 가능할까요?',
    options: ['3번', '5번', '무제한', '7번'],
    correctIndex: 2,
    explanation: '풋살은 지정된 절차와 교체 구역을 지키면 경기 중 무제한 교체가 가능합니다.',
  ),
  RuleQuiz(
    question: '볼이 터치라인을 넘었을 때 풋살의 재개 방법은?',
    options: ['스로인', '킥-인', '드롭 볼', '골 클리어런스'],
    correctIndex: 1,
    explanation: '풋살에서는 볼이 터치라인을 넘으면 손으로 던지지 않고 킥-인으로 재개합니다.',
  ),
];

const tennisRuleQuizzes = <RuleQuiz>[
  RuleQuiz(
    question: '테니스에서 세트 게임 스코어가 6-6이면 일반적으로 무엇을 할까요?',
    options: ['듀스', '타이브레이크', '렛', '세트 종료'],
    correctIndex: 1,
    explanation: '일반적인 세트에서는 6-6이 되면 타이브레이크로 세트 승자를 정합니다.',
  ),
  RuleQuiz(
    question: '첫 서브와 두 번째 서브가 모두 폴트가 되면?',
    options: ['렛', '다시 서브', '상대 포인트', '게임 종료'],
    correctIndex: 2,
    explanation: '두 번의 서브 기회를 모두 실패한 더블 폴트는 상대방의 포인트가 됩니다.',
  ),
  RuleQuiz(
    question: '공이 라인에 조금이라도 닿은 경우의 판정은?',
    options: ['아웃', '인', '렛', '재경기'],
    correctIndex: 1,
    explanation: '테니스에서는 공이 라인에 닿으면 인으로 판정합니다.',
  ),
];

List<RuleQuiz> ruleQuizzesForSport(String sport) {
  return sport == 'futsal' ? futsalRuleQuizzes : tennisRuleQuizzes;
}

RuleQuiz dailyRuleQuiz(String sport, {DateTime? now}) {
  final quizzes = ruleQuizzesForSport(sport);
  final today = kstTodayDate(now ?? DateTime.now());
  final firstDay = DateTime(today.year);
  final dayOfYear = today.difference(firstDay).inDays;
  return quizzes[dayOfYear % quizzes.length];
}
