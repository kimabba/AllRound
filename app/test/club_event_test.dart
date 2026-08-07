import 'package:allround/models/club_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('my club join request parses pending status and requested date', () {
    final request = MyClubJoinRequest.fromJson({
      'id': 'request-1',
      'status': 'pending',
      'created_at': '2026-07-14T10:30:00Z',
    });

    expect(request.id, 'request-1');
    expect(request.isPending, isTrue);
    expect(request.createdAt, DateTime.utc(2026, 7, 14, 10, 30));
  });

  test('my club join request tolerates an invalid requested date', () {
    final request = MyClubJoinRequest.fromJson({
      'id': 'request-2',
      'status': 'rejected',
      'created_at': 'not-a-date',
    });

    expect(request.isPending, isFalse);
    expect(request.createdAt, isNull);
  });

  test('조기 종료와 반복 주기를 파싱한다', () {
    final event = ClubEvent.fromJson({
      'id': 'event-1',
      'club_id': 'club-1',
      'created_by': 'user-1',
      'title': '정기 운동',
      'starts_at': '2026-08-10T10:00:00Z',
      'ended_early_at': '2026-08-09T10:00:00Z',
      'repeat_interval': 'weekly',
      'club_event_attendees': <Object>[],
    }, currentUserId: 'user-2');

    expect(event.isEndedEarly, isTrue);
    expect(event.repeatLabel, '매주');
  });

  test('멤버 상세 프로필과 가입일을 파싱한다', () {
    final member = ClubMember.fromJson({
      'user_id': 'user-1',
      'role': 'member',
      'joined_at': '2026-08-01T00:00:00Z',
      'users': {
        'name': '홍길동',
        'clubs': ['주말 운동'],
        'sports': [
          {'sport': 'tennis', 'grade': 'div3'},
        ],
        'tennis_orgs': [
          {'org': 'kato', 'division': '챌린저부', 'score': 4},
        ],
        'tournaments': [
          {'title': '여름 대회', 'division': '개나리부'},
        ],
      },
    });

    expect(member.joinedAt, DateTime.utc(2026, 8, 1));
    expect(member.sports, ['tennis:div3']);
    expect(member.teams, ['주말 운동']);
    expect(member.tennisOrganizations, ['kato · 챌린저부 · 4']);
    expect(member.tournaments, ['여름 대회 · 개나리부']);
  });
}
