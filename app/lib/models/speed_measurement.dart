// Speed Gun v1.1 — 데이터 모델

class BallPosition {
  final int frameIndex;
  final double x; // 픽셀 좌표
  final double y;
  final double confidence;

  const BallPosition({
    required this.frameIndex,
    required this.x,
    required this.y,
    required this.confidence,
  });
}

/// 4점 코트 캘리브레이션 — 실제 코트 치수에 대한 픽셀 좌표 매핑
class CourtCalibration {
  /// 픽셀 좌표 4점 (좌상·우상·우하·좌하 순)
  final List<({double x, double y})> pixelPoints;

  /// 대응하는 실제 코트 좌표 (미터 단위)
  /// 표준 테니스 코트: 23.77m × 10.97m (싱글스)
  final List<({double x, double y})> realPoints;

  const CourtCalibration({
    required this.pixelPoints,
    required this.realPoints,
  });

  /// 표준 테니스 코트 실제 좌표 (싱글스 베이스라인 4 코너)
  static const defaultTennisRealPoints = [
    (x: 0.0, y: 0.0), // 좌상
    (x: 10.97, y: 0.0), // 우상
    (x: 10.97, y: 23.77), // 우하
    (x: 0.0, y: 23.77), // 좌하
  ];
}

class TrajectoryPoint {
  final int frameIndex;
  final double realX; // 실제 미터 좌표
  final double realY;
  final double speedKmh; // 이전 프레임 대비 속도

  const TrajectoryPoint({
    required this.frameIndex,
    required this.realX,
    required this.realY,
    required this.speedKmh,
  });
}

class SpeedResult {
  final double peakSpeedKmh;
  final double avgSpeedKmh;
  final List<TrajectoryPoint> trajectory;
  final int totalFrames;
  final double fps;

  const SpeedResult({
    required this.peakSpeedKmh,
    required this.avgSpeedKmh,
    required this.trajectory,
    required this.totalFrames,
    required this.fps,
  });

  int get detectedFrames => trajectory.length;
}
