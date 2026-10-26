import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/profile_avatar.dart';
import '../../signup/view_model/signup_view_model.dart';
import '../view_model/profile_setup_view_model.dart';
import '../widgets/profile_field_card.dart';
import '../widgets/profile_option_card.dart';

class ProfileSetupView extends GetView<ProfileSetupViewModel> {
  const ProfileSetupView({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _Header(
          onBack: controller.canGoBack ? controller.back : null,
          onSkip: controller.skip,
          avatar: Obx(
            () => ProfileAvatar(
              size: 32,
              file: controller.pendingPhoto.value,
              url: controller.savedPhotoUrl,
            ),
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            top: topInset + 64,
            bottom: MediaQuery.paddingOf(context).bottom + 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Stepper(),
              const _Intro(),
              Obx(
                () => controller.loadError.value != null
                    ? _LoadErrorBanner(
                        message: controller.loadError.value!,
                        onRetry: controller.retryLoad,
                      )
                    : controller.isLoading.value
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: LinearProgressIndicator(
                          color: AppColors.primaryContainer,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.all(Radius.circular(9999)),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // Locked until saved values arrive so nothing typed is overwritten.
                child: Obx(
                  () => AbsorbPointer(
                    absorbing: controller.isLoading.value,
                    child: _form(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ProfileOwnerSelector(controller: controller),
      const SizedBox(height: 24),
      _AvatarPicker(controller: controller),
      const SizedBox(height: 24),
      _Fields(controller: controller),
      const SizedBox(height: 24),
      const _PrivacyPromise(),
      const SizedBox(height: 24),
      const _NextStepBanner(),
      const SizedBox(height: 32),
      Obx(
        () => PrimaryButton(
          label: 'Save & Continue',
          loading: controller.isSaving.value,
          onPressed: controller.saveAndContinue,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'You can adjust this profile anytime in family settings',
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSm.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.onSkip,
    required this.avatar,
  });

  /// Hidden when there is nothing to go back to.
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A132238),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (onBack != null)
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: IconButton(
                          onPressed: onBack,
                          tooltip: 'Go back',
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          icon: Icon(
                            Icons.arrow_back,
                            size: 24,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    // Brand mark used across the app; the design's logo image
                    // is not in the project assets.
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.medication,
                        size: 18,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Settings',
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onSurfaceVariant,
                        shape: const StadiumBorder(),
                      ),
                      child: Text('Skip', style: AppTextStyles.labelMd),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(child: avatar),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'STEP 1 OF 2',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 0.05 * 12,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  'Next: Reminders',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(color: AppColors.surfaceContainerHigh),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.spa, size: 16, color: AppColors.onPrimaryFixed),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Gentle Health Companion',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.onPrimaryFixed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Who are we caring for?',
            style: AppTextStyles.headlineLgMobile.copyWith(
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'We personalize reminders, tone, and dosage alerts based on who is '
            'taking the medication.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileOwnerSelector extends StatelessWidget {
  const _ProfileOwnerSelector({required this.controller});

  final ProfileSetupViewModel controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select profile owner',
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final selected = controller.profileFor.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileOptionCard(
                title: 'For myself',
                tag: 'Primary',
                description: 'I will manage and take my own scheduled doses',
                icon: Icons.person,
                iconColor: AppColors.primary,
                selected: selected == AccountFor.myself,
                onTap: () => controller.selectProfileFor(AccountFor.myself),
              ),
              const SizedBox(height: 12),
              ProfileOptionCard(
                title: 'Parent, spouse, or loved one',
                description:
                    'I am coordinating or assisting their health schedule',
                icon: Icons.family_restroom,
                iconColor: AppColors.secondary,
                selected: selected == AccountFor.caregiver,
                onTap: () => controller.selectProfileFor(AccountFor.caregiver),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.controller});

  final ProfileSetupViewModel controller;

  Future<void> _choose(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await controller.choosePhoto(source);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(48),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => _choose(context),
                  child: Obx(() {
                    final progress = controller.uploadProgress.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        ProfileAvatar(
                          size: 64,
                          file: controller.pendingPhoto.value,
                          url: controller.savedPhotoUrl,
                        ),
                        if (progress != null)
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 3,
                              color: AppColors.primaryContainer,
                              backgroundColor: AppColors.onPrimary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => _choose(context),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: AppTheme.shadowMd,
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 16,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile Photo',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Optional photo to identify easily in family view',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _choose(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Choose picture',
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

class _Fields extends StatelessWidget {
  const _Fields({required this.controller});

  final ProfileSetupViewModel controller;

  static String _formatDate(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.dateOfBirth.value ?? DateTime(now.year - 60),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    controller.selectDateOfBirth(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileFieldCard(
          label: 'Full Name',
          icon: Icons.badge_outlined,
          child: TextField(
            controller: controller.nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: ProfileFieldCard.inputStyle,
            decoration: ProfileFieldCard.inputDecoration('e.g. Eleanor Vance'),
          ),
        ),
        Obx(
          () => controller.profileFor.value == AccountFor.caregiver
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ProfileFieldCard(
                    label: 'Relationship to Caregiver',
                    icon: Icons.diversity_1,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: controller.relationship.value,
                        isExpanded: true,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          size: 20,
                          color: AppColors.outline,
                        ),
                        style: ProfileFieldCard.inputStyle,
                        borderRadius: BorderRadius.circular(16),
                        items: [
                          for (final option
                              in ProfileSetupViewModel.relationships)
                            DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                        ],
                        onChanged: controller.selectRelationship,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        ProfileFieldCard(
          label: 'Date of Birth',
          trailingLabel: 'Optional',
          icon: Icons.calendar_today_outlined,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickDate(context),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Obx(() {
                final date = controller.dateOfBirth.value;
                return Text(
                  date == null ? 'mm/dd/yyyy' : _formatDate(date),
                  style: date == null
                      ? AppTextStyles.bodyLg.copyWith(
                          color: AppColors.onSurfaceVariant,
                        )
                      : ProfileFieldCard.inputStyle,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _EmergencyContact(controller: controller),
      ],
    );
  }
}

class _EmergencyContact extends StatelessWidget {
  const _EmergencyContact({required this.controller});

  final ProfileSetupViewModel controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(48),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.contact_emergency_outlined,
                size: 20,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Emergency Contact',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                'Optional',
                style: AppTextStyles.labelSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Used quickly if reminders are repeatedly unanswered or critical doses missed.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _InsetField(
            label: 'Contact Name',
            controller: controller.contactNameController,
            hint: 'Name and relation',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _InsetField(
            label: 'Phone Number',
            controller: controller.contactPhoneController,
            hint: '(555) 000-0000',
            icon: Icons.call_outlined,
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }
}

class _InsetField extends StatelessWidget {
  const _InsetField({
    required this.label,
    required this.controller,
    required this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: AppTextStyles.bodyMd.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 32,
            child: icon == null
                ? Align(alignment: Alignment.centerLeft, child: field)
                : Row(
                    children: [
                      Icon(icon, size: 18, color: AppColors.outline),
                      const SizedBox(width: 8),
                      Expanded(child: field),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPromise extends StatelessWidget {
  const _PrivacyPromise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(48),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified_user,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Privacy Promise',
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.lock, size: 16, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your profile is saved privately to your DoseMate account. DoseMate never sells '
                  'health data, displays intrusive ads, or makes automated medical changes.',
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

class _NextStepBanner extends StatelessWidget {
  const _NextStepBanner();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.bodySm.copyWith(
      color: AppColors.onSecondaryFixedVariant,
      height: 1.375,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondaryFixed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(48),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              size: 18,
              color: AppColors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(
                    text: 'Next step:',
                    style: style.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text:
                        ' We will configure gentle, non-startling alerts that bypass '
                        'silent battery limits so no critical doses slip by.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.secondaryFixed.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 20,
              color: AppColors.onSecondaryFixedVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSecondaryFixedVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Try again',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
