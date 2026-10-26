import 'package:get/get.dart';

import '../view_model/settings_view_model.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SettingsViewModel>(() => SettingsViewModel());
  }
}
