import 'package:allround/models/moderation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('현재 UGC 접근 상태와 제재를 타입으로 해석한다', () {
    final access = UgcAccess.fromJson({
      'terms_accepted': true,
      'penalties': [
        {
          'id': 'penalty-1',
          'type': 'comment_restriction',
          'reason': '반복 욕설',
          'ends_at': '2026-07-22T00:00:00Z',
        },
      ],
    });

    expect(access.termsAccepted, isTrue);
    expect(access.penalties, hasLength(1));
    expect(access.penalties.single.type, UgcPenaltyType.commentRestriction);
    expect(access.penalties.single.reason, '반복 욕설');
  });

  test('신고의 원문 스냅샷과 증거 경로를 해석한다', () {
    final report = UgcReport.fromJson({
      'id': 'report-1',
      'target_type': 'club_comment',
      'target_id': 'comment-1',
      'reason': 'abusive_language',
      'status': 'pending',
      'details': '댓글에서 욕설했어요',
      'evidence_paths': ['user-1/evidence.jpg'],
      'content_snapshot': {
        'comment_body': '신고 대상 댓글',
        'context_comments': <Object>[],
      },
      'created_at': '2026-07-15T00:00:00Z',
      'reporter': {'nickname': '신고자'},
      'reported_user': {'name': '작성자'},
      'reported_user_id': 'user-2',
    });

    expect(report.reason, UgcReportReason.abusiveLanguage);
    expect(report.reporterName, '신고자');
    expect(report.reportedUserName, '작성자');
    expect(report.evidencePaths.single, 'user-1/evidence.jpg');
    expect(report.snapshot['comment_body'], '신고 대상 댓글');
    expect(report.isOpen, isTrue);
  });
}
