import 'package:get/get.dart';

import '../view_model/medicines_view_model.dart';

class MedicinesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MedicinesViewModel>(() => MedicinesViewModel());
  }
}
