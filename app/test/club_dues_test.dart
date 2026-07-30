import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/club_dues.dart';

void main() {
  group('ClubDueStatus', () {
    test('서버 값을 앱 상태로 변환한다', () {
      expect(
        ClubDueStatus.fromValue('paid'),
        ClubDueStatus.paid,
      );
      expect(
        ClubDueStatus.fromValue('exempt'),
        ClubDueStatus.exempt,
      );
      expect(
        ClubDueStatus.fromValue('unexpected'),
        ClubDueStatus.unpaid,
      );
    });
  });

  test('회비 기간 JSON을 파싱한다', () {
    final period = ClubDuesPeriod.fromJson({
      'id': 'period-1',
      'club_id': 'club-1',
      'period_month': '2026-07-01',
      'amount': 40000,
      'due_date': '2026-07-10',
      'account_info': '카카오뱅크 3333',
    });

    expect(period.periodMonth, DateTime(2026, 7));
    expect(period.amount, 40000);
    expect(period.dueDate, DateTime(2026, 7, 10));
    expect(period.accountInfo, '카카오뱅크 3333');
  });

  test('멤버 납부 상태와 변경 기록 JSON을 파싱한다', () {
    final payment = ClubDuesPayment.fromJson({
      'id': 'payment-1',
      'period_id': 'period-1',
      'user_id': 'user-1',
      'status': 'paid',
      'amount_paid': 40000,
      'note': null,
      'paid_at': '2026-07-05T01:00:00Z',
      'updated_at': '2026-07-05T01:00:00Z',
    });
    final audit = ClubDuesAuditEntry.fromJson({
      'id': 1,
      'payment_id': 'payment-1',
      'previous_status': 'unpaid',
      'next_status': 'paid',
      'note': null,
      'created_at': '2026-07-05T01:00:00Z',
    });

    expect(payment.status, ClubDueStatus.paid);
    expect(payment.amountPaid, 40000);
    expect(audit.previousStatus, ClubDueStatus.unpaid);
    expect(audit.nextStatus, ClubDueStatus.paid);
  });
}
