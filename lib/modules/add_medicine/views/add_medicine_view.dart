import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../widgets/app_shell.dart';
import '../../../data/models/medicine.dart';
import '../view_model/add_medicine_view_model.dart';

const _radius = 16.0;
Color get _error => AppColors.error;

String _shortDate(DateTime d) => CareDates.short(d);

TextStyle get _labelStyle =>
    AppTextStyles.labelMd.copyWith(color: AppColors.onSurface);
TextStyle get _hintStyle =>
    AppTextStyles.labelSm.copyWith(color: AppColors.onSurfaceVariant);
TextStyle get _titleStyle =>
    AppTextStyles.titleMd.copyWith(color: AppColors.onSurface);

class AddMedicineView extends GetView<AddMedicineViewModel> {
  const AddMedicineView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppBackBar(
            title: controller.isEditing ? 'Edit Medication' : 'Add Medication',
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: kSpaceLg),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Progress(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AssignPill(),
                        SizedBox(height: kSpaceLg),
                        _IdentityCard(),
                        SizedBox(height: kSpaceLg),
                        _ScheduleCard(),
                        SizedBox(height: kSpaceLg),
                        _SupplyCard(),
                        SizedBox(height: kSpaceLg),
                        _Notice(),
                        _DeleteAction(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pinned, so saving never needs a scroll to the end.
          const DmActionBar(child: _Actions()),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkWell(
                onTap: Get.back,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: DmTag(
                    label: 'STEP 2 OF 3: SCHEDULE & INSTRUCTIONS',
                    color: AppColors.primaryFixed.withValues(alpha: 0.4),
                    textColor: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignPill extends GetView<AddMedicineViewModel> {
  const _AssignPill();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DmPill(
        color: AppColors.surfaceContainer,
        shadow: kShadowSm,
        tooltip: controller.isEditing ? null : 'Choose profile',
        onTap: controller.isEditing ? null : controller.openProfiles,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Icon(Icons.account_circle, size: 20, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Obx(
              () => Text(
                'Assign to: ${controller.assigneeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle,
              ),
            ),
          ),
          if (!controller.isEditing) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _IdentityCard extends GetView<AddMedicineViewModel> {
  const _IdentityCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        _CardHeader(
          icon: Icons.medication,
          circle: AppColors.primaryFixed.withValues(alpha: 0.5),
          iconColor: AppColors.primary,
          title: 'Medication Identity',
        ),
        _Field(
          label: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Medicine Name '),
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: _error),
                      ),
                    ],
                  ),
                  style: _labelStyle,
                ),
              ),
              Obx(
                () => controller.hasName.value
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'Verified label',
                            style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          child: Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Input(
                  controller: controller.name,
                  hint: 'e.g., Amoxicillin',
                  hasError: controller.nameError.value != null,
                  trailing: controller.hasName.value
                      ? Icon(
                          Icons.check_circle_outline,
                          size: 24,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                _ErrorText(controller.nameError.value),
              ],
            ),
          ),
        ),
        _Field(
          label: Row(
            children: [
              Expanded(child: Text('Strength & Dosage', style: _labelStyle)),
              Text(
                'Optional',
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)
                    .weight(FontWeight.w400),
              ),
            ],
          ),
          child: _Input(
            controller: controller.dosage,
            hint: 'e.g., 500mg - 1 capsule',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _Field(
            label: Text('Visual Reference', style: _labelStyle),
            child: _Tile(
              onTap: controller.pickPhoto,
              padding: const EdgeInsets.all(kSpaceMd),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(_radius),
                    ),
                    child: Obx(() {
                      final file = controller.photo.value;
                      final url = controller.photoUrl.value;
                      final placeholder = Icon(
                        Icons.photo_camera_outlined,
                        size: 28,
                        color: AppColors.primaryContainer,
                      );
                      if (file != null) {
                        return Image.file(file, fit: BoxFit.cover);
                      }
                      if (url != null) {
                        return Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => placeholder,
                        );
                      }
                      return placeholder;
                    }),
                  ),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attach prescription or box photo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _labelStyle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Optional reference only — not clinically '
                          'analyzed or verified.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _hintStyle.copyWith(height: 1.25),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: kSpaceMd),
                  _CircleButton(
                    tooltip: 'Upload photo',
                    icon: Icons.add_a_photo_outlined,
                    size: 40,
                    iconSize: 20,
                    color: AppColors.surfaceContainerLowest,
                    iconColor: AppColors.onSurface,
                    shadow: kShadowSm,
                    onTap: controller.pickPhoto,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends GetView<AddMedicineViewModel> {
  const _ScheduleCard();

  Future<void> _addTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null) controller.addDose(picked);
  }

  Future<void> _pickStart(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.startDate.value,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) controller.setStartDate(picked);
  }

