import 'dart:math' as math;

import 'package:yemen_drive/features/auth/routes/auth_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/storage/secure_storage_service.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../../ride/ride_routes.dart';
import '../../account_routes.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/profile_controller.dart';

class ProfilePage extends GetView<ProfileController> {
  const ProfilePage({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تعديل الملف الشخصي',
        showBack: false,
        bottomNavIndex: embedded ? null : 4,
        actions: <Widget>[
          IconButton(
            tooltip: 'القائمة',
            onPressed: () => Get.toNamed<void>(AccountRoutes.menu),
            icon: Icon(Icons.menu_rounded),
          ),
        ],
        bottomAction: Obx(
          () => AppButton(
            label: 'حفظ التعديلات',
            isLoading: controller.isSaving.value,
            onPressed: () async {
              await controller.save();
              Get.snackbar('تم الحفظ', 'حُدّثت بيانات الملف الشخصي.');
            },
          ),
        ),
        child: Column(
          children: <Widget>[
            Stack(
              alignment: AlignmentDirectional.bottomStart,
              children: <Widget>[
                Container(
                  width: 106,
                  height: 106,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: .18),
                    border: Border.all(color: AppColors.primary, width: 3),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 58,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'تغيير الصورة',
                    onPressed: () => Get.snackbar(
                      'الصورة الشخصية',
                      'يمكن ربط هذا الإجراء برفع الصور إلى الخادم.',
                    ),
                    icon: Icon(Icons.camera_alt_rounded, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(() => Text(
                controller.displayName.value.isEmpty
                    ? 'الملف الشخصي'
                    : controller.displayName.value,
                style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: controller.nameController,
              label: 'الاسم الكامل',
              textInputAction: TextInputAction.next,
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.phoneController,
              label: 'رقم الجوال',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            const SizedBox(height: AppSpacing.md),
            Obx(() {
              const genderValues = <String>{
                'أنثى',
                'ذكر',
                'أفضل عدم التحديد',
              };
              final selectedGender =
                  genderValues.contains(controller.gender.value)
                      ? controller.gender.value
                      : null;
              return DropdownButtonFormField<String>(
                key: ValueKey<String?>(selectedGender),
                initialValue: selectedGender,
                decoration: const InputDecoration(
                  labelText: 'الجنس',
                  prefixIcon: Icon(Icons.wc_rounded),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'أنثى', child: Text('أنثى')),
                  DropdownMenuItem(value: 'ذكر', child: Text('ذكر')),
                  DropdownMenuItem(
                    value: 'أفضل عدم التحديد',
                    child: Text('أفضل عدم التحديد'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) controller.gender.value = value;
                },
              );
            }),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.addressController,
              label: 'العنوان',
              textInputAction: TextInputAction.done,
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ],
        ),
      );
}

class SideMenuPage extends StatelessWidget {
  const SideMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = math.min(360.0, MediaQuery.sizeOf(context).width * .84);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
              child: GestureDetector(
            onTap: () => Get.back<void>(),
            child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
          )),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: Material(
                color: colors.surface,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _MenuHeader(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: <Widget>[
                            _MenuTile(
                                label: 'رحلات المدينة',
                                icon: Icons.directions_car_outlined,
                                selected: true,
                                onTap: () => Get.offAllNamed<void>(
                                    RideRoutes.homeTransport)),
                            _MenuTile(
                                label: 'الخدمات',
                                icon: Icons.grid_view_outlined,
                                onTap: () =>
                                    Get.offNamed<void>(RideRoutes.services)),
                            _MenuTile(
                                label: 'سجل الطلبات',
                                icon: Icons.history,
                                onTap: () => Get.offNamed<void>(
                                    AccountRoutes.historyUpcoming)),
                            _MenuTile(
                                label: 'المحفظة',
                                icon: Icons.account_balance_wallet_outlined,
                                onTap: () =>
                                    Get.offNamed<void>(AccountRoutes.wallet)),
                            _MenuTile(
                                label: 'الأماكن المفضلة',
                                icon: Icons.favorite_border,
                                onTap: () => Get.offNamed<void>(
                                    AccountRoutes.favourites)),
                            _MenuTile(
                                label: 'العروض',
                                icon: Icons.local_offer_outlined,
                                onTap: () =>
                                    Get.offNamed<void>(AccountRoutes.offers)),
                            _MenuTile(
                                label: 'الإشعارات',
                                icon: Icons.notifications_none,
                                onTap: () => Get.offNamed<void>(
                                    RideRoutes.notifications)),
                            _MenuTile(
                                label: 'مركز الأمان',
                                icon: Icons.shield_outlined,
                                onTap: () =>
                                    Get.offNamed<void>(RideRoutes.safety)),
                            _MenuTile(
                                label: 'تقديم شكوى',
                                icon: Icons.report_outlined,
                                onTap: () => Get.offNamed<void>(
                                    AccountRoutes.complaint)),
                            _MenuTile(
                                label: 'الإعدادات',
                                icon: Icons.settings_outlined,
                                onTap: () =>
                                    Get.offNamed<void>(AccountRoutes.settings)),
                            _MenuTile(
                                label: 'المساعدة',
                                icon: Icons.help_outline,
                                onTap: () =>
                                    Get.offNamed<void>(AccountRoutes.help)),
                            _MenuTile(
                                label: 'عن يمن درايف',
                                icon: Icons.info_outline,
                                onTap: () =>
                                    Get.offNamed<void>(AccountRoutes.about)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: AppButton(
                          label: 'تسجيل الخروج',
                          onPressed: () {
                            if (Get.isRegistered<SecureStorageService>()) {
                              Get.find<SecureStorageService>().clear();
                              SecureStorageService.delete(key: 'rememberMe');
                            }
                            Get.offAllNamed<void>(AuthRoutes.welcome);
                          },
                        ),
                      ),
                    ],
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

class _MenuHeader extends GetView<ProfileController> {
  const _MenuHeader();

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Get.offNamed<void>(AccountRoutes.profile),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 16, 20),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 25,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                child: Icon(Icons.person_outline,
                    size: 30, color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Obx(() => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                              controller.displayName.value.isEmpty
                                  ? 'حسابي'
                                  : controller.displayName.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 3),
                          Text('عرض الملف الشخصي',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ))),
              const Icon(Icons.chevron_right, size: 22),
            ],
          ),
        ),
      );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.selected = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.surfaceContainer,
        selectedColor: Theme.of(context).colorScheme.onSurface,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon,
            size: 23, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      );
}
