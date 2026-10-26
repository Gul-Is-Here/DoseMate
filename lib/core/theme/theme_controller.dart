import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';

/// The appearance setting (System, Light or Dark): saved on this device,
/// applied at once, and following the system's light/dark switch while on
/// System.
class ThemeController extends GetxService with WidgetsBindingObserver {
  static const _key = 'appearance.mode';

  final mode = ThemeMode.system.obs;

  Future<ThemeController> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_key),
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      // Unreadable storage: keep following the system.
      if (kDebugMode) debugPrint('Appearance load error: ${e.runtimeType}');
    }
    _apply(rebuild: false);
    return this;
  }

  /// The brightness the app shows now.
  Brightness get brightness => switch (mode.value) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  Future<void> setMode(ThemeMode value) async {
    if (value == mode.value) return;
    mode.value = value;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (e) {
      // Applied for now; it just won't be remembered.
      if (kDebugMode) debugPrint('Appearance save error: ${e.runtimeType}');
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (mode.value == ThemeMode.system) _apply();
  }

  void _apply({bool rebuild = true}) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    if (identical(palette, AppPalette.current)) return;
    AppPalette.current = palette;
    if (rebuild) rebuildAll();
  }

  /// Screens read colours as they build, so every widget rebuilds (keeping
  /// its state) to pick up the new palette.
  static void rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
