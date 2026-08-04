import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/player_result.dart';

void main() {
  test('JSON 을 모델로 옮긴다', () {
    final r = PlayerResult.fromJson(const {
      'org_code': 'gj',
      'org_player_id': 'abc',
      'tournament_name': '광주시장배',
      'played_on': '2026-05-01',
      'event_raw': '골드부',
      'result_raw': '1',
      'result_round': 1,
      'points': 1000,
    });
    expect(r.tournamentName, '광주시장배');
    expect(r.playedOn, DateTime(2026, 5, 1));
    expect(r.resultRound, 1);
    expect(r.points, 1000);
  });

  test('정규화 실패 행은 resultRound 가 null 이고 원문이 남는다', () {
    final r = PlayerResult.fromJson(const {
      'org_code': 'gj',
      'org_player_id': 'abc',
      'tournament_name': 'zz',
      'played_on': '2026-05-01',
      'result_raw': '예선탈락',
      'result_round': null,
      'points': 5,
    });
    expect(r.resultRound, isNull);
    expect(r.resultRaw, '예선탈락');
  });

  test('표시 라벨 — 정규화값이 있으면 한국어로, 없으면 원문 그대로', () {
    expect(_label('1', 1), '우승');
    expect(_label('2', 2), '준우승');
    expect(_label('4강', 4), '4강');
    expect(_label('16', 16), '16강');
    expect(_label('예선탈락', null), '예선탈락');
  });
}

String _label(String raw, int? round) => PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': 'zz',
      'played_on': '2026-05-01',
      'result_raw': raw,
      'result_round': round,
      'points': 0,
    }).resultLabel;
