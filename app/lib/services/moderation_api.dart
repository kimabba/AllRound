import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/moderation.dart';
import '../utils/storage_object_name.dart';
import 'api_base.dart';

mixin ModerationApi on ApiBase {
  Future<bool> hasVerifiedSignupAge() async {
    final raw = await supabase.rpc('has_verified_signup_age');
    if (raw is! bool) {
      throw const FormatException('Invalid signup age verification payload');
    }
    return raw;
  }

  Future<UgcAccess> myUgcAccess() async {
    final raw = await supabase.rpc('my_ugc_access');
    if (raw is! Map) throw const FormatException('Invalid UGC access payload');
    return UgcAccess.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> acceptCurrentUgcTerms() async {
    await supabase.rpc('accept_current_ugc_terms');
  }

  Future<String> uploadReportEvidence({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final normalized = extension.toLowerCase().replaceAll('jpeg', 'jpg');
    final expectedContentType = switch (normalized) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
    if (expectedContentType == null || contentType != expectedContentType) {
      throw const FormatException('Invalid sanitized image format');
    }
    // Report evidence is private and its database RPC still validates the
    // reporter folder. Authorization itself uses Storage owner_id; the filename
    // is opaque and never contains the device's original source name.
    final path = '$userId/${newOpaqueImageObjectName(normalized)}';
    await supabase.storage.from('ugc-report-evidence').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<String> createUgcReport({
    required UgcTargetType targetType,
    required String targetId,
    required UgcReportReason reason,
    String? details,
    List<String> evidencePaths = const [],
  }) async {
    final raw = await supabase.rpc('create_ugc_report', params: {
      'p_target_type': targetType.value,
      'p_target_id': targetId,
      'p_reason': reason.value,
      'p_details': details?.trim().isEmpty == true ? null : details?.trim(),
      'p_evidence_paths': evidencePaths,
    });
    if (raw is! String) throw const FormatException('Invalid report id');
    return raw;
  }

  Future<void> deleteReportEvidence(List<String> paths) async {
    if (paths.isEmpty) return;
    await supabase.storage.from('ugc-report-evidence').remove(paths);
  }

  Future<void> blockUser(String userId) async {
    await supabase.rpc('block_user', params: {'p_blocked_user_id': userId});
  }

  Future<void> unblockUser(String userId) async {
    await supabase.rpc('unblock_user', params: {'p_blocked_user_id': userId});
  }

  Future<List<BlockedUser>> myBlockedUsers() async {
    final raw = await supabase.rpc('my_blocked_users');
    if (raw is! List) throw const FormatException('Invalid blocked users');
    return raw
        .whereType<Map>()
        .map((row) => BlockedUser.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<UgcReport>> adminUgcReports({String? status}) async {
    var query = supabase.from('ugc_reports').select(
          '*, '
          'reporter:users!ugc_reports_reporter_id_fkey(name,nickname,email), '
          'reported_user:users!ugc_reports_reported_user_id_fkey(name,nickname,email)',
        );
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false).limit(200);
    return rows.map(UgcReport.fromJson).toList(growable: false);
  }

  Future<List<UserPenalty>> adminUserPenalties(String userId) async {
    final rows = await supabase
        .from('user_penalties')
        .select('id, penalty_type, reason, ends_at')
        .eq('user_id', userId)
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return rows
        .map(
          (row) => UserPenalty.fromJson({
            'id': row['id'],
            'type': row['penalty_type'],
            'reason': row['reason'],
            'ends_at': row['ends_at'],
          }),
        )
        .toList(growable: false);
  }

  Future<String> reportEvidenceUrl(String path) {
    return supabase.storage
        .from('ugc-report-evidence')
        .createSignedUrl(path, 60 * 10);
  }

  Future<void> resolveUgcReport({
    required String reportId,
    required bool dismiss,
    required bool deleteContent,
    UgcPenaltyType? penaltyType,
    int? durationDays,
    String? note,
  }) async {
    await supabase.rpc('admin_resolve_ugc_report', params: {
      'p_report_id': reportId,
      'p_resolution': dismiss ? 'dismiss' : 'action',
      'p_delete_content': deleteContent,
      'p_penalty_type': penaltyType?.value,
      'p_duration_days': durationDays,
      'p_note': note?.trim().isEmpty == true ? null : note?.trim(),
    });
  }

  Future<void> revokeUserPenalty(String penaltyId, String reason) async {
    await supabase.rpc('admin_revoke_user_penalty', params: {
      'p_penalty_id': penaltyId,
      'p_reason': reason.trim(),
    });
  }

  Future<String?> findAssistantMessageId({
    required String conversationId,
    required String content,
  }) async {
    final row = await supabase
        .from('chat_messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .eq('role', 'assistant')
        .eq('content', content)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }
}
