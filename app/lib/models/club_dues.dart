enum ClubDueStatus {
  paid,
  unpaid,
  exempt;

  String get value => name;

  String get label => switch (this) {
        ClubDueStatus.paid => '납부',
        ClubDueStatus.unpaid => '미납',
        ClubDueStatus.exempt => '면제',
      };

  static ClubDueStatus fromValue(Object? value) => switch (value) {
        'paid' => ClubDueStatus.paid,
        'exempt' => ClubDueStatus.exempt,
        _ => ClubDueStatus.unpaid,
      };
}

class ClubDuesPeriod {
  final String id;
  final String clubId;
  final DateTime periodMonth;
  final int amount;
  final DateTime? dueDate;
  final String? accountInfo;

  const ClubDuesPeriod({
    required this.id,
    required this.clubId,
    required this.periodMonth,
    required this.amount,
    this.dueDate,
    this.accountInfo,
  });

  factory ClubDuesPeriod.fromJson(Map<String, dynamic> json) {
    return ClubDuesPeriod(
      id: json['id'] as String,
      clubId: json['club_id'] as String,
      periodMonth: DateTime.parse(json['period_month'] as String),
      amount: (json['amount'] as num).toInt(),
      dueDate: json['due_date'] is String
          ? DateTime.parse(json['due_date'] as String)
          : null,
      accountInfo: json['account_info'] as String?,
    );
  }
}

class ClubDuesPayment {
  final String id;
  final String periodId;
  final String userId;
  final ClubDueStatus status;
  final int? amountPaid;
  final String? note;
  final DateTime? paidAt;
  final DateTime updatedAt;

  const ClubDuesPayment({
    required this.id,
    required this.periodId,
    required this.userId,
    required this.status,
    required this.updatedAt,
    this.amountPaid,
    this.note,
    this.paidAt,
  });

  factory ClubDuesPayment.fromJson(Map<String, dynamic> json) {
    return ClubDuesPayment(
      id: json['id'] as String,
      periodId: json['period_id'] as String,
      userId: json['user_id'] as String,
      status: ClubDueStatus.fromValue(json['status']),
      amountPaid: (json['amount_paid'] as num?)?.toInt(),
      note: json['note'] as String?,
      paidAt: json['paid_at'] is String
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ClubDuesAuditEntry {
  final int id;
  final String paymentId;
  final ClubDueStatus? previousStatus;
  final ClubDueStatus nextStatus;
  final String? note;
  final DateTime createdAt;

  const ClubDuesAuditEntry({
    required this.id,
    required this.paymentId,
    required this.nextStatus,
    required this.createdAt,
    this.previousStatus,
    this.note,
  });

  factory ClubDuesAuditEntry.fromJson(Map<String, dynamic> json) {
    return ClubDuesAuditEntry(
      id: (json['id'] as num).toInt(),
      paymentId: json['payment_id'] as String,
      previousStatus: json['previous_status'] == null
          ? null
          : ClubDueStatus.fromValue(json['previous_status']),
      nextStatus: ClubDueStatus.fromValue(json['next_status']),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
