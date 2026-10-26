import 'dart:async';
import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/confirm_dialog.dart';
import 'alarm_actions.dart';

/// Notification permission as the app sees it.
enum NotifyPermission { unknown, granted, denied }

/// The app's only local-notification service (awesome_notifications):
/// channels, the permission prompt, showing and clearing alerts, and
/// scheduling. Remote messages arrive through PushService (FCM), which
/// shows them with [show] while the app is open.
class NotificationService extends GetxService with WidgetsBindingObserver {
  NotificationService({AwesomeNotifications? plugin})
    : _plugin = plugin ?? AwesomeNotifications();

  /// Local medicine and appointment alarms: the alarm sound, repeated
  /// until acted on (Android) for at most [AlarmService.ringFor].
  // Created natively first (MainActivity.createAlarmChannel) so it plays on
  // the alarm stream; the settings below must match it.
  static const alarmsChannel = 'dose_alarms';

  /// Server (FCM) alerts and follow-ups: the short notification sound.
  /// Its id is the FCM default channel in AndroidManifest.xml and the one
  /// Cloud Functions name.
  static const serverChannel = 'server_alerts';

  // Earlier channels. An Android channel's sound can't change once created,
  // so the sounds came with new channels and these are removed.
  static const _oldChannels = ['alerts', 'reminders', 'local_alarms'];
  static const _askedKey = 'notifications.asked';

  final AwesomeNotifications _plugin;

  final permission = NotifyPermission.unknown.obs;

  /// Android exact alarms (for on-time reminders); null where not needed.
  final exactAlarms = RxnBool();

  /// False when the plugin couldn't start; the app works without alerts.
  bool ready = false;

  /// Called whenever permission becomes granted or exact-alarm access
  /// changes (PushService registers, alarms are rescheduled).
  final onGranted = <Future<void> Function()>[];

  static bool _initialized = false;
  bool _asking = false;

