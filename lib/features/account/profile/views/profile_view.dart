import 'dart:math' as math;

import 'package:yemen_drive/features/auth/routes/auth_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/storage/secure_storage_service.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../../../../shared/widgets/map_backdrop.dart';
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
                    color: AppColors.primaryDark,
                  ),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
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
            Obx(
              () => DropdownButtonFormField<String>(
                key: ValueKey<String>(controller.gender.value),
                initialValue: controller.gender.value,
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
              ),
            ),
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
    final drawerWidth = math.min(360.0, MediaQuery.sizeOf(context).width * .88);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: MapBackdrop(
          showMarker: false,
          showRoute: true,
          child: SafeArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Material(
                elevation: 20,
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadiusDirectional.only(
                  topEnd: Radius.circular(24),
                  bottomEnd: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: drawerWidth,
                  height: double.infinity,
                  child: Column(
                    children: <Widget>[
                      _MenuHeader(onClose: () => Get.back<void>()),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                          children: <Widget>[
                            _MenuTile(
                              label: 'الرئيسية',
                              icon: Icons.home_rounded,
                              onTap: () => Get.offAllNamed<void>('/home'),
                            ),
                            _MenuTile(
                              label: 'الملف الشخصي',
                              icon: Icons.person_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.profile),
                            ),
                            _MenuTile(
                              label: 'الأماكن المفضلة',
                              icon: Icons.favorite_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.favourites),
                            ),
                            _MenuTile(
                              label: 'المحفظة',
                              icon: Icons.account_balance_wallet_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.wallet),
                            ),
                            _MenuTile(
                              label: 'سجل الرحلات',
                              icon: Icons.history_rounded,
                              onTap: () => Get.offNamed<void>(
                                AccountRoutes.historyUpcoming,
                              ),
                            ),
                            _MenuTile(
                              label: 'العروض',
                              icon: Icons.local_offer_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.offers),
                            ),
                            const Divider(height: 28),
                            _MenuTile(
                              label: 'تقديم شكوى',
                              icon: Icons.report_problem_outlined,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.complaint),
                            ),
                            _MenuTile(
                              label: 'الإعدادات',
                              icon: Icons.settings_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.settings),
                            ),
                            _MenuTile(
                              label: 'عن يمن درايف',
                              icon: Icons.info_outline_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.about),
                            ),
                            _MenuTile(
                              label: 'المساعدة والدعم',
                              icon: Icons.support_agent_rounded,
                              onTap: () =>
                                  Get.offNamed<void>(AccountRoutes.help),
                            ),
                            const Divider(height: 28),
                            _MenuTile(
                              label: 'تسجيل الخروج',
                              icon: Icons.logout_rounded,
                              color: AppColors.error,
                              onTap: () {
                                if (Get.isRegistered<SecureStorageService>()) {
                                  final SecureStorageService
                                      secureStorageService = Get.find();
                                  secureStorageService.clear();
                                  SecureStorageService.delete(
                                    key: "rememberMe",
                                  );
                                }
                                Get.offAllNamed<void>(AuthRoutes.welcome);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        decoration:
            BoxDecoration(color: AppColors.primary.withValues(alpha: .12)),
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'إغلاق',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded),
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              child: Icon(Icons.person_rounded, size: 42),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('هشام العميسي', style: Theme.of(context).textTheme.titleLarge),
            Text(
              '+967 775 288 883',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        trailing: Icon(Icons.arrow_back_ios_new_rounded, size: 14),
      );
}
