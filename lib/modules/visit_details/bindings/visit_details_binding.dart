import 'package:get/get.dart';

import '../view_model/visit_details_view_model.dart';

class VisitDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<VisitDetailsViewModel>(() => VisitDetailsViewModel());
  }
}
