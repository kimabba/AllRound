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
}
