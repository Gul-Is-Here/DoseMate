import 'package:get/get.dart';

import '../view_model/signup_view_model.dart';

class SignupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SignupViewModel>(() => SignupViewModel());
  }
}
