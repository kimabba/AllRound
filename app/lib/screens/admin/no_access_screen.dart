import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/session_security.dart';
import '../../widgets/app_empty_state.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppEmptyState(
        icon: Icons.admin_panel_settings_outlined,
        title: '관리자 권한이 필요합니다',
        description: '이 페이지는 관리자만 접근할 수 있습니다.\n모바일 앱에서 올라운드를 이용해 주세요.',
        actionLabel: '로그아웃',
        onAction: () => signOutSecurely(Supabase.instance.client),
      ),
    );
  }
}
