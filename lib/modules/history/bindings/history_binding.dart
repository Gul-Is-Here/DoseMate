import 'package:get/get.dart';

import '../view_model/history_view_model.dart';

class HistoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HistoryViewModel>(() => HistoryViewModel());
  }
}
