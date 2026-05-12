import 'dart:math' as math;

import '../models/speed_measurement.dart';

/// Homography + Kalman + 속도 계산
class SpeedCalculator {
  /// DLT 알고리즘으로 3×3 Homography 행렬 계산
  /// [pixelPts] 4개 픽셀 좌표, [realPts] 대응 실제 좌표
  static List<List<double>> computeHomography(
    List<({double x, double y})> pixelPts,
    List<({double x, double y})> realPts,
  ) {
    assert(pixelPts.length == 4 && realPts.length == 4);

    // 8×9 행렬 A (DLT) 구성
    final a = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      final px = pixelPts[i].x;
      final py = pixelPts[i].y;
      final rx = realPts[i].x;
      final ry = realPts[i].y;
      a.add([-rx, -ry, -1, 0, 0, 0, px * rx, px * ry, px]);
      a.add([0, 0, 0, -rx, -ry, -1, py * rx, py * ry, py]);
    }

    // SVD 대신 정규방정식으로 근사 (경량 구현)
    // AᵀA h = 0 → 최소 고유벡터 → 반복 QR 대신 가우스 소거로 대체
    // 실용적 정확도: 4점이 비퇴화(non-degenerate)이면 충분
    final h = _solveDlt(a);
    return [
      [h[0], h[1], h[2]],
      [h[3], h[4], h[5]],
      [h[6], h[7], h[8]],
    ];
  }

  /// Homography로 픽셀 → 실제 좌표 변환
  static ({double x, double y}) pixelToReal(
    List<List<double>> h,
    double px,
    double py,
  ) {
    final w = h[2][0] * px + h[2][1] * py + h[2][2];
    if (w.abs() < 1e-10) return (x: 0, y: 0);
    final rx = (h[0][0] * px + h[0][1] * py + h[0][2]) / w;
    final ry = (h[1][0] * px + h[1][1] * py + h[1][2]) / w;
    return (x: rx, y: ry);
  }

  /// Kalman 필터로 공 위치 스무딩
  static List<BallPosition> kalmanSmooth(List<BallPosition> raw) {
    if (raw.isEmpty) return raw;

    final smoothed = <BallPosition>[];
    var kx = raw.first.x;
    var ky = raw.first.y;
    var vx = 0.0;
    var vy = 0.0;
    var px = 100.0; // 오차 공분산 초기값
    var py = 100.0;
    const q = 10.0; // 프로세스 노이즈
    const r = 50.0; // 측정 노이즈

    for (final pos in raw) {
      // 예측
      kx += vx;
      ky += vy;
      px += q;
      py += q;

      // 업데이트 (Kalman gain)
      final kgx = px / (px + r);
      final kgy = py / (py + r);
      final ix = kx + kgx * (pos.x - kx);
      final iy = ky + kgy * (pos.y - ky);
      vx = ix - kx;
      vy = iy - ky;
      kx = ix;
      ky = iy;
      px = (1 - kgx) * px;
      py = (1 - kgy) * py;

      smoothed.add(BallPosition(
        frameIndex: pos.frameIndex,
        x: kx,
        y: ky,
        confidence: pos.confidence,
      ));
    }
    return smoothed;
  }

  /// 공 위치 + Homography → 속도 계산
  static SpeedResult calculate({
    required List<BallPosition> detections,
    required CourtCalibration calibration,
    required double fps,
    required int totalFrames,
  }) {
    if (detections.length < 2) {
      return SpeedResult(
        peakSpeedKmh: 0,
        avgSpeedKmh: 0,
        trajectory: [],
        totalFrames: totalFrames,
        fps: fps,
      );
    }

    final homography = computeHomography(
      calibration.pixelPoints,
      calibration.realPoints,
    );

    final smoothed = kalmanSmooth(detections);
    final trajectory = <TrajectoryPoint>[];
    var peakSpeed = 0.0;
    var speedSum = 0.0;

    for (var i = 0; i < smoothed.length; i++) {
      final real = pixelToReal(homography, smoothed[i].x, smoothed[i].y);
      double speed = 0;

      if (i > 0) {
        final prev = trajectory[i - 1];
        final dx = real.x - prev.realX;
        final dy = real.y - prev.realY;
        final dist = math.sqrt(dx * dx + dy * dy); // 미터
        final frameDiff = smoothed[i].frameIndex - smoothed[i - 1].frameIndex;
        final timeSec = frameDiff / fps;
        speed = timeSec > 0 ? (dist / timeSec) * 3.6 : 0; // km/h
        if (speed > peakSpeed) peakSpeed = speed;
        speedSum += speed;
      }

      trajectory.add(TrajectoryPoint(
        frameIndex: smoothed[i].frameIndex,
        realX: real.x,
        realY: real.y,
        speedKmh: speed,
      ));
    }

    final avgSpeed =
        trajectory.length > 1 ? speedSum / (trajectory.length - 1) : 0.0;

    return SpeedResult(
      peakSpeedKmh: peakSpeed,
      avgSpeedKmh: avgSpeed,
      trajectory: trajectory,
      totalFrames: totalFrames,
      fps: fps,
    );
  }

  // ──────────────────────────────────────────────────────────
  // DLT 내부 구현 — 가우스-요르단 소거로 8×9 행렬의 null-space 벡터 추출
  // ──────────────────────────────────────────────────────────
  static List<double> _solveDlt(List<List<double>> a) {
    // AᵀA (9×9) 계산
    final ata = List.generate(9, (_) => List.filled(9, 0.0));
    for (var i = 0; i < 9; i++) {
      for (var j = 0; j < 9; j++) {
        double s = 0;
        for (final row in a) {
          s += row[i] * row[j];
        }
        ata[i][j] = s;
      }
    }

    // Power iteration으로 최소 고유벡터 근사
    // (완전 SVD 대신 경량 대안: AᵀA는 9×9이므로 허용)
    var v = List.filled(9, 1.0 / math.sqrt(9));
    const maxIter = 200;

    // Shift: λ_max ≈ Frobenius norm 사용, (AᵀA - λI)^{-1}v → 최소값 수렴
    double shift = 0;
    for (var i = 0; i < 9; i++) {
      shift += ata[i][i];
    }
    shift /= 9;

    final shifted = List.generate(
        9, (i) => List.generate(9, (j) => i == j ? ata[i][j] - shift : ata[i][j]));

    for (var iter = 0; iter < maxIter; iter++) {
      final mv = _matVec(shifted, v);
      final norm = math.sqrt(mv.fold(0.0, (s, x) => s + x * x));
      if (norm < 1e-12) break;
      v = mv.map((x) => x / norm).toList();
    }

    return v;
  }

  static List<double> _matVec(List<List<double>> m, List<double> v) {
    final result = List.filled(m.length, 0.0);
    for (var i = 0; i < m.length; i++) {
      for (var j = 0; j < v.length; j++) {
        result[i] += m[i][j] * v[j];
      }
    }
    return result;
  }
}
