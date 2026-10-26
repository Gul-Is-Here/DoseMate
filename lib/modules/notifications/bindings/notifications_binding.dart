import 'package:get/get.dart';

import '../view_model/notifications_view_model.dart';

class NotificationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NotificationsViewModel>(() => NotificationsViewModel());
  }
}
