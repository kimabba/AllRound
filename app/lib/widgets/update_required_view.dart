import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/release_gate.dart';
import '../theme/tokens.dart';

/// 최소 지원 빌드 미달일 때 앱 대신 그려지는 화면.
///
/// 뒤로 갈 곳이 없는 종착 화면이라 AppBar 도, 닫기도 없다. 서버가 이 버전을 더 이상
/// 지원하지 않는다는 뜻이므로 그냥 통과시키면 깨진 화면을 보게 된다.
class UpdateRequiredView extends StatelessWidget {
  const UpdateRequiredView({super.key, required this.gate});

  final ReleaseGate gate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final storeUrl = gate.storeUrl;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_rounded,
                  size: 56,
                  color: colors.primary,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '업데이트가 필요합니다',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '사용 중인 버전은 더 이상 지원되지 않습니다.\n'
                  '최신 버전으로 업데이트한 뒤 이용해주세요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                // 스토어 URL 이 아직 없으면(앱 ID 미확정) 버튼 대신 안내만 낸다.
                // 열리지 않는 버튼을 보여주는 것보다 낫다.
                if (storeUrl != null)
                  FilledButton(
                    onPressed: () => launchUrl(
                      Uri.parse(storeUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('스토어에서 업데이트'),
                  )
                else
                  Text(
                    '앱스토어에서 "올라운드"를 검색해주세요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
