import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/services/notification_service.dart';

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
                    onPressed: _notify.requestExactAlarms,
                    child: const Text('Allow exact alarms'),
                  ),
                ],
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
