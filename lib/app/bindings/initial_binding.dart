import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/care_repository.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/care_service.dart';
import '../../data/services/profile_service.dart';

/// App-wide dependencies registered before the first frame.
abstract class InitialBinding {
  static Future<AuthService> init() {
    final profiles = Get.put(
      ProfileService(
        ProfileRepository(FirebaseFirestore.instance, FirebaseStorage.instance),
      ),
      permanent: true,
    );
    // Follows the active profile for every screen's medicines and visits.
    Get.put(
      CareService(CareRepository(FirebaseFirestore.instance), profiles),
      permanent: true,
    );
    // Address search for visits (Places API, client-restricted key).
    Get.put(PlacesRepository(), permanent: true);
    return Get.putAsync(
      () => AuthService(AuthRepository(FirebaseAuth.instance), profiles).init(),
      permanent: true,
    );
  }
}
