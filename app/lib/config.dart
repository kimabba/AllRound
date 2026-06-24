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

  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

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

  /// 로컬 관리자 모드 (`make admin` → `--dart-define=ADMIN_MODE=true`).
  /// 로그인 화면을 관리자용으로 보여준다(컨슈머 카카오·마케팅·온보딩 카피 숨김,
  /// 이메일·구글 로그인만). 실제 관리자 권한은 서버 RLS/Edge(`users.role='admin'`)가
  /// 진실의 원천 — 이 플래그는 UI 표시용일 뿐 권한을 부여하지 않는다.
  static const adminMode = bool.fromEnvironment(
    'ADMIN_MODE',
    defaultValue: false,
  );

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY 가 설정되지 않았습니다. --dart-define 으로 전달하세요.',
      );
    }
  }
}
