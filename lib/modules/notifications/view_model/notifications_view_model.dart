import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/dose_state.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/visit.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/care_service.dart';
import '../../medicine_details/view_model/medicine_details_view_model.dart';
import '../../visit_details/view_model/visit_details_view_model.dart';
import '../../../widgets/app_snackbar.dart';

enum NotificationTab { all, doses, refills, appointments }

/// Which buttons a card shows.
enum NotificationAction { takeOrSnooze, refill, directions, details }

/// What an alert's colours say: an overdue dose, something needing
/// attention, or information. Resolved when drawn, so they follow the theme.
enum NotificationTone { overdue, attention, info }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.tab,
    required this.label,
    required this.time,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.action,
    required this.today,
    this.dose,
    this.medicine,
    this.visit,
  });

  final String id;
  final NotificationTab tab;
  final String label;
  final String time;
  final String title;
  final String body;
  final IconData icon;
  final NotificationTone tone;
  final NotificationAction action;
  final bool today;
  final DoseOccurrence? dose;
  final Medicine? medicine;
  final Visit? visit;

  Color get iconColor => switch (tone) {
    NotificationTone.overdue => AppColors.error,
    NotificationTone.attention => AppColors.attention,
    NotificationTone.info => AppColors.onSelected,
  };

  Color get iconBackground => switch (tone) {
    NotificationTone.overdue => AppColors.errorContainer,
    NotificationTone.attention => AppColors.attentionContainer,
    NotificationTone.info => AppColors.selected,
  };

  Color get labelColor => iconColor;
}

/// Notifications & Alerts for the active profile, worked out live from its
/// medicines, dose logs and visits (the same Firestore streams Home uses),
/// so an alert disappears as soon as its dose is logged on any device.
/// Read marks are kept on this device. Caregiver items are left out in
/// this version.
class NotificationsViewModel extends GetxController {
  NotificationsViewModel({CareService? care})
    : care = care ?? Get.find<CareService>();

  final CareService care;

  /// Doses this long past their time are alerted, like the push alerts.
  static const _alertAfter = DoseStates.grace;
  static const _visitDays = 3;

  final tab = NotificationTab.all.obs;
  final read = <String>{}.obs;
  final items = <NotificationItem>[].obs;

  // Re-evaluated every minute so a dose becomes overdue on time.
  final _tick = 0.obs;
  Timer? _timer;
  final _workers = <Worker>[];
  String? _readKey;

  @override
  void onInit() {
    super.onInit();
    _workers.add(
      everAll([
        care.medicines,
        care.logs,
        care.visits,
        care.today,
        care.snoozed,
        _tick,
      ], (_) => _build()),
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick.value++);
    _build();
    _loadRead();
  }

  @override
  void onClose() {
    _timer?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    super.onClose();
  }

  /// True until the profile's schedule first arrives (not on later
  /// updates, which keep the list in place).
  bool get loading =>
      care.status.value == CareStatus.loading ||
      care.status.value == CareStatus.idle;

  /// Why the schedule couldn't load, or null.
  String? get loadError => care.status.value == CareStatus.error
      ? (care.error.value ?? 'Could not load your schedule.')
      : null;

  Future<void> retry() => care.retry();

  /// A Take Now for [n] is still being saved.
  bool isSaving(NotificationItem n) =>
      n.dose != null && care.busy.contains(n.dose!.logId);

  bool isUnread(NotificationItem n) => !read.contains(n.id);

  int get unreadCount => items.where(isUnread).length;

  int countFor(NotificationTab t) =>
      items.where((n) => t == NotificationTab.all || n.tab == t).length;

  List<NotificationItem> visible({required bool today}) => items
      .where(
        (n) =>
            n.today == today &&
            (tab.value == NotificationTab.all || n.tab == tab.value),
      )
      .toList();

  void markAllRead() {
    read.addAll(items.map((n) => n.id));
    _saveRead();
  }

  void markRead(NotificationItem n) {
    if (read.add(n.id)) _saveRead();
  }

