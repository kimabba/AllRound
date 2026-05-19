import 'package:flutter/material.dart';

// 웹 빌드용 stub — dart:io / FFmpeg 미지원 플랫폼에서 사용
class SpeedGunScreen extends StatelessWidget {
  const SpeedGunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('스피드건')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '스피드건은 모바일 앱에서만 사용할 수 있습니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
