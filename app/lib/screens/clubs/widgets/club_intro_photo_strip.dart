import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/clubs/club_tiles.dart';

/// 클럽 소개 사진을 가로 목록으로 표시한다.
///
/// 빈 URL은 제외하고, 로드에 실패한 사진은 오류 아이콘으로 대체한다.
class ClubIntroPhotoStrip extends StatelessWidget {
  const ClubIntroPhotoStrip({
    required this.imageUrls,
    super.key,
  });

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final urls = imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          return Container(
            width: 168,
            height: 132,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: ClubMediaImage(
              source: urls[index],
              fit: BoxFit.cover,
              fallback: Icon(
                Icons.image_not_supported_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}
