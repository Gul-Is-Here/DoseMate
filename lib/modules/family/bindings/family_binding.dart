import 'package:get/get.dart';

import '../view_model/family_view_model.dart';

class FamilyBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<FamilyViewModel>(() => FamilyViewModel());
  }
}
