import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final configuredDirectory =
      Platform.environment['ALLROUND_E2E_SCREENSHOT_DIR']?.trim();
  final outputDirectory = Directory(
    configuredDirectory == null || configuredDirectory.isEmpty
        ? 'build/design-evidence'
        : configuredDirectory,
  );

  await integrationDriver(
    responseDataCallback: null,
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? _,
    ]) async {
      final safeName = screenshotName.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '-',
      );
      if (safeName.isEmpty || screenshotBytes.length < 8) return false;
      const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      for (var index = 0; index < pngSignature.length; index += 1) {
        if (screenshotBytes[index] != pngSignature[index]) return false;
      }

      await outputDirectory.create(recursive: true);
      await File('${outputDirectory.path}/$safeName.png').writeAsBytes(
        screenshotBytes,
        flush: true,
      );
      return true;
    },
  );
}