  Future<NotificationService> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (_initialized) {
      ready = true;
      await refresh();
      return this;
    }
    try {
      ready = await _plugin.initialize(
        // Android small icon; null uses the app icon.
        null,
        [
          NotificationChannel(
            channelKey: alarmsChannel,
            channelName: 'Medicine & appointment alarms',
            channelDescription: 'Rings at each dose and appointment reminder',
            importance: NotificationImportance.Max,
            defaultPrivacy: NotificationPrivacy.Private,
            playSound: true,
            soundSource: 'resource://raw/alarm',
            defaultRingtoneType: DefaultRingtoneType.Alarm,
            enableVibration: true,
            vibrationPattern: highVibrationPattern,
            locked: false,
            onlyAlertOnce: false,
            criticalAlerts: false,
          ),
          NotificationChannel(
            channelKey: serverChannel,
            channelName: 'Dose alerts',
            channelDescription: 'Doses not logged yet and low supply',
            importance: NotificationImportance.High,
            defaultPrivacy: NotificationPrivacy.Private,
            playSound: true,
            soundSource: 'resource://raw/notificationsound',
            defaultRingtoneType: DefaultRingtoneType.Notification,
            enableVibration: true,
          ),
        ],
        debug: false,
      );
      await _plugin.setListeners(onActionReceivedMethod: onAction);
      for (final key in _oldChannels) {
        await _plugin.removeChannel(key).catchError((Object _) => false);
      }
      _initialized = ready;
    } catch (e) {
      ready = false;
      _log('init', e);
    }
    await refresh();
    return this;
  }

  /// Alarm buttons (may run in a background isolate); other taps open the
  /// app on its signed-in start screen.
  @pragma('vm:entry-point')
  static Future<void> onAction(ReceivedAction action) =>
      AlarmActions.handle(action);

  AwesomeNotifications get plugin => _plugin;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from system settings: pick up any change.
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Re-reads the permission and exact-alarm status.
  Future<void> refresh() async {
    if (!ready) return;
    try {
      final was = permission.value;
      final allowed = await _plugin.isNotificationAllowed();
      permission.value = allowed
          ? NotifyPermission.granted
          : NotifyPermission.denied;
      final wasExact = exactAlarms.value;
      if (Platform.isAndroid) {
        final has = await _plugin.checkPermissionList(
          channelKey: alarmsChannel,
          permissions: const [NotificationPermission.PreciseAlarms],
        );
        exactAlarms.value = has.contains(NotificationPermission.PreciseAlarms);
      }
      if (allowed &&
          (was != NotifyPermission.granted || wasExact != exactAlarms.value)) {
        await _granted();
      }
    } catch (e) {
      _log('status', e);
    }
  }

  /// From Home once it's visible after sign in: explains, then shows the
  /// native prompt. Asked once per install; a denial leaves the app usable
  /// and Settings offers to enable later.
  Future<void> askOnce() async {
    if (!ready || _asking) return;
    _asking = true;
    try {
      await refresh();
      if (permission.value != NotifyPermission.denied) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;
      await prefs.setBool(_askedKey, true);
      final ok = await confirmAction(
        title: 'Turn on dose alerts?',
        message:
            'DoseMate can tell you when a dose hasn\'t been logged and when '
            'a medicine is running low. You can change this anytime in '
            'Settings.',
        confirmLabel: 'Continue',
        cancelLabel: 'Not now',
        destructive: false,
      );
      if (ok) await _request();
    } catch (e) {
      _log('ask', e);
    } finally {
      _asking = false;
    }
  }

  /// The Settings button: the native prompt while one is available,
  /// otherwise the app's notification settings.
  Future<void> enable() async {
    if (!ready || _asking) return;
    _asking = true;
    try {
      await _request();
    } catch (e) {
      _log('enable', e);
    } finally {
      _asking = false;
    }
  }

  // On Android the plugin opens the settings page itself once the system
  // no longer shows a prompt; on iOS only the first request prompts.
  Future<void> _request() async {
    final allowed = await _plugin.requestPermissionToSendNotifications();
    if (!allowed && Platform.isIOS) await _plugin.showNotificationConfigPage();
    await refresh();
  }

  /// Exact alarms are separate from notification permission: Android
  /// grants them on a system page, never a prompt.
  Future<void> enableExactAlarms() async {
    if (!ready || !Platform.isAndroid) return;
    try {
      await _plugin.requestPermissionToSendNotifications(
        channelKey: alarmsChannel,
        permissions: const [NotificationPermission.PreciseAlarms],
      );
    } catch (e) {
      _log('exact', e);
    }
    await refresh();
  }

  Future<void> _granted() async {
    for (final f in List.of(onGranted)) {
      try {
        await f();
      } catch (e) {
        _log('granted', e);
      }
    }
  }

  /// Shows an alert now. [key] gives it a stable id, so the same alert
  /// replaces itself and can be cleared with [clear].
  Future<bool> show({
    required String key,
    required String title,
    required String body,
    String channel = serverChannel,
  }) async {
    if (!ready) return false;
    try {
      return await _plugin.createNotification(
        content: NotificationContent(
          id: idFor(key),
          channelKey: channel,
          title: title,
          body: body,
          category: NotificationCategory.Reminder,
          payload: {'key': key},
        ),
      );
    } catch (e) {
      _log('show', e);
      return false;
    }
  }

  Future<void> clear(String key) async {
    if (!ready) return;
    try {
      await _plugin.cancel(idFor(key));
    } catch (e) {
      _log('clear', e);
    }
  }

  /// On sign out: nothing of the account stays on the device.
  Future<void> clearAll() async {
    if (!ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      _log('clear', e);
    }
  }

  /// A stable 31-bit id for [key], the same on every run, so a reminder
  /// or alert is never duplicated.
  static int idFor(String key) => AlarmActions.idFor(key);

  // Error types only; never tokens or user data.
  static void _log(String step, Object e) {
    if (kDebugMode) debugPrint('Notifications $step error: ${e.runtimeType}');
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
