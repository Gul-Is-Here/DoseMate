import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/auth_service.dart';
import '../routes/app_routes.dart';

/// Keeps unverified email accounts out of the app.
class VerifiedMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final user = Get.find<AuthService>().user.value;
    if (user == null) return const RouteSettings(name: AppRoutes.login);
    if (AuthRepository.needsEmailVerification(user)) {
      return const RouteSettings(name: AppRoutes.verifyEmail);
    }
    return null;
  }
}

/// Sends signed-out users to sign in.
class SignedInMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) => Get.find<AuthService>().isSignedIn
      ? null
      : const RouteSettings(name: AppRoutes.login);
}
