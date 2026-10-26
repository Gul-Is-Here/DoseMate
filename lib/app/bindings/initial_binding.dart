import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/care_repository.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/services/calendar_service.dart';
import '../../data/services/history_service.dart';
import '../../data/services/alarm_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/care_service.dart';
import '../../data/services/profile_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/push_service.dart';

/// App-wide dependencies registered before the first frame.
abstract class InitialBinding {
  static Future<AuthService> init() async {
    final profiles = Get.put(
      ProfileService(
        ProfileRepository(FirebaseFirestore.instance, FirebaseStorage.instance),
      ),
      permanent: true,
    );
    // Follows the active profile for every screen's medicines and visits.
    final care = Get.put(
      CareService(CareRepository(FirebaseFirestore.instance), profiles),
      permanent: true,
    );
    // The Calendar's selection and visible week; kept across tab switches.
    Get.put(CalendarService(care), permanent: true);
    // Log History filters, loaded pages and scroll position.
    Get.put(HistoryService(care), permanent: true);
    // Address search for visits (Places API, client-restricted key).
    Get.put(PlacesRepository(), permanent: true);
    final auth = await Get.putAsync(
      () => AuthService(AuthRepository(FirebaseAuth.instance), profiles).init(),
      permanent: true,
    );
    // Account deletion (Cloud Function), and what this device forgets after.
    Get.put(AccountRepository(FirebaseFirestore.instance), permanent: true);
    auth.afterAccountDeleted
      ..add(_forgetAccountSettings)
      ..add((_) => _clearFirestoreCache());
    // Local notifications and permission; init never throws.
    final notify = await Get.putAsync(
      () => NotificationService().init(),
      permanent: true,
    );
    // Local alarms for every owned profile, kept in step with its data.
    final alarms = Get.put(
      AlarmService(
        auth,
        profiles,
        CareRepository(FirebaseFirestore.instance),
        notify,
      ).init(),
      permanent: true,
    );
    // Snoozes in the app re-arm the dose's alarm.
    care.onSnooze.add(alarms.snoozeDose);
    // Alerts from Cloud Functions; a failure here never blocks the app.
    try {
      await Get.putAsync(
        () => PushService(
          auth,
          FirebaseFirestore.instance,
          FirebaseMessaging.instance,
          notify,
        ).init(),
        permanent: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Push setup error: ${e.runtimeType}');
    }
    return auth;
  }

  /// Per-account settings are stored under keys ending in `.<uid>`.
  static Future<void> _forgetAccountSettings(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.endsWith('.$uid'))) {
      await prefs.remove(key);
    }
  }

  /// Drops the deleted account's cached records and any writes still
  /// queued for it. Firestore starts afresh on its next use.
  static Future<void> _clearFirestoreCache() async {
    final db = FirebaseFirestore.instance;
    await db.terminate();
    await db.clearPersistence();
  }
}