  void _build() {
    final now = care.now();
    final today = care.today.value;
    final pid = care.profileId ?? '';
    final list = <NotificationItem>[];

    // Unlogged doses: today's past their alert time, and yesterday's.
    final yesterday = CareDates.addDays(today, -1);
    for (final day in [today, yesterday]) {
      for (final o in care.occurrencesOn(day)) {
        if (care.logFor(o) != null) continue;
        final isToday = day == today;
        if (isToday &&
            (!o.at.isBefore(now.subtract(_alertAfter)) || care.isSnoozed(o))) {
          continue;
        }
        final m = o.medicine;
        list.add(
          NotificationItem(
            id: 'dose:$pid:${o.logId}',
            tab: NotificationTab.doses,
            label: isToday ? 'Missed Scheduled Dose' : 'Missed Dose',
            time: isToday
                ? '${CareDates.clockOf(o.at)} (${_ago(now.difference(o.at))})'
                : 'Yesterday at ${CareDates.clockOf(o.at)}',
            title: [m.name, m.dosage].where((s) => s.isNotEmpty).join(' '),
            body: isToday
                ? 'Scheduled for ${CareDates.clockOf(o.at)}. Log it now or '
                      'snooze for 15 minutes.'
                : 'This dose wasn\'t logged. Open it to review or log it late.',
            icon: Icons.alarm_on,
            tone: NotificationTone.overdue,
            action: isToday
                ? NotificationAction.takeOrSnooze
                : NotificationAction.details,
            today: isToday,
            dose: o,
          ),
        );
      }
    }

    for (final m in care.lowSupply) {
      final days = m.daysOfSupply;
      list.add(
        NotificationItem(
          id: 'supply:$pid:${m.id}:${m.quantity}',
          tab: NotificationTab.refills,
          label: 'Low Supply Warning',
          time: 'Now',
          title: '${m.name} supply low',
          body:
              'Only ${m.quantity} ${m.quantity == 1 ? 'dose' : 'doses'} '
              'remaining${days == null ? '' : ' (~$days ${days == 1 ? 'day' : 'days'} left)'}. '
              'Record a refill once you\'ve restocked.',
          icon: Icons.medication_liquid,
          tone: NotificationTone.attention,
          action: NotificationAction.refill,
          today: true,
          medicine: m,
        ),
      );
    }

    final until = CareDates.addDays(today, _visitDays + 1);
    for (final v in care.visits) {
      if (v.status != VisitStatus.scheduled ||
          v.startsAt.isBefore(now) ||
          !v.startsAt.isBefore(until)) {
        continue;
      }
      final day = CareDates.dateOnly(v.startsAt);
      final when = CareDates.relative(day, today);
      list.add(
        NotificationItem(
          id: 'visit:$pid:${v.id}:${v.startsAt.millisecondsSinceEpoch}',
          tab: NotificationTab.appointments,
          label: 'Appointment Reminder',
          time: when,
          title: v.title,
          body: [
            '${CareDates.long(day)} at ${CareDates.clockOf(v.startsAt)}',
            if (v.who.isNotEmpty) v.who,
          ].join(' • '),
          icon: Icons.event,
          tone: NotificationTone.info,
          action: NotificationAction.directions,
          today: day == today,
          visit: v,
        ),
      );
    }

    items.assignAll(list);
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    final m = d.inMinutes % 60;
    return '${d.inHours}h${m == 0 ? '' : ' ${m}m'} ago';
  }

  // Buttons

  Future<void> take(NotificationItem n) async {
    final o = n.dose;
    if (o == null) return;
    markRead(n);
    try {
      final result = await care.logDose(o, DoseStatus.taken);
      if (result == WriteResult.pending) {
        showSnack('Saved offline', 'It will sync when you\'re online.');
      }
    } on CareFailure catch (e) {
      showSnack("Couldn't log dose", e.message);
    }
  }

  void snooze(NotificationItem n) {
    final o = n.dose;
    if (o == null) return;
    markRead(n);
    care.snooze(o);
  }

  void open(NotificationItem n) {
    markRead(n);
    final pid = care.profileId;
    if (pid == null) return;
    if (n.visit case final v?) {
      Get.toNamed(
        AppRoutes.visitDetails,
        arguments: VisitDetailsArgs(visitId: v.id, profileId: pid),
      );
    } else if (n.dose case final o?) {
      Get.toNamed(
        AppRoutes.medicineDetails,
        arguments: MedicineDetailsArgs.forDose(o, profileId: pid),
      );
    } else if (n.medicine case final m?) {
      Get.toNamed(
        AppRoutes.medicineDetails,
        arguments: MedicineDetailsArgs(medicineId: m.id, profileId: pid),
      );
    }
  }

  // Read marks, per account, on this device.

  Future<void> _loadRead() async {
    final uid = Get.isRegistered<AuthService>()
        ? Get.find<AuthService>().user.value?.uid
        : null;
    if (uid == null) return;
    _readKey = 'notifications.read.$uid';
    try {
      final prefs = await SharedPreferences.getInstance();
      read.addAll(prefs.getStringList(_readKey!) ?? const []);
    } catch (_) {
      // Read marks are a convenience; without them items show as unread.
    }
  }

  /// Marks to save: other profiles' as they are, and this profile's only
  /// for its current items, so the list doesn't grow forever. Item ids are
  /// "kind:profileId:...".
  @visibleForTesting
  List<String> keptReadMarks() {
    final pid = care.profileId ?? '';
    final ids = items.map((n) => n.id).toSet();
    return read.where((id) {
      final parts = id.split(':');
      final mine = parts.length > 1 && parts[1] == pid;
      return !mine || ids.contains(id);
    }).toList();
  }

  Future<void> _saveRead() async {
    final key = _readKey;
    if (key == null) return;
    final keep = keptReadMarks();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, keep);
    } catch (_) {}
  }
}
