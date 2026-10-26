import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get/get.dart';

import 'auth_service.dart';
import 'notification_service.dart';

/// Runs when a message arrives while the app is in the background or
/// closed. Alerts there are shown by the system from the message itself,
/// so there is nothing to show; see [PushService] for clearing.
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {}

/// The signed-in owner's alerts (sent by Cloud Functions): registers this
/// device under `users/{uid}/devices/{token}`, shows alerts while the app
/// is open, and clears a dose's alert once it's logged on any device
/// (only alerts this app showed: ones the system showed in the background
/// stay until dismissed).
/// Caretakers get no alerts in this version.
///
/// Uses FCM registration tokens: the newer installation id API isn't
/// supported by the firebase-admin version the functions send with.
// ignore_for_file: deprecated_member_use
class PushService extends GetxService {
  PushService(this._auth, this._firestore, this._messaging, this._notify);

  final AuthService _auth;
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  final NotificationService _notify;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Worker? _userWorker;

  bool get _allowed => _notify.permission.value == NotifyPermission.granted;

  String? _uid;
  String? _token;

  Future<PushService> init() async {
    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
    // iOS shows alerts itself while the app is open; Android needs
    // _onMessage.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      sound: true,
    );
    _subscriptions
      ..add(FirebaseMessaging.onMessage.listen(_onMessage))
      ..add(_messaging.onTokenRefresh.listen(_onToken));
    _userWorker = ever<User?>(_auth.user, _onUser);
    _onUser(_auth.user.value);
    _auth.beforeSignOut.add(unregister);
    // Permission is asked by NotificationService; register once granted.
    _notify.onGranted.add(_register);
    if (_allowed) unawaited(_register());
    return this;
  }

  void _onUser(User? user) {
    final uid = user != null && !user.isAnonymous ? user.uid : null;
    if (uid == _uid) {
      // Same account, now perhaps verified: register if not yet done.
      if (uid != null && _token == null && _allowed) unawaited(_register());
      return;
    }
    final wasSignedIn = _uid != null;
    _uid = uid;
    if (uid != null && _allowed) unawaited(_register());
    if (uid == null && wasSignedIn && _token != null) {
      // Signed out elsewhere: the device record can't be removed without
      // the account, so retire the token; the server drops it on next send.
      _token = null;
      _messaging.deleteToken().catchError((Object e) => _log('token', e));
    }
  }

  Future<void> _register() async {
    final uid = _uid;
    if (uid == null || _auth.needsVerification) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await _onToken(token);
    } catch (e) {
      _log('token', e);
    }
  }

  Future<void> _onToken(String token) async {
    final uid = _uid;
    if (uid == null || !_allowed) return;
    final old = _token;
    _token = token;
    try {
      if (old != null && old != token) await _device(uid, old).delete();
      await _device(uid, token).set({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        // Missed dose alerts follow the device's local day.
        'timezone': (await FlutterTimezone.getLocalTimezone()).identifier,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _log('register', e);
    }
  }

  /// Removes this device before signing out, so the account's alerts stop
  /// here. Offline, the removal syncs later; the token is retired anyway.
  Future<void> unregister() async {
    final uid = _uid, token = _token;
    _token = null;
    if (uid == null || token == null) return;
    try {
      await _device(uid, token).delete().timeout(const Duration(seconds: 3));
    } catch (e) {
      _log('unregister', e);
    }
    await _messaging.deleteToken().catchError((Object e) => _log('token', e));
    await _notify.clearAll();
  }

  DocumentReference<Map<String, dynamic>> _device(String uid, String token) =>
      _firestore.collection('users').doc(uid).collection('devices').doc(token);

  Future<void> _onMessage(RemoteMessage message) async {
    final tag = message.data['tag'];
    if (tag is! String) return;
    if (message.data['type'] == 'dose-logged') return _notify.clear(tag);
    final n = message.notification;
    if (n == null || !Platform.isAndroid) return;
    await _notify.show(key: tag, title: n.title ?? '', body: n.body ?? '');
  }

  // Error types and codes only; never tokens or user data.
  static void _log(String step, Object e) {
    if (!kDebugMode) return;
    final code = e is FirebaseException ? e.code : e.runtimeType;
    debugPrint('Push $step error: $code');
  }

  @override
  void onClose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _userWorker?.dispose();
    _auth.beforeSignOut.remove(unregister);
    _notify.onGranted.remove(_register);
    super.onClose();
  }
}
