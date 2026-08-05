import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/club_inquiry.dart';

void main() {
  test('club inquiry thread parses requester and timestamps', () {
    final thread = ClubInquiryThread.fromJson({
      'id': 'thread-1',
      'club_id': 'club-1',
      'requester_id': 'user-1',
      'status': 'open',
      'last_message_at': '2026-07-16T12:00:00Z',
      'created_at': '2026-07-16T11:00:00Z',
      'requester': {
        'nickname': '주희',
        'avatar_url': 'https://example.com/avatar.jpg',
        'primary_region': '서울',
        'age_group': '30대',
        'sports': [
          {'sport': 'tennis', 'grade': 'y3to5'},
        ],
        'clubs': ['주말 운동'],
        'tournaments': [
          {'title': '여름 대회', 'division': '개나리부'},
        ],
        'tennis_orgs': [
          {'org': 'kato', 'division': '챌린저부', 'score': 4},
        ],
      },
    });

    expect(thread.requesterLabel, '주희');
    expect(thread.requesterAvatarUrl, 'https://example.com/avatar.jpg');
    expect(thread.requesterRegion, '서울');
    expect(thread.requesterAgeGroup, '30대');
    expect(thread.requesterSports, ['tennis:y3to5']);
    expect(thread.requesterTeams, ['주말 운동']);
    expect(thread.requesterTournaments, ['여름 대회 · 개나리부']);
    expect(thread.requesterTennisOrganizations, ['kato · 챌린저부 · 4']);
    expect(thread.lastMessageAt.toUtc(), DateTime.utc(2026, 7, 16, 12));
  });

  test('club inquiry thread hides missing requester identity', () {
    final thread = ClubInquiryThread.fromJson({
      'id': 'thread-1',
      'club_id': 'club-1',
      'requester_id': 'user-1',
      'status': 'open',
      'last_message_at': '2026-07-16T12:00:00Z',
      'created_at': '2026-07-16T11:00:00Z',
    });

    expect(thread.requesterLabel, '문의자');
  });

  test('club inquiry message keeps nullable deleted sender', () {
    final message = ClubInquiryMessage.fromJson({
      'id': 'message-1',
      'thread_id': 'thread-1',
      'sender_id': null,
      'body': '문의 내용',
      'created_at': '2026-07-16T12:00:00Z',
    });

    expect(message.senderId, isNull);
    expect(message.body, '문의 내용');
  });
}
