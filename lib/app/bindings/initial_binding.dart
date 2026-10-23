import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/auth_service.dart';

/// App-wide dependencies registered before the first frame.
abstract class InitialBinding {
  static Future<AuthService> init() => Get.putAsync(
    () => AuthService(AuthRepository(FirebaseAuth.instance)).init(),
    permanent: true,
  );
}
