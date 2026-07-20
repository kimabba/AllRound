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
      <String, Object>{'path': file.path, 'quality': 0.86},
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

/// Decodes and re-encodes an upload image before it leaves the device.
///
/// ImagePicker resizing is not a privacy boundary: camera model, capture time,
/// GPS coordinates, comments, and color profiles can remain in EXIF/ancillary
/// metadata. Re-encoding pixel data after baking orientation removes those
/// fields while keeping PNG transparency. WebP is normalized to PNG because
/// the image package intentionally has no WebP encoder.
PreparedClubImage prepareClubImageBytes(
  Uint8List originalBytes, {
  int jpegQuality = 86,
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

  if (format == ClubImageFormat.jpeg) {
    return PreparedClubImage(
      bytes: img.encodeJpg(
        clean,
        quality: jpegQuality.clamp(1, 100).toInt(),
      ),
      extension: ClubImageFormat.jpeg.extension,
      contentType: ClubImageFormat.jpeg.contentType,
    );
  }

  return PreparedClubImage(
    bytes: img.encodePng(clean),
    extension: ClubImageFormat.png.extension,
    contentType: ClubImageFormat.png.contentType,
  );
}
