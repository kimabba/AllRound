import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// 서버가 요구하는 최소 지원 빌드. 조회에 실패하면 null 이고, null 은 "막지 않는다"다.
@immutable
class ReleaseGate {
  const ReleaseGate({required this.minBuild, this.storeUrl});

  final int minBuild;
  final String? storeUrl;
}

/// 이 빌드가 막혀야 하는지. 순수 함수 — 화면·네트워크와 분리해 테스트 가능하게 둔다.
///
/// fail-open: gate 가 null(조회 실패·플랫폼 행 없음)이면 통과시킨다. 게이트는 보안이
/// 아니라 UX 장치이고, 서버가 잠깐 죽었다고 앱 전체가 잠기면 더 나쁘다. 실제 권한
/// 강제는 RLS/Edge 가 한다.
bool isUpdateRequired({required int currentBuild, required ReleaseGate? gate}) {
  if (gate == null) return false;
  return currentBuild < gate.minBuild;
}

/// 현재 플랫폼의 게이트 행 키. 웹은 항상 최신이 배포되므로 게이트 대상이 아니다.
String? releaseGatePlatform() {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return null;
  }
}

/// 게이트 조회. 어떤 실패도 null 로 흡수한다(fail-open).
Future<ReleaseGate?> fetchReleaseGate(SupabaseClient client) async {
  final platform = releaseGatePlatform();
  if (platform == null) return null;
  try {
    final row = await client
        .from('app_release_gate')
        .select('min_build, store_url')
        .eq('platform', platform)
        .maybeSingle();
    if (row == null) return null;
    return ReleaseGate(
      minBuild: row['min_build'] as int,
      storeUrl: row['store_url'] as String?,
    );
  } catch (_) {
    // ponytail: 조용히 통과시킨다. 게이트 조회 실패로 앱을 막는 건 사고다.
    return null;
  }
}

/// 앱 시작 시 1회 판정. 결과는 "막아야 하면 게이트, 아니면 null".
Future<ReleaseGate?> checkForcedUpdate(SupabaseClient client) async {
  final gate = await fetchReleaseGate(client);
  if (!isUpdateRequired(
    currentBuild: AppConfig.appBuildNumber,
    gate: gate,
  )) {
    return null;
  }
  return gate;
}
