import 'dart:math';
import 'dart:typed_data';

import 'package:allround/utils/club_image_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('detectClubImageFormat', () {
    test('detects JPEG, PNG, and WebP from bytes', () {
      expect(
        detectClubImageFormat(Uint8List.fromList([0xff, 0xd8, 0xff, 0x00])),
        ClubImageFormat.jpeg,
      );
      expect(
        detectClubImageFormat(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        ),
        ClubImageFormat.png,
      );
      expect(
        detectClubImageFormat(
          Uint8List.fromList('RIFFxxxxWEBP'.codeUnits),
        ),
        ClubImageFormat.webp,
      );
    });

    test('detects iPhone HEIC/HEIF container brands', () {
      expect(
        detectClubImageFormat(
          Uint8List.fromList(<int>[0, 0, 0, 24, ...'ftypheic'.codeUnits]),
        ),
        ClubImageFormat.heif,
      );
      expect(
        detectClubImageFormat(
          Uint8List.fromList(<int>[0, 0, 0, 24, ...'ftypmif1'.codeUnits]),
        ),
        ClubImageFormat.heif,
      );
    });

    test('rejects unsupported bytes instead of relabeling them as JPEG', () {
      expect(
        detectClubImageFormat(Uint8List.fromList('not an image'.codeUnits)),
        isNull,
      );
    });
  });

  group('prepareClubImageBytes', () {
    test('bakes orientation and removes JPEG EXIF metadata', () {
      final source = img.Image(width: 2, height: 1)
        ..setPixelRgba(0, 0, 255, 0, 0, 255)
        ..setPixelRgba(1, 0, 0, 0, 255, 255);
      source.exif.imageIfd.orientation = 6;
      source.exif.imageIfd.imageDescription = 'private capture note';

      final prepared = prepareClubImageBytes(img.encodeJpg(source));
      final decoded = img.decodeJpg(prepared.bytes);

      expect(prepared.extension, 'jpg');
      expect(prepared.contentType, 'image/jpeg');
      expect(decoded, isNotNull);
      expect(decoded!.width, 1);
      expect(decoded.height, 2);
      expect(decoded.exif.isEmpty, isTrue);
      expect(img.decodeJpgExif(prepared.bytes)?.isEmpty ?? true, isTrue);
    });

    test('removes PNG text metadata and preserves transparency', () {
      final source = img.Image(width: 1, height: 1, numChannels: 4)
        ..setPixelRgba(0, 0, 10, 20, 30, 40)
        ..textData = {'Location': 'private place'};

      final prepared = prepareClubImageBytes(img.encodePng(source));
      final decoded = img.decodePng(prepared.bytes);

      expect(prepared.extension, 'png');
      expect(prepared.contentType, 'image/png');
      expect(decoded, isNotNull);
      expect(decoded!.textData, isNull);
      expect(decoded.getPixel(0, 0).a, 40);
    });

    test('불투명한 PNG 는 JPEG 로 내보낸다 (무손실 PNG 는 한도를 넘긴다)', () {
      final opaque = img.Image(width: 64, height: 64, numChannels: 4);
      for (final pixel in opaque) {
        pixel.setRgba(120, 60, 30, 255);
      }

      final prepared = prepareClubImageBytes(img.encodePng(opaque));

      expect(prepared.extension, 'jpg');
      expect(prepared.contentType, 'image/jpeg');
      expect(img.decodeJpg(prepared.bytes), isNotNull);
    });

    test('한도를 넘는 사진은 화질을 낮춰 담고, 그래도 넘치면 안내한다', () {
      final noisy = img.Image(width: 400, height: 400);
      final random = Random(11);
      for (final pixel in noisy) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final source = img.encodeJpg(noisy, quality: 100);

      // 기본 화질로는 넘치지만 낮추면 들어가는 한도
      final atQuality86 = prepareClubImageBytes(source).bytes.length;
      final squeezed = prepareClubImageBytes(source, maxBytes: atQuality86 - 1);
      expect(squeezed.bytes.length, lessThan(atQuality86));

      // 어떤 화질로도 못 담으면 실패를 삼키지 않고 알린다
      expect(
        () => prepareClubImageBytes(source, maxBytes: 100),
        throwsA(isA<ClubImagePreparationException>()),
      );
    });

    test('투명도가 있으면 한도를 넘겨도 JPEG 로 바꾸지 않고 알린다', () {
      final transparent = img.Image(width: 64, height: 64, numChannels: 4)
        ..setPixelRgba(0, 0, 10, 20, 30, 0);

      expect(
        () => prepareClubImageBytes(
          img.encodePng(transparent),
          maxBytes: 10,
        ),
        throwsA(isA<ClubImagePreparationException>()),
      );
    });

    test('rejects malformed bytes even when the header looks supported', () {
      expect(
        () => prepareClubImageBytes(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
        ),
        throwsA(isA<ClubImagePreparationException>()),
      );
    });
  });
}
