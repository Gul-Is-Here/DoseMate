import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/medicine.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/medicine_details_view_model.dart';

const _radiusLg = 32.0;
const _radiusXl = 48.0;

/// "label-sm uppercase tracking-wider".
TextStyle _overline(Color color) =>
    AppTextStyles.labelSm.copyWith(color: color, letterSpacing: 1.2);

class MedicineDetailsView extends GetView<MedicineDetailsViewModel> {
  const MedicineDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppBackBar(title: 'Medication Details'),
          Expanded(
            child: Obx(
              () => switch (controller.state) {
                DetailsState.loading => const _DetailsSkeleton(),
                DetailsState.error => const _Message(
                  icon: Icons.cloud_off,
                  title: 'Couldn’t load this medicine',
                  retry: true,
                ),
                DetailsState.unavailable => const _Message(
                  icon: Icons.medication_outlined,
                  title: 'This medicine is no longer available',
                  body:
                      'It may have been deleted or belongs to another '
                      'profile.',
                ),
                DetailsState.ready => const _Details(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        bottom: 40 + MediaQuery.paddingOf(context).bottom,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusRow(),
          Padding(
            padding: EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReminderCard(),
                SizedBox(height: kSpaceMd),
                _HeroCard(),
                SizedBox(height: kSpaceMd),
                _NoteCard(),
                SizedBox(height: kSpaceMd + 4),
                _Actions(),
                SizedBox(height: kSpaceMd + 8),
                _HelpCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [_Details] while the medicine loads: status, reminder, hero and note.
class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Skeleton(
        label: 'Loading medicine',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 8),
              child: Row(
                children: [
                  const Bone.circle(size: 12),
                  const SizedBox(width: 8),
                  Bone.text(_overline(AppColors.primary), width: 120),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonCard(
                    radius: _radiusLg,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Bone.circle(size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BoneColumn(
                            children: [
                              Bone.text(
                                AppTextStyles.labelSm,
                                widthFactor: 0.4,
                              ),
                              Bone.text(
                                AppTextStyles.titleMd,
                                widthFactor: 0.7,
                              ),
                              Bone.text(AppTextStyles.bodySm, widthFactor: 0.5),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  SkeletonCard(
                    radius: _radiusXl,
                    shadow: kShadowMd,
                    padding: const EdgeInsets.all(kSpaceLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Bone(width: 120, height: 26, radius: 999),
                        const SizedBox(height: 12),
                        Bone.text(
                          AppTextStyles.headlineLgMobile,
                          widthFactor: 0.65,
                        ),
                        const SizedBox(height: 4),
                        Bone.text(AppTextStyles.titleMd, widthFactor: 0.35),
                        const SizedBox(height: 20),
                        const Bone(height: 88, radius: _radiusLg),
                      ],
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  const SkeletonCard(
                    radius: _radiusLg,
                    child: Bone(height: 48, radius: 999),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends GetView<MedicineDetailsViewModel> {
  const _StatusRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 8),
      child: Row(
        children: [
          Obx(
            () => DmDot(
              size: 12,
              color: controller.isAttention
                  ? AppColors.secondaryContainer
                  : AppColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Obx(
              () => Text(
                controller.statusLabel.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _overline(
                  controller.isAttention
                      ? AppColors.secondary
                      : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Minimize Reminder',
            child: Material(
              color: AppColors.surfaceContainer,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: controller.close,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends GetView<MedicineDetailsViewModel> {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      radius: _radiusLg,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          DmIconCircle(
            size: 44,
            icon: Icons.schedule,
            iconSize: 24,
            color: AppColors.surfaceContainerHigh,
            iconColor: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() {
              final time = controller.reminderTime;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder Alert',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      text: time ?? 'No scheduled time',
                      style: AppTextStyles.titleMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                      children: [
                        if (time != null)
                          TextSpan(
                            text: ' ${controller.reminderPart}',
                            style: AppTextStyles.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant)
                                .weight(FontWeight.w400),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(width: 8),
          Obx(() {
            final syncing = controller.isSyncing;
            return Tooltip(
              message: syncing
                  ? 'Saved on this device, waiting to sync'
                  : 'Synced with your account',
              child: DmPill(
                color: AppColors.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  Icon(
                    syncing ? Icons.sync : Icons.verified_user_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    syncing ? 'Syncing' : 'CareSync',
                    style: AppTextStyles.labelSm
                        .copyWith(color: AppColors.onSurface)
                        .weight(FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HeroCard extends GetView<MedicineDetailsViewModel> {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(_radiusXl),
        boxShadow: kShadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -32,
            top: -32,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kSpaceLg),
            child: Obx(() {
              final m = controller.medicine;
              // Briefly null while the screen swaps to "unavailable".
              if (m == null) return const SizedBox.shrink();
              final name = controller.profile?.fullName;
              final course = controller.courseLabel;
              return Column(
                children: [
                  const _PillBadge(),
                  const SizedBox(height: kSpaceMd),
                  if (name != null)
                    DmPill(
                      color: AppColors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'For $name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    m.name,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLgMobile.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (m.dosage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      m.dosage,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMd.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (m.notes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(kSpaceMd),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(_radiusLg),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: DmIconCircle(
                              size: 32,
                              icon: Icons.restaurant,
                              iconSize: 18,
                              color: AppColors.surfaceContainerHighest,
                              iconColor: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PATIENT DIRECTIONS',
                                  style: _overline(AppColors.onSurfaceVariant),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '“${m.notes}”',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.onSurface,
                                    fontStyle: FontStyle.italic,
                                    height: 1.625,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            controller.quantityLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (course != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.history,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            course,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// The reference's two-tone capsule in its pulsing circles.
class _PillBadge extends StatelessWidget {
  const _PillBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 80,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: CustomPaint(painter: _CapsulePainter()),
        ),
      ),
    );
  }
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    // Soft shadow capsule, rotated -30° about (8, 18).
    canvas
      ..save()
      ..translate(8, 18)
      ..rotate(-30 * 3.141592653589793 / 180)
      ..drawRRect(
        RRect.fromLTRBR(0, 0, 32, 12, const Radius.circular(6)),
        Paint()..color = AppColors.primary.withValues(alpha: 0.15),
      )
      ..restore();
    final top = Path()
      ..moveTo(12.5, 15.4)
      ..lineTo(22.9, 9.4)
      ..cubicTo(26.2, 7.5, 30.5, 8.6, 32.4, 11.9)
      ..lineTo(35.6, 17.4)
      ..lineTo(20.8, 25.9)
      ..lineTo(17.6, 20.4)
      ..cubicTo(15.7, 17.1, 16.8, 12.8, 12.5, 15.4)
      ..close();
    final bottom = Path()
      ..moveTo(20.8, 25.9)
      ..lineTo(35.6, 17.4)
      ..lineTo(38.8, 22.9)
      ..cubicTo(40.7, 26.2, 39.6, 30.5, 36.3, 32.4)
      ..lineTo(25.9, 38.4)
      ..cubicTo(22.6, 40.3, 18.3, 39.2, 16.4, 35.9)
      ..lineTo(13.2, 30.4)
      ..lineTo(20.8, 25.9)
      ..close();
    canvas
      ..drawPath(top, Paint()..color = AppColors.primary)
      ..drawPath(bottom, Paint()..color = AppColors.secondaryContainer)
      ..drawCircle(
        const Offset(27, 22),
        1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) => false;
}

class _NoteCard extends GetView<MedicineDetailsViewModel> {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide.none,
    );
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      radius: _radiusLg,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Optional Dose Note',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                'Saves to log',
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)
                    .weight(FontWeight.w400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Obx(
            () => SizedBox(
              height: 56,
              child: TextField(
                controller: controller.note,
                maxLines: 1,
                enabled: controller.canLog,
                textAlignVertical: TextAlignVertical.center,
                style: text,
                cursorColor: AppColors.primary,
                scrollPadding: const EdgeInsets.all(160),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'e.g., took 15 mins late with warm soup...',
                  hintStyle: text.copyWith(color: AppColors.onSurfaceVariant),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  suffixIcon: controller.hasNote.value
                      ? IconButton(
                          tooltip: 'Clear note',
                          onPressed: controller.note.clear,
                          icon: Icon(
                            Icons.cancel,
                            size: 18,
                            color: AppColors.outline,
                          ),
                        )
                      : null,
                  border: border,
                  enabledBorder: border.copyWith(
                    borderSide: BorderSide(color: AppColors.outline),
                  ),
                  disabledBorder: border.copyWith(
                    borderSide: BorderSide(color: AppColors.outlineVariant),
                  ),
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ),
          ),
          Obx(() {
            final error = controller.noteError.value;
            return error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      error,
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  );
          }),
        ],
      ),
    );
  }
}

class _Actions extends GetView<MedicineDetailsViewModel> {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final log = controller.log;
      if (log != null) return _Logged(log: log);
      final enabled = controller.canLog && !controller.isBusy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DmPill(
            color: enabled
                ? AppColors.primaryContainer
                : AppColors.primaryContainer.withValues(alpha: 0.6),
            minHeight: 58,
            expand: true,
            shadow: kShadowMd,
            onTap: enabled ? controller.markTaken : null,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 24,
                color: AppColors.onPrimary,
              ),
              const SizedBox(width: 12),
              Text(
                'Mark as Taken',
                style: AppTextStyles.labelLg.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DmPill(
                  color: AppColors.secondaryFixed,
                  minHeight: 56,
                  expand: true,
                  onTap: enabled ? controller.snooze : null,
                  children: [
                    Icon(Icons.snooze, size: 20, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Snooze (15m)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelMd.copyWith(
                          color: AppColors.onSecondaryFixed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DmPill(
                  color: AppColors.surfaceContainerHigh,
                  minHeight: 56,
                  expand: true,
                  onTap: enabled ? controller.skip : null,
                  children: [
                    Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Skip Dose',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// Replaces the buttons once this dose is recorded.
class _Logged extends GetView<MedicineDetailsViewModel> {
  const _Logged({required this.log});

  final DoseLog log;

  @override
  Widget build(BuildContext context) {
    final taken = log.status == DoseStatus.taken;
    final fg = taken ? AppColors.success : AppColors.neutral;
    return DmCard(
      color: taken ? AppColors.successContainer : AppColors.neutralContainer,
      radius: _radiusLg,
      padding: const EdgeInsets.fromLTRB(kSpaceMd, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            taken ? Icons.task_alt : Icons.do_not_disturb_on_outlined,
            size: 24,
            color: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.statusLabel,
                  style: AppTextStyles.labelMd.copyWith(color: fg),
                ),
                if (log.note case final note? when note.isNotEmpty)
                  Text(
                    '“$note”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.isBusy ? null : controller.undo,
            child: Text(
              'Undo',
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends GetView<MedicineDetailsViewModel> {
  const _HelpCard();

  Future<void> _openSheet() => Get.bottomSheet(
    const _PastDoseSheet(),
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusLg)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLow,
      radius: _radiusLg,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: DmIconCircle(
              size: 32,
              icon: Icons.help_outline,
              iconSize: 18,
              color: AppColors.surfaceContainer,
              iconColor: AppColors.outline,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unmarked or Past Dose?',
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.onSurface)
                      .weight(FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'If you took this medication earlier or need to adjust '
                  'times, update anytime. DoseMate keeps your timeline '
                  'accurate without assuming clinical outcomes.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.625,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _openSheet,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Log custom time or edit schedule',
                          style: AppTextStyles.labelMd.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists missed doses from today and yesterday to log, plus Edit schedule.
class _PastDoseSheet extends GetView<MedicineDetailsViewModel> {
  const _PastDoseSheet();

  @override
  Widget build(BuildContext context) {
    final doses = controller.pastUnlogged;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kMargin,
          kSpaceLg,
          kMargin,
          kSpaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Log a past dose',
              style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              doses.isEmpty
                  ? 'No unlogged doses from today or yesterday.'
                  : 'Mark one of these as taken.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final o in doses)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history, color: AppColors.primary),
                title: Text(controller.doseLabel(o)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => controller.logPast(o),
              ),
            const SizedBox(height: 8),
            DmPill(
              color: AppColors.surfaceContainer,
              minHeight: 48,
              expand: true,
              onTap: controller.editSchedule,
              children: [
                Icon(
                  Icons.edit_calendar_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Edit schedule',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends GetView<MedicineDetailsViewModel> {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.retry = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DmIconCircle(
              size: 64,
              icon: icon,
              iconSize: 32,
              color: AppColors.surfaceContainer,
              iconColor: AppColors.primary,
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
            ),
            const SizedBox(height: 4),
            if (retry)
              Obx(
                () => Text(
                  controller.loadError ?? 'Please try again.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Text(
                body!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: kSpaceLg),
            DmWideButton(
              label: retry ? 'Retry' : 'Go Back',
              icon: retry ? Icons.refresh : Icons.arrow_back,
              height: 48,
              onTap: retry ? controller.retry : controller.close,
            ),
          ],
        ),
      ),
    );
  }
}
