import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../data/services/auth_service.dart';

class HomeViewModel extends GetxController {
  final counter = 0.obs;

  void increment() => counter.value++;

  final _auth = Get.find<AuthService>();

  bool get isSignedIn => _auth.isSignedIn;

  /// The auth listener routes to sign in once Firebase reports the logout.
  Future<void> signOut() => _auth.signOut();

  void signIn() => Get.offAllNamed(AppRoutes.login);
}
