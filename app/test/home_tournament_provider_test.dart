import 'package:allround/models/tournament.dart';
import 'package:allround/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';

Tournament tournament(String id, String sport, DateTime startDate) =>
    Tournament(
      id: id,
      sport: sport,
      title: id,
      organizer: '테스트',
      startDate: startDate,
      eligibleGrades: const [],
      status: 'published',
    );

void main() {
  final today = DateTime(2026, 8, 7);

  test('홈 대회는 종목마다 50건씩 독립 조회한다', () async {
    final calls = <String>[];

    final result = await loadHomeTournamentsBySport(
      hasGradeBasis: false,
      now: today,
      search: ({required sport, required onlyMyGrade, required limit}) async {
        calls.add('$sport:$onlyMyGrade:$limit');
        return [tournament('$sport-upcoming', sport, today)];
      },
    );

    expect(calls, ['futsal:false:50', 'tennis:false:50']);
    expect(result.map((item) => item.id), [
      'futsal-upcoming',
      'tennis-upcoming',
    ]);
  });

  test('등급 일치 예정 대회가 없는 종목만 전체 목록으로 다시 조회한다', () async {
    final calls = <String>[];

    final result = await loadHomeTournamentsBySport(
      hasGradeBasis: true,
      now: today,
      search: ({required sport, required onlyMyGrade, required limit}) async {
        calls.add('$sport:$onlyMyGrade:$limit');
        if (sport == 'futsal' && onlyMyGrade) {
          return [
            tournament(
              'futsal-past',
              sport,
              today.subtract(const Duration(days: 1)),
            ),
          ];
        }
        return [
          tournament(
            '$sport-${onlyMyGrade ? 'matched' : 'fallback'}',
            sport,
            today,
          ),
        ];
      },
    );

    expect(calls, ['futsal:true:50', 'tennis:true:50', 'futsal:false:50']);
    expect(result.map((item) => item.id), [
      'futsal-fallback',
      'tennis-matched',
    ]);
  });
}