  Future<void> _pickEnd(BuildContext context) async {
    final start = controller.startDate.value;
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.endDate,
      firstDate: start.add(const Duration(days: 1)),
      lastDate: DateTime(start.year + 5),
    );
    if (picked != null) controller.setEndDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        _CardHeader(
          icon: Icons.calendar_month,
          circle: AppColors.secondaryFixed.withValues(alpha: 0.5),
          iconColor: AppColors.secondary,
          title: 'Schedule Routine',
        ),
        _Field(
          label: Text('Frequency Type', style: _labelStyle),
          child: Obx(() {
            final selected = controller.frequency.value;
            Widget option(Frequency f) => Expanded(
              child: _FrequencyOption(
                label: f.label,
                selected: selected == f,
                onTap: () => controller.selectFrequency(f),
              ),
            );
            Widget row(Frequency a, Frequency b) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [option(a), const SizedBox(width: 4), option(b)],
              ),
            );
            return Column(
              children: [
                row(Frequency.onceDaily, Frequency.multipleDaily),
                const SizedBox(height: 4),
                row(Frequency.specificDays, Frequency.asNeeded),
                if (selected == Frequency.specificDays) ...[
                  const SizedBox(height: 8),
                  _DayPicker(
                    selected: controller.days.toSet(),
                    onToggle: controller.toggleDay,
                  ),
                ],
              ],
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reminders & Times', style: _labelStyle),
              Obx(
                () => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, minutes) in controller.doses.indexed) ...[
                      const SizedBox(height: 8),
                      _DoseRow(
                        minutes: minutes,
                        note: controller.doseNote(minutes),
                        onRemove: () => controller.removeDose(i),
                      ),
                    ],
                    _ErrorText(controller.scheduleError.value),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Tile(
                color: AppColors.surfaceContainer,
                onTap: () => _addTime(context),
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceMd,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Add another reminder time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Obx(() {
            final start = controller.startDate.value;
            final days = controller.courseDays.value;
            final isToday = DateUtils.isSameDay(start, DateTime.now());
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _DateTile(
                      label: Text('Start Date', style: _hintStyle),
                      icon: Icons.event,
                      iconColor: AppColors.primary,
                      value: isToday
                          ? 'Today, ${_shortDate(start)}'
                          : _shortDate(start),
                      onTap: () => _pickStart(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateTile(
                      label: Row(
                        children: [
                          Expanded(child: Text('End Date', style: _hintStyle)),
                          Text(
                            'Active',
                            style: AppTextStyles.labelSm
                                .copyWith(color: AppColors.primary)
                                .weight(FontWeight.w500),
                          ),
                        ],
                      ),
                      icon: Icons.event_available,
                      iconColor: AppColors.secondary,
                      value:
                          '$days-day course (${_shortDate(controller.endDate)})',
                      onTap: () => _pickEnd(context),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        _Field(
          label: Text('Personal Instructions & Notes', style: _labelStyle),
          child: _Input(
            controller: controller.notes,
            style: AppTextStyles.bodyMd,
            trailing: Icon(
              Icons.local_drink_outlined,
              size: 20,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _FrequencyOption extends StatelessWidget {
  const _FrequencyOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.onSurface;
    return Semantics(
      selected: selected,
      child: _Tile(
        color: selected
            ? AppColors.primaryContainer
            : AppColors.surfaceContainerLow,
        shadow: selected ? kShadowSm : null,
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 18, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMd.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({
    required this.minutes,
    required this.note,
    required this.onRemove,
  });

  final int minutes;
  final String note;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final clock = CareDates.clock(minutes);
    final time = clock.length == 7 ? '0$clock' : clock;
    final daytime = minutes >= 5 * 60 && minutes < 17 * 60;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          DmIconCircle(
            size: 40,
            icon: daytime ? Icons.wb_twilight : Icons.dark_mode_outlined,
            iconSize: 20,
            color: daytime
                ? AppColors.primaryFixed.withValues(alpha: 0.4)
                : AppColors.secondaryFixed.withValues(alpha: 0.5),
            iconColor: daytime ? AppColors.primary : AppColors.secondary,
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: _titleStyle.weight(FontWeight.w700)),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hintStyle,
                ),
              ],
            ),
          ),
          _CircleButton(
            tooltip: 'Remove $time',
            icon: Icons.close,
            size: 36,
            iconSize: 20,
            color: Colors.transparent,
            iconColor: AppColors.onSurfaceVariant,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onTap,
  });

  final Widget label;
  final IconData icon;
  final Color iconColor;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplyCard extends GetView<AddMedicineViewModel> {
  const _SupplyCard();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.all(kSpaceLg),
      shadow: kShadowSm,
      child: Obx(() {
        final open = controller.supplyExpanded.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: open,
              label: 'Supply & Refill Tracking',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.toggleSupply,
                child: Row(
                  children: [
                    DmIconCircle(
                      size: 36,
                      icon: Icons.inventory_2_outlined,
                      iconSize: 20,
                      color: AppColors.surfaceContainer,
                      iconColor: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Supply & Refill Tracking', style: _titleStyle),
                          Text(
                            'Keep inventory synchronized',
                            style: _hintStyle,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.expand_more,
                        size: 24,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              const SizedBox(height: kSpaceMd + 4),
              _SettingRow(
                title: 'Quantity on hand',
                subtitle: 'Remaining in current bottle',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CircleButton(
                      tooltip: 'Decrease pills',
                      icon: Icons.remove,
                      size: 36,
                      iconSize: 18,
                      color: AppColors.surfaceContainer,
                      iconColor: AppColors.onSurface,
                      onTap: () => controller.changeQuantity(-1),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      constraints: const BoxConstraints(minWidth: 72),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: kShadowSm,
                      ),
                      child: Text(
                        '${controller.quantity.value} left',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelLg
                            .copyWith(color: AppColors.onSurface)
                            .weight(FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _CircleButton(
                      tooltip: 'Increase pills',
                      icon: Icons.add,
                      size: 36,
                      iconSize: 18,
                      color: AppColors.surfaceContainer,
                      iconColor: AppColors.onSurface,
                      onTap: () => controller.changeQuantity(1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceMd),
              _SettingRow(
                title: 'Low supply warning',
                subtitle: controller.lowSupplyLabel,
                trailing: DmToggle(
                  label: 'Low supply warning',
                  value: controller.lowSupplyWarning.value,
                  onTap: controller.toggleLowSupplyWarning,
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _labelStyle),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: kSpaceMd),
          trailing,
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.verified_user_outlined,
              size: 24,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User Record Notice',
                  style: _labelStyle.weight(FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter details exactly as specified by your healthcare '
                  'provider or prescription label. DoseMate does not suggest '
                  'doses or verify drug interactions.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.625,
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

class _Actions extends GetView<AddMedicineViewModel> {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final saving = controller.saving.value;
      final editing = controller.editing;
      final canDraft =
          editing == null || editing.status == MedicineStatus.draft;
      return Row(
        children: [
          if (canDraft) ...[
            Expanded(
              flex: 2,
              child: DmPill(
                color: AppColors.surfaceContainerLow,
                minHeight: 48,
                expand: true,
                onTap: saving ? null : () => controller.save(draft: true),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Flexible(
                    child: Text(
                      'Save Draft',
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
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 3,
            child: DmPill(
              color: AppColors.primaryContainer,
              minHeight: 48,
              expand: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onTap: saving ? null : controller.save,
              children: [
                Flexible(
                  child: Text(
                    editing == null ? 'Review Details & Save' : 'Save Changes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMd
                        .copyWith(color: AppColors.onPrimary)
                        .weight(FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
                saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: AppColors.onPrimary,
                      ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// Delete stays at the end of the form, apart from the save buttons.
class _DeleteAction extends GetView<AddMedicineViewModel> {
  const _DeleteAction();

  @override
  Widget build(BuildContext context) {
    if (controller.editing == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: kSpaceMd),
      child: Obx(
        () => DmPill(
          color: Colors.transparent,
          minHeight: 48,
          expand: true,
          onTap: controller.saving.value ? null : controller.delete,
          children: [
            Icon(Icons.delete_outline, size: 18, color: _error),
            const SizedBox(width: 6),
            Text(
              'Delete Medicine',
              style: AppTextStyles.labelMd.copyWith(color: _error),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mon–Sun toggles for the Specific days frequency.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var day = 1; day <= 7; day++) ...[
          if (day > 1) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: selected.contains(day),
              label: CareDates.weekdays[day - 1],
              child: _Tile(
                color: selected.contains(day)
                    ? AppColors.primaryContainer
                    : AppColors.surfaceContainerLow,
                onTap: () => onToggle(day),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ExcludeSemantics(
                  child: Text(
                    CareDates.weekdays[day - 1].substring(0, 1),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelMd.copyWith(
                      color: selected.contains(day)
                          ? AppColors.onPrimary
                          : AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(text, style: AppTextStyles.labelSm.copyWith(color: _error)),
    );
  }
}

// Building blocks.

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.all(kSpaceLg),
      shadow: kShadowSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(height: kSpaceMd),
            child,
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.circle,
    required this.iconColor,
    required this.title,
  });

  final IconData icon;
  final Color circle;
  final Color iconColor;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DmIconCircle(
          size: 36,
          icon: icon,
          iconSize: 20,
          color: circle,
          iconColor: iconColor,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(title, style: _titleStyle)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final Widget label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [label, const SizedBox(height: 4), child],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.child,
    required this.onTap,
    required this.padding,
    this.color,
    this.shadow,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;

  /// Defaults to the raised input surface.
  final Color? color;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(_radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadow),
      child: Material(
        color: color ?? AppColors.surfaceContainerLow,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.color,
    required this.iconColor,
    this.onTap,
    this.shadow,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadow),
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap ?? () {},
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.hint,
    this.trailing,
    this.style,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String? hint;
  final Widget? trailing;
  final TextStyle? style;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final text = (style ?? AppTextStyles.bodyLg).copyWith(
      color: AppColors.onSurface,
    );
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: side,
        );
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        maxLines: 1,
        textAlignVertical: TextAlignVertical.center,
        style: text,
        cursorColor: AppColors.primary,
        scrollPadding: const EdgeInsets.all(80),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: text.copyWith(color: AppColors.onSurfaceVariant),
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          isCollapsed: true,
          contentPadding: const EdgeInsets.fromLTRB(kSpaceMd, 14, kSpaceMd, 14),
          suffixIcon: trailing == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: trailing,
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 0),
          border: border(),
          enabledBorder: border(
            BorderSide(color: hasError ? _error : AppColors.outline),
          ),
          focusedBorder: border(
            BorderSide(
              color: hasError ? _error : AppColors.primaryContainer,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}
