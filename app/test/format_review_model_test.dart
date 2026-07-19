import 'package:allround/models/format_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('format review JSON을 즉시 타입 모델로 변환한다', () {
    final item = FormatReviewItem.fromJson({
      'id': 'tid-1',
      'title': '정형화 검수',
      'source_url': 'https://example.com/tid-1',
      'format_source_hash': 'hash-1',
      'format_staged': {
        'regulation_fields': [
          {'label': '참가비', 'value': '30,000원'},
          {'label': '', 'value': '버려질 항목'},
        ],
        'regulation_notes': [' 주의 사항 ', null, ''],
      },
      'format_flags': [
        {'code': 'masked', 'field': '연락처', 'masked': '010-****-1234'},
      ],
    });

    expect(item.id, 'tid-1');
    expect(item.sourceUrl, Uri.parse('https://example.com/tid-1'));
    expect(item.staged?.fields, hasLength(1));
    expect(item.staged?.notes, ['주의 사항']);
    expect(item.flags.single.code, 'masked');
  });

  test('지원하지 않는 원문 URL과 식별자 누락을 안전하게 처리한다', () {
    final item = FormatReviewItem.fromJson({
      'id': 'tid-2',
      'title': '',
      'source_url': 'javascript:alert(1)',
      'format_staged': null,
      'format_flags': 'invalid',
    });

    expect(item.title, '제목 없는 대회');
    expect(item.sourceUrl, isNull);
    expect(item.flags, isEmpty);
    expect(
      () => FormatReviewItem.fromJson({'title': 'id 없음'}),
      throwsFormatException,
    );
  });
}
