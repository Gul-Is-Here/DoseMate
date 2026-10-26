import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/services/alarm_service.dart';
import '../data/services/notification_service.dart';
import 'app_snackbar.dart';

/// Settings for this device's notifications: their status, a way to turn
/// them on, and (Android) exact alarms for on-time reminders.
class NotificationSettingsSheet extends StatelessWidget {
  const NotificationSettingsSheet({super.key});

  static Future<void> show() async {
    final notify = Get.find<NotificationService>();
    await notify.refresh();
    await Get.bottomSheet(
      const NotificationSettingsSheet(),
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    );
  }

  NotificationService get _notify => Get.find<NotificationService>();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Obx(() {
          final on = _notify.permission.value == NotifyPermission.granted;
          final exact = _notify.exactAlarms.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag to dismiss (the sheet also closes on a tap outside).
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  'Notifications',
                  style: AppTextStyles.titleLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Status(
                label: 'Dose alerts',
                value: !_notify.ready
                    ? 'Unavailable on this device'
                    : on
                    ? 'On'
                    : 'Off',
                on: on,
              ),
              if (_notify.ready && !on) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _notify.enable,
                  child: const Text('Enable Notifications'),
                ),
              ],
              if (Platform.isAndroid && on && exact != null) ...[
                const SizedBox(height: 16),
                _Status(
                  label: 'Exact reminder times',
                  value: exact ? 'On' : 'Off: reminders may be late',
                  on: exact,
                ),
                if (!exact) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _notify.enableExactAlarms,
                    child: const Text('Allow exact alarms'),
                  ),
                ],
              ],
              if (on) ...[
                const SizedBox(height: 16),
                _AsyncTextButton(
                  label: 'Send a test notification',
                  onPressed: () async {
                    final shown = await _notify.show(
                      key: 'test',
                      title: 'DoseMate test',
                      body: 'Notifications are working on this device.',
                    );
                    showSnack(
                      shown ? 'Test sent' : 'Not sent',
                      shown
                          ? 'Check your notifications.'
                          : 'The test notification couldn\'t be created. '
                                'Try again, or check DoseMate in system '
                                'settings.',
                    );
                  },
                ),
                _AsyncTextButton(
                  label: 'Test alarm in 1 minute',
                  onPressed: () async {
                    final ok =
                        Get.isRegistered<AlarmService>() &&
                        await Get.find<AlarmService>().testAlarm();
                    showSnack(
                      ok ? 'Test alarm set' : 'Not set',
                      ok
                          ? 'It rings in about a minute. Try it locked.'
                          : 'The test alarm couldn\'t be scheduled. Try '
                                'again in a moment.',
                    );
                  },
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.value, required this.on});

  final String label;
  final String value;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          on ? Icons.notifications_active : Icons.notifications_off,
          color: on ? AppColors.primary : AppColors.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.labelMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A text button that shows it's working and ignores repeated taps until
/// [onPressed] finishes.
class _AsyncTextButton extends StatefulWidget {
  const _AsyncTextButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_AsyncTextButton> createState() => _AsyncTextButtonState();
}

class _AsyncTextButtonState extends State<_AsyncTextButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _busy ? null : _run,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Working',
              ),
            )
          : Text(widget.label),
    );
  }
}
