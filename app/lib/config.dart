import 'package:flutter/foundation.dart' show kReleaseMode;

/// 빌드 시점 환경변수 (--dart-define).
///
/// flutter run \
///   --dart-define=SUPABASE_URL=... \
///   --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=API_BASE_URL=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Edge Functions base URL.
  /// 보통 `${SUPABASE_URL}/functions/v1` 가 정답.
  /// 별도로 명시하지 않으면 supabaseUrl 에서 파생한다.
  static String get apiBaseUrl {
    const explicit = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (explicit.isNotEmpty) return explicit;
    return '$supabaseUrl/functions/v1';
  }

  /// Frontend-only preview switch for UI/design work.
  ///
  /// This bypasses web admin route guards locally when running with
  /// `--dart-define=ADMIN_DESIGN_PREVIEW=true`. Server-side RLS and Edge
  /// Function authorization still remain the source of truth.
  static const adminDesignPreview = bool.fromEnvironment(
    'ADMIN_DESIGN_PREVIEW',
    defaultValue: false,
  );

  /// Frontend-only preview switch for user-facing app UI work.
  ///
  /// This lets designers open mobile app routes on web without a signed-in
  /// session. It must only be enabled from local `flutter run` commands.
  static const userDesignPreview = bool.fromEnvironment(
    'USER_DESIGN_PREVIEW',
    defaultValue: false,
  );

  /// App Store 스크린샷 자동 캡처에서 개발용 안내 문구만 숨긴다.
  /// 사용자 프리뷰와 함께 쓰는 로컬 전용 플래그이며 릴리스 빌드에서는 금지한다.
  static const appStoreScreenshot = bool.fromEnvironment(
    'APP_STORE_SCREENSHOT',
    defaultValue: false,
  );

  /// 로컬 관리자 모드 (`make admin` → `--dart-define=ADMIN_MODE=true`).
  /// 로그인 화면을 관리자용으로 보여준다(컨슈머 카카오·마케팅·온보딩 카피 숨김,
  /// 이메일·구글 로그인만). 실제 관리자 권한은 서버 RLS/Edge(`users.role='admin'`)가
  /// 진실의 원천 — 이 플래그는 UI 표시용일 뿐 권한을 부여하지 않는다.
  static const adminMode = bool.fromEnvironment(
    'ADMIN_MODE',
    defaultValue: false,
  );

  /// 로컬 테스트용 운영진 계정 이메일.
  /// 실제 권한은 서버의 users.role 이 결정한다.
  static const testAdminEmail = String.fromEnvironment(
    'TEST_ADMIN_EMAIL',
    defaultValue: 'test1@naver.com',
  );

  /// 로컬 테스트용 일반 계정 이메일.
  /// 비워두면 일반 계정 로그인 버튼은 이메일 직접 입력 흐름으로 연다.
  static const testUserEmail = String.fromEnvironment(
    'TEST_USER_EMAIL',
    defaultValue: '',
  );

  /// 이 빌드의 빌드번호. `pubspec.yaml` 의 `version: x.y.z+N` 의 N 과 같아야 한다.
  ///
  /// package_info_plus 를 쓰지 않는 이유: 플랫폼 채널을 타므로 웹 빌드(JY-81)까지
  /// 신경 써야 하고, 이 값 하나를 위해 의존성을 늘릴 이유가 없다. 대신 pubspec 과의
  /// 일치는 `app/test/release_gate_test.dart` 가 강제한다 — 손으로 맞추다 어긋나는
  /// 경로를 막는다.
  static const appBuildNumber = 7;

  /// 개발용 프리뷰/관리자 우회 플래그 중 하나라도 켜져 있는지.
  /// 릴리스 빌드 차단(assertConfigured) 및 회귀 테스트에서 사용.
  static bool get hasDevOverrideFlags =>
      adminDesignPreview ||
      userDesignPreview ||
      appStoreScreenshot ||
      adminMode;

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY 가 설정되지 않았습니다. --dart-define 으로 전달하세요.',
      );
    }
    // 릴리스 빌드에는 개발용 프리뷰/관리자 우회 플래그가 절대 들어가면 안 된다.
    // dart-define·kReleaseMode 는 컴파일 상수라, 릴리스 빌드에서 우회 플래그가 켜져
    // 있으면 앱 시작 즉시 실패시켜 스토어 빌드로 새는 것을 차단한다 (JY-6).
    // debug/profile(로컬 개발·디자인 프리뷰)은 영향 없음.
    if (kReleaseMode && hasDevOverrideFlags) {
      throw StateError(
        'release build 에 개발용 플래그가 켜져 있습니다 '
        '(ADMIN_DESIGN_PREVIEW / USER_DESIGN_PREVIEW / '
        'APP_STORE_SCREENSHOT / ADMIN_MODE). '
        '프로덕션 빌드에서는 제거하세요.',
      );
    }
  }
}
