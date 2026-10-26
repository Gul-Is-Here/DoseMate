import 'package:get/get.dart';

import '../../calendar/bindings/calendar_binding.dart';
import '../../history/bindings/history_binding.dart';
import '../../home/bindings/home_binding.dart';
import '../../medicines/bindings/medicines_binding.dart';
import '../../settings/bindings/settings_binding.dart';
import '../view_model/shell_view_model.dart';

/// One shell for all main tabs. Each tab's view model is registered lazily
/// and created when its tab is first shown.
class ShellBinding extends Bindings {
  ShellBinding({this.initialTab = 0});

  final int initialTab;

  @override
  void dependencies() {
    Get.put(ShellViewModel(initialTab: initialTab));
    HomeBinding().dependencies();
    MedicinesBinding().dependencies();
    CalendarBinding().dependencies();
    HistoryBinding().dependencies();
    SettingsBinding().dependencies();
  }
}
