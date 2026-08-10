class ClubReviewRecord {
  final String id;
  final String name;
  final String sport;
  final String? region;
  final String? address;
  final String status;
  final String? statusReason;
  final String? reviewedBy;
  final String? reviewerName;
  final DateTime reviewedAt;

  const ClubReviewRecord({
    required this.id,
    required this.name,
    required this.sport,
    this.region,
    this.address,
    required this.status,
    this.statusReason,
    this.reviewedBy,
    this.reviewerName,
    required this.reviewedAt,
  });

  bool get isApproved => status == 'approved';

  factory ClubReviewRecord.fromJson(
    Map<String, dynamic> json, {
    required Map<String, String> reviewerNames,
  }) {
    final reviewedBy = json['approved_by'] as String?;
    return ClubReviewRecord(
      id: json['id'] as String,
      name: json['name'] as String,
      sport: json['sport'] as String,
      region: json['region'] as String?,
      address: json['address'] as String?,
      status: json['status'] as String,
      statusReason: json['status_reason'] as String?,
      reviewedBy: reviewedBy,
      reviewerName: reviewedBy == null ? null : reviewerNames[reviewedBy],
      reviewedAt: DateTime.parse(json['approved_at'] as String),
    );
  }
}

class CrawlAuditLog {
  final String id;
  final String source;
  final String status;
  final int fetchedCount;
  final int insertedCount;
  final int updatedCount;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  CrawlAuditLog({
    required this.id,
    required this.source,
    required this.status,
    required this.fetchedCount,
    required this.insertedCount,
    required this.updatedCount,
    this.error,
    required this.startedAt,
    this.finishedAt,
  });

  factory CrawlAuditLog.fromJson(Map<String, dynamic> j) => CrawlAuditLog(
        id: j['id'] as String,
        source: j['source'] as String,
        status: j['status'] as String,
        fetchedCount: j['fetched_count'] as int? ?? 0,
        insertedCount: j['inserted_count'] as int? ?? 0,
        updatedCount: j['updated_count'] as int? ?? 0,
        error: j['error'] as String?,
        startedAt: DateTime.parse(j['started_at'] as String),
        finishedAt: j['finished_at'] != null
            ? DateTime.parse(j['finished_at'] as String)
            : null,
      );
}
