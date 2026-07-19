import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';

void main() {
  test('FormatStatus.fromString 매핑', () {
    expect(FormatStatus.fromString('needs_review'), FormatStatus.needsReview);
    expect(FormatStatus.fromString('formatted'), FormatStatus.formatted);
    expect(FormatStatus.fromString('skipped'), FormatStatus.skipped);
    expect(FormatStatus.fromString(null), FormatStatus.pending);
    expect(FormatStatus.fromString('bogus'), FormatStatus.pending);
  });
}
