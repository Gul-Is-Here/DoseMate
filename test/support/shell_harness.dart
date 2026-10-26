import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  @override
  String get uid => 'uid-1';

  @override
  bool get emailVerified => true;

  @override
  String? get email => 'eleanor@example.com';

  @override
  String? get displayName => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Optional: `HOME_FONTS=dir` (holding the Plus Jakarta Sans variable font
/// as pjs.ttf) loads the real fonts, and `HOME_SHOT=file.png` then writes a
/// faithful screenshot at the reference size.
Future<void> loadRealFonts() async {
  final dir = Platform.environment['HOME_FONTS'];
  if (dir == null) return;
  final jakarta = File('$dir/pjs.ttf').readAsBytesSync();
  for (final variant in ['regular', '500', '600', '700']) {
    await (FontLoader(
      'PlusJakartaSans_$variant',
    )..addFont(Future.value(ByteData.sublistView(jakarta)))).load();
  }
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
    'material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(icons)))).load();
}
