import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../models/speed_measurement.dart';

// YOLOv8n COCO 'sports ball' 클래스 ID
const _sportsBallClass = 32;
const _modelPath = 'assets/models/yolov8n.tflite';
const _inputSize = 640;
const _confThreshold = 0.3;

class BallDetectorService {
  Interpreter? _interpreter;
  bool _useMock = false;

  Future<void> initialize() async {
    try {
      // assets에 모델 파일이 없으면 mock 모드로 fallback
      await rootBundle.load(_modelPath);
      _interpreter = await Interpreter.fromAsset(_modelPath);
      _useMock = false;
    } catch (_) {
      _useMock = true;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// 단일 프레임 이미지 파일에서 공 감지
  /// 반환: 감지된 공의 중심 좌표 + confidence (없으면 null)
  Future<({double x, double y, double confidence})?> detectBall(
    String imagePath,
  ) async {
    if (_useMock) return _mockDetect(imagePath);
    return _realDetect(imagePath);
  }

  /// 다수 프레임을 순서대로 처리 → BallPosition 리스트 반환
  Future<List<BallPosition>> detectFrames(
    List<String> framePaths, {
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <BallPosition>[];
    for (var i = 0; i < framePaths.length; i++) {
      final det = await detectBall(framePaths[i]);
      if (det != null) {
        results.add(BallPosition(
          frameIndex: i,
          x: det.x,
          y: det.y,
          confidence: det.confidence,
        ));
      }
      onProgress?.call(i + 1, framePaths.length);
    }
    return results;
  }

  // ──────────────────────────────────────────────────────────
  // TFLite 실제 추론
  // ──────────────────────────────────────────────────────────
  Future<({double x, double y, double confidence})?> _realDetect(
      String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) return null;

    final bytes = file.readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final resized = img.copyResize(image, width: _inputSize, height: _inputSize);
    final input = _imageToFloat32(resized);

    // YOLOv8 출력: [1, 84, 8400]
    // (4 bbox + 80 class scores) × 8400 anchors
    final output = List.generate(
      1,
      (_) => List.generate(84, (_) => List.filled(8400, 0.0)),
    );

    _interpreter!.run(input, output);

    return _postprocess(output[0], image.width.toDouble(), image.height.toDouble());
  }

  List<List<List<List<double>>>> _imageToFloat32(img.Image image) {
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );
    return input;
  }

  ({double x, double y, double confidence})? _postprocess(
    List<List<double>> output, // [84, 8400]
    double origW,
    double origH,
  ) {
    // output[0..3]: cx, cy, w, h (normalized to _inputSize)
    // output[4..83]: class scores (no sigmoid in YOLOv8 output)
    final detections = <({
      double cx,
      double cy,
      double w,
      double h,
      double score
    })>[];

    for (var i = 0; i < 8400; i++) {
      final score = output[4 + _sportsBallClass][i];
      if (score < _confThreshold) continue;

      final cx = output[0][i] * origW / _inputSize;
      final cy = output[1][i] * origH / _inputSize;
      final w = output[2][i] * origW / _inputSize;
      final h = output[3][i] * origH / _inputSize;
      detections.add((cx: cx, cy: cy, w: w, h: h, score: score));
    }

    if (detections.isEmpty) return null;

    // NMS: 가장 높은 score 선택 (단순 버전)
    detections.sort((a, b) => b.score.compareTo(a.score));
    final best = detections.first;

    return (x: best.cx, y: best.cy, confidence: best.score);
  }

  // ──────────────────────────────────────────────────────────
  // Mock 모드 — 모델 파일 없을 때 개발용 가짜 감지
  // ──────────────────────────────────────────────────────────
  int _mockFrame = 0;

  ({double x, double y, double confidence})? _mockDetect(String imagePath) {
    _mockFrame++;
    // 10프레임 중 7프레임 감지, 부드러운 포물선 궤적 시뮬레이션
    if (_mockFrame % 10 == 0) return null; // 간헐적 미감지
    final t = (_mockFrame % 60) / 60.0;
    final x = 100 + 400 * t;
    final y = 300 - 200 * (1 - (2 * t - 1) * (2 * t - 1)); // 포물선
    return (x: x, y: y, confidence: 0.75);
  }
}
