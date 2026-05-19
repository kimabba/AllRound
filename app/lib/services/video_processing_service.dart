import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class VideoMeta {
  final String path;
  final double fps;
  final int durationMs;
  final int width;
  final int height;

  const VideoMeta({
    required this.path,
    required this.fps,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  int get estimatedFrameCount => (durationMs / 1000 * fps).round();
}

class VideoProcessingService {
  final _picker = ImagePicker();

  /// 갤러리에서 비디오 선택 → VideoMeta 반환
  Future<VideoMeta?> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return probeVideo(file.path);
  }

  /// FFprobe로 비디오 메타데이터 추출
  Future<VideoMeta> probeVideo(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('비디오 정보를 읽을 수 없습니다: $path');
    }

    final streams = info.getStreams();
    final videoStream = streams.firstWhere(
      (s) => s.getType() == 'video',
      orElse: () => throw Exception('비디오 스트림 없음'),
    );

    final fps = _parseFps(videoStream.getAverageFrameRate());
    final durationMs =
        ((double.tryParse(info.getDuration() ?? '0') ?? 0) * 1000).round();
    final width = int.tryParse(videoStream.getWidth()?.toString() ?? '0') ?? 0;
    final height =
        int.tryParse(videoStream.getHeight()?.toString() ?? '0') ?? 0;

    return VideoMeta(
      path: path,
      fps: fps,
      durationMs: durationMs,
      width: width,
      height: height,
    );
  }

  /// 비디오에서 프레임을 JPEG로 추출 → 파일 경로 목록 반환
  /// [maxFrames] 최대 추출 프레임 수 (0 = 전체)
  Future<List<String>> extractFrames(
    VideoMeta meta, {
    int maxFrames = 0,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory('${tempDir.path}/speed_gun_frames');
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync();

    final framePattern = '${outDir.path}/frame_%05d.jpg';

    // 전체 프레임 또는 제한된 프레임 추출
    final vfFilter = maxFrames > 0
        ? 'select=\'lte(n\\,$maxFrames)\''
        : 'select=\'1\'';

    final cmd = '-i "${meta.path}" '
        '-vf "$vfFilter" '
        '-q:v 2 '
        '-vsync vfr '
        '"$framePattern"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (returnCode == null || returnCode.getValue() != 0) {
      final logs = await session.getAllLogs();
      final msg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception('프레임 추출 실패:\n$msg');
    }

    final frames = outDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .map((f) => f.path)
        .toList()
      ..sort();

    return frames;
  }

  /// 첫 번째 프레임만 추출 (캘리브레이션용)
  Future<String> extractFirstFrame(VideoMeta meta) async {
    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/speed_gun_first_frame.jpg';

    final cmd = '-i "${meta.path}" -frames:v 1 -q:v 2 "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (returnCode == null || returnCode.getValue() != 0) {
      throw Exception('첫 프레임 추출 실패');
    }

    return outPath;
  }

  /// 임시 프레임 파일 정리
  Future<void> cleanup() async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory('${tempDir.path}/speed_gun_frames');
    if (outDir.existsSync()) {
      outDir.deleteSync(recursive: true);
    }
  }

  double _parseFps(String? fpsStr) {
    if (fpsStr == null || fpsStr.isEmpty) return 30.0;
    // FFprobe는 "240/1" 또는 "30000/1001" 형식으로 반환
    if (fpsStr.contains('/')) {
      final parts = fpsStr.split('/');
      final num = double.tryParse(parts[0]) ?? 0;
      final den = double.tryParse(parts[1]) ?? 1;
      return den != 0 ? num / den : 30.0;
    }
    return double.tryParse(fpsStr) ?? 30.0;
  }
}
