import 'package:get/get.dart';

import '../view_model/medicine_details_view_model.dart';

class MedicineDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MedicineDetailsViewModel>(() => MedicineDetailsViewModel());
  }
}
