import 'package:flutter/material.dart';

import '../../widgets/app_empty_state.dart';

// 웹 빌드용 stub — dart:io / FFmpeg 미지원 플랫폼에서 사용
class SpeedGunScreen extends StatelessWidget {
  const SpeedGunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스피드건')),
      body: const AppEmptyState(
        icon: Icons.phone_iphone_rounded,
        title: '모바일 앱에서 사용할 수 있어요',
        description: '스피드건은 휴대폰에 저장된 고속 촬영 영상을 기기 안에서 분석합니다.',
      ),
    );
  }
}
