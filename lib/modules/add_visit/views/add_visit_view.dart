import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/repositories/places_repository.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/add_visit_view_model.dart';

const _radius = 16.0;
const _gap6 = SizedBox(height: 6);
Color get _error => AppColors.error;

class AddVisitView extends GetView<AddVisitViewModel> {
  const AddVisitView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppBackBar(title: controller.isEditing ? 'Edit Visit' : 'Add Visit'),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: kSpaceLg),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Intro(),
                  _Categories(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SpecificsCard(),
                        SizedBox(height: kSpaceMd),
                        _ScheduleCard(),
                        SizedBox(height: kSpaceMd),
                        _LocationCard(),
                        SizedBox(height: kSpaceMd),
                        _PrepCard(),
                        SizedBox(height: kSpaceMd),
                        _Notice(),
                        _EditActions(),
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

class _Intro extends GetView<AddVisitViewModel> {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 4),
      child: DmCard(
        color: AppColors.surfaceContainerLow,
        padding: const EdgeInsets.all(kSpaceMd),
        shadow: kShadowSm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DmIconCircle(
              size: 40,
              icon: Icons.edit_calendar,
              iconSize: 22,
              color: AppColors.primaryFixed,
              iconColor: AppColors.onPrimaryFixed,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.isEditing
                        ? 'Edit Healthcare Visit'
                        : 'New Healthcare Visit',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  Obx(() {
                    final name = controller.activeProfile?.fullName;
                    final who = name == null ? 'this' : '$name’s';
                    return Text(
                      'Adding to $who wellness routine. This will display on '
                      'their active timeline and caregiver summary.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Categories extends GetView<AddVisitViewModel> {
  const _Categories();

  static const _icons = {
    'Routine Checkup': Icons.medical_information_outlined,
    'Dentist': Icons.sentiment_satisfied_alt,
    'Specialist': Icons.medical_services_outlined,
    'Lab Test': Icons.biotech_outlined,
    'Telehealth': Icons.videocam_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: kSpaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: kMargin),
            child: _Label('Visit Category', color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 42,
            child: Obx(() {
              final selected = controller.category.value;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(kMargin, 0, kMargin, 4),
                itemCount: AddVisitViewModel.categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (_, i) {
                  final label = AddVisitViewModel.categories[i];
                  return _Chip(
                    label: label,
                    icon: _icons[label]!,
                    iconSize: 18,
                    selected: selected == label,
                    padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
                    onTap: () => controller.selectCategory(label),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SpecificsCard extends GetView<AddVisitViewModel> {
  const _SpecificsCard();

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: _CardTitle(Icons.assignment_outlined, 'Visit Specifics'),
        ),
        _Field(
          label: Row(
            children: [
              const Expanded(child: _Label('Appointment Title / Purpose')),
              Text(
                'Required',
                style: AppTextStyles.labelSm.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          child: Obx(
            () => _Validated(
              error: controller.titleError.value,
              child: _Input(
                controller: controller.title,
                hint: 'e.g. Cardiologist Follow-up',
              ),
            ),
          ),
        ),
        _Field(
          label: const _Label('Doctor / Practitioner'),
          child: _Input(
            controller: controller.doctor,
            hint: 'e.g. Dr. Robert Sterling',
            icon: Icons.person_outline,
          ),
        ),
        _Field(
          label: const _Label('Facility / Clinic'),
          child: _Input(
            controller: controller.clinic,
            hint: 'e.g. St. Jude Dental Clinic',
            icon: Icons.domain,
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends GetView<AddVisitViewModel> {
  const _ScheduleCard();

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.date.value,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) controller.setDate(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: controller.time.value,
    );
    if (picked != null) controller.setTime(picked);
  }

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: _CardTitle(Icons.schedule, 'When is the appointment?'),
            ),
            const SizedBox(width: 8),
            DmTag(
              label: 'Upcoming',
              color: AppColors.secondaryFixed,
              textColor: AppColors.onSecondaryFixed,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _Field(
                label: const _Label('Selected Date'),
                child: Obx(() {
                  final d = controller.date.value;
                  return _PickerBox(
                    title:
                        '${CareDates.weekdays[d.weekday - 1].substring(0, 3)}, '
                        '${CareDates.short(d)}',
                    subtitle: '${d.year}',
                    icon: Icons.calendar_month_outlined,
                    onTap: () => _pickDate(context),
                  );
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                label: const _Label('Time'),
                child: Obx(
                  () => _PickerBox(
                    title: controller.time.value.format(context),
                    subtitle: CareDates.relative(
                      controller.date.value,
                      CareDates.dateOnly(DateTime.now()),
                    ),
                    icon: Icons.access_time,
                    onTap: () => _pickTime(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        Obx(() => _Validated(error: controller.whenError.value)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Gentle Reminders'),
              const SizedBox(height: 4),
              Obx(
                () => Text(
                  'Choose when ${controller.firstName ?? 'they'} and their '
                  'caregiver should receive alerts:',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in AddVisitViewModel.reminderOptions)
                      _Chip(
                        label: r,
                        icon: controller.reminders.contains(r)
                            ? Icons.check
                            : Icons.add,
                        iconSize: 16,
                        gap: 4,
                        selected: controller.reminders.contains(r),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        onTap: () => controller.toggleReminder(r),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends GetView<AddVisitViewModel> {
  const _LocationCard();

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      children: [
        const _CardTitle(Icons.pin_drop_outlined, 'Clinic Location & Contact'),
        _Field(
          label: const _Label('Location Address'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Input(
                controller: controller.address,
                hint: 'Clinic address or medical suite',
                icon: Icons.search,
              ),
              const _PlaceSuggestions(),
            ],
          ),
        ),
        const _MapPreview(),
        _Field(
          label: const _Label('Facility Phone Number'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Obx(
                  () => _Validated(
                    error: controller.phoneError.value,
                    child: _Input(
                      controller: controller.phone,
                      hint: 'e.g. (555) 234-5678',
                      icon: Icons.call_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Test Call Clinic',
                child: Material(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(_radius),
                  child: InkWell(
                    onTap: controller.callClinic,
                    borderRadius: BorderRadius.circular(_radius),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(
                        Icons.ring_volume_outlined,
                        size: 24,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(kSpaceMd),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.commute,
                  size: 22,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Departure Alerts',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      'Notify when it is time to leave based on local '
                      'traffic conditions.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Obx(
                () => DmToggle(
                  label: 'Smart Departure Alerts',
                  value: controller.departureAlerts.value,
                  onTap: controller.toggleDepartureAlerts,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Results of the address search, inline under the field so they scroll
/// with the form and stay above the keyboard.
class _PlaceSuggestions extends GetView<AddVisitViewModel> {
  const _PlaceSuggestions();

  @override
  Widget build(BuildContext context) {
    final hint = AppTextStyles.bodySm.copyWith(
      color: AppColors.onSurfaceVariant,
    );
    return Obx(() {
      final state = controller.placeSearch.value;
      final Widget body = switch (state) {
        PlaceSearch.idle => const SizedBox.shrink(),
        // Suggestion rows to come, in their place.
        PlaceSearch.loading => Skeleton(
          label: 'Searching places',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 2; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Bone.circle(size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BoneColumn(
                          children: [
                            Bone.text(AppTextStyles.labelMd, widthFactor: 0.5),
                            Bone.text(hint, widthFactor: 0.85),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        PlaceSearch.empty => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No matching places. You can keep the address as typed.',
            style: hint,
          ),
        ),
        PlaceSearch.error => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          controller.placeError.value ??
                              'Address search failed.',
                          style: hint,
                        ),
                      ),
                    ),
                    if (controller.placeErrorRetryable.value)
                      TextButton(
                        onPressed: controller.retryPlaceSearch,
                        child: const Text('Retry'),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            // A place that couldn't be opened: the others can still be
            // chosen.
            if (controller.suggestions.isNotEmpty)
              ..._suggestionRows(controller.suggestions, hint),
          ],
        ),
        PlaceSearch.results => Column(
          mainAxisSize: MainAxisSize.min,
          children: _suggestionRows(controller.suggestions, hint),
        ),
      };
      if (state == PlaceSearch.idle) return body;
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: kShadowSm,
        ),
        child: body,
      );
    });
  }

  /// The suggestion rows and Google's attribution under them.
  List<Widget> _suggestionRows(List<PlaceSuggestion> list, TextStyle hint) => [
    for (final s in list)
      InkWell(
        onTap: () => controller.selectPlace(s),
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      s.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: hint,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    // Required attribution when not showing a Google map.
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text('Powered by Google', style: hint),
      ),
    ),
  ];
}

/// Stand-in for the reference's static map photo, which is not bundled.
class _MapPreview extends GetView<AddVisitViewModel> {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
        height: 144,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.center,
            // A dark scrim under light text, the same in both themes.
            colors: [const Color(0xE6191B2A), AppColors.surfaceContainerHigh],
          ),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              size: 20,
              color: AppPalette.dark.onSelected,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Obx(
                () => Text(
                  controller.selectedPlace.value?.name ??
                      'Choose an address from the suggestions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppPalette.dark.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepCard extends GetView<AddVisitViewModel> {
  const _PrepCard();

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      children: [
        const _CardTitle(Icons.checklist, 'Things to Bring & Preparation'),
        _Field(
          label: const _Label('Caregiver & Patient Reminders'),
          child: _Input(
            controller: controller.notes,
            hint:
                'e.g. Bring updated medication list, glasses, and new '
                'Medicare card...',
            minLines: 3,
            style: AppTextStyles.bodyMd.copyWith(height: 1.625),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in AddVisitViewModel.prepSuggestions)
              Material(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () => controller.addPrep(p),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: AppColors.onSurface),
                        const SizedBox(width: 4),
                        Text(
                          p,
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline, size: 18, color: AppColors.outline),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Appointments are safely stored locally on your device for '
              'schedule coordination and family caregiver reminders. This '
              'tool does not directly link to hospital EMR or clinical '
              'portals.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends GetView<AddVisitViewModel> {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final saving = controller.saving.value;
      return Row(
        children: [
          if (!controller.isEditing) ...[
            Expanded(
              flex: 2,
              child: DmPill(
                color: AppColors.surfaceContainerLow,
                minHeight: 48,
                expand: true,
                onTap: saving ? null : Get.back,
                children: [
                  Text(
                    'Cancel',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 3,
            child: DmWideButton(
              label: controller.isEditing ? 'Save Changes' : 'Save Appointment',
              icon: Icons.check_circle,
              height: 48,
              compact: true,
              color: AppColors.primaryContainer,
              onTap: saving ? null : controller.save,
            ),
          ),
        ],
      );
    });
  }
}

/// Cancelling or deleting a visit stays at the end of the form, apart from
/// the save button.
class _EditActions extends GetView<AddVisitViewModel> {
  const _EditActions();

  @override
  Widget build(BuildContext context) {
    if (!controller.isEditing) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: kSpaceMd),
      child: Obx(() {
        final saving = controller.saving.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DmPill(
              color: AppColors.surfaceContainerLow,
              minHeight: 48,
              expand: true,
              onTap: saving ? null : controller.cancelVisit,
              children: [
                Text(
                  'Cancel Visit',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DmPill(
              color: Colors.transparent,
              minHeight: 48,
              expand: true,
              onTap: saving ? null : controller.deleteVisit,
              children: [
                Icon(Icons.delete_outline, size: 18, color: _error),
                const SizedBox(width: 6),
                Text(
                  'Delete Visit',
                  style: AppTextStyles.labelMd.copyWith(color: _error),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// A field with its validation message underneath.
class _Validated extends StatelessWidget {
  const _Validated({required this.error, this.child});

  final String? error;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final message = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?child,
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              message,
              style: AppTextStyles.labelSm.copyWith(color: _error),
            ),
          ),
      ],
    );
  }
}

// Form building blocks.

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

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

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.color});

  final String text;

  /// Defaults to secondary text.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelMd.copyWith(
        color: color ?? AppColors.onSurfaceVariant,
      ),
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
      children: [label, _gap6, child],
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.hint,
    this.icon,
    this.keyboardType,
    this.minLines,
    this.style,
  });

  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final int? minLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final multiline = minLines != null;
    final text = (style ?? AppTextStyles.bodyLg).copyWith(
      color: AppColors.onSurface,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide.none,
    );
    final field = TextField(
      controller: controller,
      keyboardType: multiline ? TextInputType.multiline : keyboardType,
      minLines: minLines,
      // Single-line fields sit in a fixed 56px box with the text centred.
      maxLines: multiline ? null : 1,
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
        contentPadding: EdgeInsets.fromLTRB(
          icon == null ? kSpaceMd : 0,
          multiline ? kSpaceMd : 14,
          kSpaceMd,
          multiline ? kSpaceMd : 14,
        ),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(minWidth: 48),
        border: border,
        // A visible edge on any surface, indigo while typing.
        enabledBorder: border.copyWith(
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
    return multiline ? field : SizedBox(height: 56, child: field);
  }
}

class _PickerBox extends StatelessWidget {
  const _PickerBox({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.selected,
    required this.padding,
    required this.onTap,
    this.gap = 6,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final bool selected;
  final EdgeInsets padding;
  final VoidCallback onTap;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.onSurface;
    return Semantics(
      selected: selected,
      child: DmPill(
        color: selected
            ? AppColors.primaryContainer
            : AppColors.surfaceContainerLow,
        shadow: selected ? kShadowSm : null,
        padding: padding,
        onTap: onTap,
        children: [
          Icon(icon, size: iconSize, color: fg),
          SizedBox(width: gap),
          Text(label, style: AppTextStyles.labelMd.copyWith(color: fg)),
        ],
      ),
    );
  }
}
