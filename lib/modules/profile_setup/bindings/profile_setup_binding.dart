import 'package:get/get.dart';

import '../view_model/profile_setup_view_model.dart';

class ProfileSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProfileSetupViewModel>(() => ProfileSetupViewModel());
  }
}
