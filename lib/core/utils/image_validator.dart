import 'dart:io';

/// A supported profile image format, detected from the file's bytes.
enum ImageFormat {
  jpeg('jpg', 'image/jpeg'),
  png('png', 'image/png'),
  webp('webp', 'image/webp'),
  heic('heic', 'image/heic');

  const ImageFormat(this.extension, this.contentType);

  final String extension;
  final String contentType;
}

/// Checks a picked photo before upload. Matches the Storage rules: images
/// only, under [maxBytes].
abstract class ImageValidator {
  static const maxBytes = 5 * 1024 * 1024;

  /// Reads the 16-byte header; file names and extensions are not trusted.
  /// Synchronous on purpose: the read is tiny.
  static ImageFormat? detect(File file) {
    final raf = file.openSync();
    try {
      return detectBytes(raf.readSync(16));
    } finally {
      raf.closeSync();
    }
  }

  static ImageFormat? detectBytes(List<int> b) {
    bool at(int offset, List<int> sig) =>
        b.length >= offset + sig.length &&
        List.generate(
          sig.length,
          (i) => b[offset + i] == sig[i],
        ).every((ok) => ok);
    if (at(0, [0xFF, 0xD8, 0xFF])) return ImageFormat.jpeg;
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return ImageFormat.png;
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) {
      return ImageFormat.webp;
    }
    if (at(4, 'ftyp'.codeUnits) &&
        [
          'heic',
          'heix',
          'mif1',
          'msf1',
          'hevc',
        ].any((brand) => at(8, brand.codeUnits))) {
      return ImageFormat.heic;
    }
    return null;
  }

  /// Returns a user-facing error, or null when the photo can be uploaded.
  static String? validate(File file) {
    if (detect(file) == null) {
      return 'Choose a JPEG, PNG, WebP or HEIC photo.';
    }
    if (file.lengthSync() > maxBytes) {
      return 'That photo is too large. Choose one under 5 MB.';
    }
    return null;
  }
}
