import 'package:allround/services/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 로그인 세션 없는 실제 SupabaseClient. 네트워크를 타지 않는다 —
// myConfirmedLink() 는 currentUser 가 null 이면 즉시 null 을 돌려준다
// (chat_ui_states_test.dart 와 동일한 패턴).
ApiService _unauthenticatedApi() => ApiService(
      SupabaseClient(
        'http://127.0.0.1:54321',
        'qa-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );

void main() {
  test('연결이 없으면 myPlayerResults 는 빈 목록을 돌려준다(전체 전적을 긁지 않는다)', () async {
    final api = _unauthenticatedApi();
    final results = await api.myPlayerResults();
    expect(results, isEmpty);
  });

  test('연결이 없으면 myConfirmedLink 는 null 이다', () async {
    final api = _unauthenticatedApi();
    final link = await api.myConfirmedLink();
    expect(link, isNull);
  });

  test('연결이 없으면 myCurrentRankings 는 빈 목록이다(전체 순위를 긁지 않는다)', () async {
    final api = _unauthenticatedApi();
    expect(await api.myCurrentRankings(), isEmpty);
  });

  // orgCode 는 로그인 이후 필터로만 쓰인다 — 비로그인 조기 반환 경로는
  // orgCode 유무와 무관하게 항상 먼저 걸린다. 실제 필터링(광주+전남 동시
  // confirmed 사용자가 지정한 협회만 받는지)은 네트워크를 타야 해 이 계층에서는
  // 검증할 수 없다 — rankings_screen_test.dart 의 _FakeRankingApi 로 화면
  // 통합 수준에서 확인한다.
  test('연결이 없으면 myConfirmedLink(orgCode:) 도 null 이다', () async {
    final api = _unauthenticatedApi();
    final link = await api.myConfirmedLink(orgCode: 'jn');
    expect(link, isNull);
  });

  test('연결이 없으면 myPlayerResults(orgCode:) 도 빈 목록이다', () async {
    final api = _unauthenticatedApi();
    final results = await api.myPlayerResults(orgCode: 'jn');
    expect(results, isEmpty);
  });

  test('연결이 없으면 myCurrentRankings(orgCode:) 도 빈 목록이다', () async {
    final api = _unauthenticatedApi();
    expect(await api.myCurrentRankings(orgCode: 'jn'), isEmpty);
  });
}
