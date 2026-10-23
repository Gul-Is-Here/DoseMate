import 'package:get/get.dart';

import '../view_model/verify_email_view_model.dart';

class VerifyEmailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<VerifyEmailViewModel>(() => VerifyEmailViewModel());
  }
}
