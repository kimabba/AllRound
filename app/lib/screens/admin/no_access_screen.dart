import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined,
                size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 24),
            Text(
              '관리자 권한이 필요합니다',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '이 페이지는 관리자만 접근할 수 있습니다.\n모바일 앱을 설치하여 올라운드를 이용해주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Supabase.instance.client.auth
                  .signOut(scope: SignOutScope.global),
              icon: const Icon(Icons.logout),
              label: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}
