import 'dart:math';

const _uploadImageExtensions = {'jpg', 'png'};

/// Creates an opaque 192-bit object name without embedding a user identifier.
///
/// Storage ownership is enforced by `storage.objects.owner_id`; a public URL
/// therefore does not need to expose the account UUID in its path.
String newOpaqueImageObjectName(
  String extension, {
  Random? random,
}) {
  final normalized = extension.toLowerCase().replaceAll('jpeg', 'jpg');
  if (!_uploadImageExtensions.contains(normalized)) {
    throw ArgumentError.value(extension, 'extension', 'jpg or png required');
  }

  final generator = random ?? Random.secure();
  final token = List<int>.generate(24, (_) => generator.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$token.$normalized';
}
