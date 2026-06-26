import 'api_base.dart';
import 'admin_api.dart';
import 'chat_api.dart';
import 'club_api.dart';
import 'notification_api.dart';
import 'rules_api.dart';
import 'tournament_api.dart';
import 'user_api.dart';

// 기존 import 호환: 다른 파일에서 `import 'api.dart'` 만으로
// ChatStreamEvent, buildTournamentSearchQuery 접근 가능.
export 'chat_api.dart' show ChatStreamEvent;
export 'tournament_api.dart' show buildTournamentSearchQuery;

/// Edge Functions REST + SSE 클라이언트.
///
/// 도메인별 메서드는 mixin 으로 분리되어 있으며,
/// 이 클래스가 facade 역할을 한다.
class ApiService extends ApiBase
    with
        TournamentApi,
        ClubApi,
        UserApi,
        RulesApi,
        NotificationApi,
        AdminApi,
        ChatApi {
  ApiService(super.supabase);
}
