import 'package:get/get.dart';

import '../view_model/add_visit_view_model.dart';

class AddVisitBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AddVisitViewModel>(() => AddVisitViewModel());
  }
}
