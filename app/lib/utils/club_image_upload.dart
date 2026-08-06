import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

enum ClubImageFormat {
  jpeg(extension: 'jpg', contentType: 'image/jpeg'),
  png(extension: 'png', contentType: 'image/png'),
  webp(extension: 'webp', contentType: 'image/webp'),
  heif(extension: 'heic', contentType: 'image/heic');

  const ClubImageFormat({
    required this.extension,
    required this.contentType,
  });

  final String extension;
  final String contentType;
}

class PreparedClubImage {
  const PreparedClubImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

class ClubImagePreparationException implements Exception {
  const ClubImagePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _imageConverterChannel = MethodChannel(
  'kr.allround.app/club-image-converter',
);

ClubImageFormat? detectClubImageFormat(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return ClubImageFormat.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return ClubImageFormat.png;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return ClubImageFormat.webp;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    final headerEnd = bytes.length < 40 ? bytes.length : 40;
    final header = String.fromCharCodes(bytes.sublist(8, headerEnd));
    const heifBrands = ['heic', 'heix', 'hevc', 'hevx', 'heif', 'mif1', 'msf1'];
    if (heifBrands.any(header.contains)) return ClubImageFormat.heif;
  }
  return null;
}

Future<PreparedClubImage> prepareClubImage(XFile file) async {
  final originalBytes = await file.readAsBytes();
  final format = detectClubImageFormat(originalBytes);
  if (format == null) {
    throw const ClubImagePreparationException(
      '지원하지 않는 사진 형식입니다. JPG, PNG 또는 WebP 사진을 선택해주세요.',
    );
  }

  if (format != ClubImageFormat.heif) {
    return prepareClubImageBytes(originalBytes);
  }

  if (defaultTargetPlatform != TargetPlatform.iOS) {
    throw const ClubImagePreparationException(
      'HEIC 사진을 변환할 수 없습니다. JPG 또는 PNG 사진을 선택해주세요.',
    );
  }

  try {
    final converted = await _imageConverterChannel.invokeMethod<Uint8List>(
      'convertHeicToJpeg',
      // maxSide 는 ImagePicker 로 들어오는 다른 경로와 같은 상한이다.
      <String, Object>{'path': file.path, 'quality': 0.86, 'maxSide': 1600},
    );
    if (converted == null || converted.isEmpty) {
      throw const ClubImagePreparationException('iPhone 사진 변환에 실패했습니다.');
    }
    return prepareClubImageBytes(converted);
  } on PlatformException {
    throw const ClubImagePreparationException(
      'iPhone 사진 변환에 실패했습니다. 다른 사진으로 다시 시도해주세요.',
    );
  } on MissingPluginException {
    throw const ClubImagePreparationException(
      'iPhone 사진 변환 기능을 불러오지 못했습니다. 앱을 다시 실행해주세요.',
    );
  }
}

/// 어느 클럽 사진 버킷에도 들어가는 상한. club-logos 가 5MB 로 가장 엄격하다.
const clubImageMaxBytes = 5 * 1024 * 1024;

/// Decodes and re-encodes an upload image before it leaves the device.
///
/// ImagePicker resizing is not a privacy boundary: camera model, capture time,
/// GPS coordinates, comments, and color profiles can remain in EXIF/ancillary
/// metadata. Re-encoding pixel data after baking orientation removes those
/// fields while keeping PNG transparency. WebP is normalized to PNG because
/// the image package intentionally has no WebP encoder.
///
/// 투명한 픽셀이 있을 때만 PNG 로 남긴다. 무손실 PNG 는 사진에서 원본보다 커져
/// (1600×1600 실측 최대 7.5MB) 버킷 한도를 넘고, 그러면 업로드가 이유 없이
/// 실패한 것처럼 보인다.
PreparedClubImage prepareClubImageBytes(
  Uint8List originalBytes, {
  int jpegQuality = 86,
  int maxBytes = clubImageMaxBytes,
}) {
  final format = detectClubImageFormat(originalBytes);
  if (format == null || format == ClubImageFormat.heif) {
    throw const ClubImagePreparationException(
      '지원하지 않는 사진 형식입니다. JPG, PNG 또는 WebP 사진을 선택해주세요.',
    );
  }

  final img.Image? decoded;
  try {
    decoded = img.decodeImage(originalBytes);
  } on RangeError {
    throw const ClubImagePreparationException(
      '사진을 안전하게 처리하지 못했습니다. 다른 사진으로 다시 시도해주세요.',
    );
  } on FormatException {
    throw const ClubImagePreparationException(
      '사진을 안전하게 처리하지 못했습니다. 다른 사진으로 다시 시도해주세요.',
    );
  }
  if (decoded == null) {
    throw const ClubImagePreparationException(
      '사진을 안전하게 처리하지 못했습니다. 다른 사진으로 다시 시도해주세요.',
    );
  }

  final baked = img.bakeOrientation(decoded);
  final clean = img.Image.from(baked, noAnimation: true)
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;

  if (_hasTransparentPixel(clean)) {
    final png = img.encodePng(clean);
    if (png.length <= maxBytes) {
      return PreparedClubImage(
        bytes: png,
        extension: ClubImageFormat.png.extension,
        contentType: ClubImageFormat.png.contentType,
      );
    }
    // 투명도를 지키려면 PNG 여야 하는데 한도를 넘었다. 흰 배경에 합성해 JPEG 로
    // 떨어뜨리는 대신 사용자에게 알린다 — 배경색을 임의로 정하면 로고가 망가진다.
    throw const ClubImagePreparationException(
      '사진 용량이 너무 커서 올릴 수 없습니다. 더 작은 사진을 선택해주세요.',
    );
  }

  return PreparedClubImage(
    bytes: _encodeJpegWithinLimit(clean, jpegQuality, maxBytes),
    extension: ClubImageFormat.jpeg.extension,
    contentType: ClubImageFormat.jpeg.contentType,
  );
}

bool _hasTransparentPixel(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

Uint8List _encodeJpegWithinLimit(img.Image image, int quality, int maxBytes) {
  for (final q in <int>{quality.clamp(1, 100).toInt(), 70, 55}) {
    final bytes = img.encodeJpg(image, quality: q);
    if (bytes.length <= maxBytes) return bytes;
  }
  // 마지막 시도까지 한도를 넘겼다. 화질을 더 떨어뜨리는 대신 다른 사진을 받는다.
  throw const ClubImagePreparationException(
    '사진 용량이 너무 커서 올릴 수 없습니다. 더 작은 사진을 선택해주세요.',
  );
}
