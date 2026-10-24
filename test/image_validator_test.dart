import 'dart:io';

import 'package:dosemate/core/utils/image_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects formats from bytes, not names', () {
    expect(
      ImageValidator.detectBytes([0xFF, 0xD8, 0xFF, 0xE0]),
      ImageFormat.jpeg,
    );
    expect(
      ImageValidator.detectBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
      ImageFormat.png,
    );
    expect(
      ImageValidator.detectBytes([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WEBP'.codeUnits,
      ]),
      ImageFormat.webp,
    );
    expect(
      ImageValidator.detectBytes([
        0,
        0,
        0,
        24,
        ...'ftyp'.codeUnits,
        ...'heic'.codeUnits,
      ]),
      ImageFormat.heic,
    );
    expect(ImageValidator.detectBytes('%PDF-1.7'.codeUnits), isNull);
    expect(ImageValidator.detectBytes([]), isNull);
  });

  test('rejects non-images and files over 5 MB', () {
    final dir = Directory.systemTemp.createTempSync('img');
    final pdf = File('${dir.path}/photo.jpg')
      ..writeAsBytesSync('%PDF-1.7'.codeUnits);
    final big = File('${dir.path}/big')
      ..writeAsBytesSync([
        0xFF,
        0xD8,
        0xFF,
        ...List.filled(ImageValidator.maxBytes, 0),
      ]);
    final ok = File('${dir.path}/noextension')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
    expect(ImageValidator.validate(pdf), contains('JPEG, PNG'));
    expect(ImageValidator.validate(big), contains('5 MB'));
    expect(ImageValidator.validate(ok), isNull);
  });
}
