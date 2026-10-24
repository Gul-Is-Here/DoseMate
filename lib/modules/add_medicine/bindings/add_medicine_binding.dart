import 'package:get/get.dart';

import '../view_model/add_medicine_view_model.dart';

class AddMedicineBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AddMedicineViewModel>(() => AddMedicineViewModel());
  }
}
