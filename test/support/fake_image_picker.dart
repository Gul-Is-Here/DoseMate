import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Returns [result] (null = cancelled) or throws [error], recording the source.
class FakeImagePicker implements ImagePicker {
  XFile? result;
  PlatformException? error;
  final sources = <ImageSource>[];

  /// Writes a real image file so validation runs on actual bytes.
  static XFile write(String name, List<int> bytes) {
    final file = File(
      '${Directory.systemTemp.createTempSync('pick').path}/$name',
    )..writeAsBytesSync(bytes);
    return XFile(file.path);
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    sources.add(source);
    if (error case final e?) throw e;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
