import 'package:allround/models/club_recruiting.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> recruitingJson({
  String sport = 'futsal',
  String status = 'open',
  Object? createdAt = '2026-07-14T10:00:00Z',
  Object? closedAt,
}) {
  return {
    'id': 'post-1',
    'club_id': 'club-1',
    'title': '주말 팀원 모집',
    'intro': '즐겁게 함께 뛰어요.',
    'place': '시민구장',
    'schedule_text': '7/18 (토) 19:00',
    'skill_level': '초급',
    'gender_text': '무관',
    'age_text': '30대',
    'position_text': sport == 'futsal' ? '필드·키퍼' : null,
    'field_count': sport == 'futsal' ? 4 : 0,
    'keeper_count': sport == 'futsal' ? 1 : 0,
    'total_count': sport == 'futsal' ? 5 : 2,
    'cost_text': '10,000원',
    'status': status,
    'created_at': createdAt,
    'closed_at': closedAt,
    'clubs': {
      'id': 'club-1',
      'name': '올라운드 클럽',
      'sport': sport,
      'region': '광주 북구',
      'status': 'approved',
    },
  };
}

void main() {
  test('풋살 모집글과 포지션별 인원 표시를 파싱한다', () {
    final post = RecruitingPostPreview.fromJson(recruitingJson());

    expect(post.clubId, 'club-1');
    expect(post.clubName, '올라운드 클럽');
    expect(post.countLabel, '필드 4명 · 키퍼 1명');
    expect(post.isClosed, isFalse);
    expect(post.createdAt.toUtc(), DateTime.utc(2026, 7, 14, 10));
  });

  test('테니스 모집글은 전체 모집 인원을 표시한다', () {
    final post = RecruitingPostPreview.fromJson(
      recruitingJson(sport: 'tennis'),
    );

    expect(post.position, isNull);
    expect(post.countLabel, '2명');
  });

  test('마감 상태와 잘못된 날짜를 안전하게 처리한다', () {
    final post = RecruitingPostPreview.fromJson(
      recruitingJson(
        status: 'closed',
        createdAt: 'invalid',
        closedAt: 'invalid',
      ),
    );

    expect(post.isClosed, isTrue);
    expect(post.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(post.closedAt, isNull);
  });
}
