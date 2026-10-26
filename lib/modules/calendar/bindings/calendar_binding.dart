import 'package:get/get.dart';

import '../view_model/calendar_view_model.dart';

class CalendarBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CalendarViewModel>(() => CalendarViewModel());
  }
}
