import 'dart:typed_data';

import 'package:allround/utils/club_image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
