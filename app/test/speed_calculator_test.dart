import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/speed_measurement.dart';
import 'package:allround/services/speed_calculator.dart';

void main() {
  group('SpeedCalculator', () {
    test('pixelToReal applies identity homography', () {
      final real = SpeedCalculator.pixelToReal(
        [
          [1, 0, 0],
          [0, 1, 0],
          [0, 0, 1],
        ],
        12.5,
        7.25,
      );

      expect(real.x, closeTo(12.5, 1e-9));
      expect(real.y, closeTo(7.25, 1e-9));
    });

    test('calculate returns a zero result when there are fewer than 2 detections', () {
      final result = SpeedCalculator.calculate(
        detections: const [
          BallPosition(frameIndex: 10, x: 100, y: 120, confidence: 0.92),
        ],
        calibration: const CourtCalibration(
          pixelPoints: [
            (x: 0.0, y: 0.0),
            (x: 100.0, y: 0.0),
            (x: 100.0, y: 100.0),
            (x: 0.0, y: 100.0),
          ],
          realPoints: [
            (x: 0.0, y: 0.0),
            (x: 10.0, y: 0.0),
            (x: 10.0, y: 10.0),
            (x: 0.0, y: 10.0),
          ],
        ),
        fps: 120,
        totalFrames: 240,
      );

      expect(result.peakSpeedKmh, 0);
      expect(result.avgSpeedKmh, 0);
      expect(result.trajectory, isEmpty);
      expect(result.detectedFrames, 0);
      expect(result.fps, 120);
      expect(result.totalFrames, 240);
    });

    test('kalmanSmooth preserves detection count, frame indices, and confidence', () {
      const raw = [
        BallPosition(frameIndex: 0, x: 10, y: 20, confidence: 0.8),
        BallPosition(frameIndex: 3, x: 16, y: 25, confidence: 0.7),
        BallPosition(frameIndex: 6, x: 22, y: 30, confidence: 0.6),
      ];

      final smoothed = SpeedCalculator.kalmanSmooth(raw);

      expect(smoothed, hasLength(raw.length));
      expect(smoothed.map((p) => p.frameIndex), [0, 3, 6]);
      expect(smoothed.map((p) => p.confidence), [0.8, 0.7, 0.6]);
    });
  });
}
