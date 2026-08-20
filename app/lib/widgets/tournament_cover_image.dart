import 'package:flutter/material.dart';

import '../models/tournament.dart';

/// 대회 포스터를 우선 표시하고, 없거나 불러오지 못하면 종목별 기본 경기장
/// 사진을 보여준다. 대회 ID로 정렬 위치를 정해 같은 대회는 항상 같은 구도로
/// 보이면서도 포스터가 없는 카드들이 모두 똑같아 보이지 않게 한다.
class TournamentCoverImage extends StatelessWidget {
  const TournamentCoverImage({
    super.key,
    required this.tournament,
    this.fit = BoxFit.cover,
  });

  final Tournament tournament;
  final BoxFit fit;

  static const _futsalAsset = 'assets/images/tournaments/futsal-cover.jpg';
  static const _tennisAsset = 'assets/images/tournaments/tennis-cover.jpg';
  static const _alignments = <Alignment>[
    Alignment.centerLeft,
    Alignment.center,
    Alignment.centerRight,
  ];

  @override
  Widget build(BuildContext context) {
    final posterUrl = tournament.posterUrl?.trim();
    final fallback = Image.asset(
      tournament.sport == 'tennis' ? _tennisAsset : _futsalAsset,
      fit: fit,
      alignment: _alignmentFor(tournament.id),
    );
    if (posterUrl == null || posterUrl.isEmpty) return fallback;
    return Image.network(
      posterUrl,
      fit: fit,
      // 휴대폰 사진 원본(수천 px)을 그대로 디코딩하면 카드 스크롤 때 프레임이
      // 끊길 수 있다. 상세 화면의 고밀도 디스플레이까지 충분한 크기로 제한한다.
      cacheWidth: 1200,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Alignment _alignmentFor(String value) {
    var stableValue = 0;
    for (final unit in value.codeUnits) {
      stableValue = (stableValue * 31 + unit) & 0x7fffffff;
    }
    return _alignments[stableValue % _alignments.length];
  }
}
