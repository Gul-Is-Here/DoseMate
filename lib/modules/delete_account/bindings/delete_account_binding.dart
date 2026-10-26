import 'package:get/get.dart';

import '../view_model/delete_account_view_model.dart';

class DeleteAccountBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeleteAccountViewModel>(() => DeleteAccountViewModel());
  }
}
