import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/services/theme_service.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../account_routes.dart';
import '../../widgets/account_widgets.dart';
import '../../change_password/controllers/change_password_controller.dart';
import '../../contact/controllers/contact_controller.dart';
import '../../delete_account/controllers/delete_account_controller.dart';
import '../../language/controllers/language_controller.dart';
import '../controllers/settings_controller.dart';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'الإعدادات',
        child: Column(
          children: <Widget>[
            AccountListTile(
              title: 'تغيير كلمة المرور',
              subtitle: 'حدّث كلمة المرور الخاصة بحسابك',
              icon: Icons.lock_outline_rounded,
              onTap: () => Get.toNamed<void>(AccountRoutes.changePassword),
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => AccountListTile(
                title: 'auto_start_transport'.tr,
                subtitle: 'auto_start_transport_hint'.tr,
                icon: Icons.directions_car_filled_outlined,
                trailing: Switch.adaptive(
                  value: controller.autoStartTransport.value,
                  onChanged: controller.setAutoStartTransport,
                ),
                onTap: () => controller.setAutoStartTransport(
                  !controller.autoStartTransport.value,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountListTile(
              title: 'اللغة',
              subtitle: controller.selectedLanguage.value == ("ar".obs.value)
                  ? 'العربية'
                  : 'English',
              icon: Icons.language_rounded,
              onTap: () => Get.toNamed<void>(AccountRoutes.language),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountListTile(
              title: 'مظهر التطبيق',
              subtitle: Get.isDarkMode ? 'الوضع الداكن' : 'الوضع الفاتح',
              icon: Get.isDarkMode
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              onTap: () => _showThemePicker(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () {
                final palette = Get.find<ThemeService>().palette.value;
                return AccountListTile(
                  title: 'هوية الألوان',
                  subtitle: palette.label,
                  icon: Icons.palette_outlined,
                  onTap: () => _showPalettePicker(context),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountListTile(
              title: 'سياسة الخصوصية',
              subtitle: 'كيف نجمع بياناتك ونستخدمها ونحميها',
              icon: Icons.privacy_tip_outlined,
              onTap: () => Get.toNamed<void>(AccountRoutes.privacy),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountListTile(
              title: 'تواصل معنا',
              subtitle: 'أرسل رسالة إلى فريق الدعم',
              icon: Icons.contact_support_outlined,
              onTap: () => Get.toNamed<void>(AccountRoutes.contact),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountListTile(
              title: 'حذف الحساب',
              subtitle: 'حذف بيانات الحساب نهائيًا',
              icon: Icons.delete_forever_outlined,
              iconColor: AppColors.error,
              onTap: () => Get.toNamed<void>(AccountRoutes.deleteAccount),
            ),
          ],
        ),
      );

  Future<void> _showThemePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'مظهر التطبيق',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ListTile(
                  title: const Text('حسب إعداد الجهاز'),
                  leading: Icon(Icons.settings_suggest_outlined),
                  trailing: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                  ),
                  onTap: () => _selectTheme(context, ThemeMode.system),
                ),
                ListTile(
                  title: const Text('الوضع الفاتح'),
                  leading: Icon(Icons.light_mode_outlined),
                  trailing: !Get.isDarkMode
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primaryDark,
                        )
                      : null,
                  onTap: () => _selectTheme(context, ThemeMode.light),
                ),
                ListTile(
                  title: const Text('الوضع الداكن'),
                  leading: Icon(Icons.dark_mode_outlined),
                  trailing: Get.isDarkMode
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primaryDark,
                        )
                      : null,
                  onTap: () => _selectTheme(context, ThemeMode.dark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectTheme(BuildContext context, ThemeMode? value) async {
    if (value == null) return;
    Navigator.pop(context);
    await controller.setTheme(value);
  }

  Future<void> _showPalettePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(
                title: Text('هوية الألوان'),
                subtitle: Text('اختر ألوان واجهة التطبيق'),
                leading: Icon(Icons.palette_outlined),
              ),
              for (final palette in AppPalette.values)
                Obx(
                  () {
                    final selected =
                        Get.find<ThemeService>().palette.value == palette;
                    return ListTile(
                      title: Text(palette.label),
                      leading: CircleAvatar(
                        backgroundColor: palette.colors.primary,
                        radius: 12,
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        await controller.setPalette(palette);
                      },
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class ChangePasswordPage extends GetView<ChangePasswordController> {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تغيير كلمة المرور',
        bottomAction: Obx(
          () => AppButton(
            label: 'حفظ كلمة المرور',
            isLoading: controller.isSubmitting.value,
            onPressed: () async {
              if (await controller.savePassword()) {
                Get.back<void>();
                Get.snackbar('تم التحديث', 'تغيّرت كلمة المرور بنجاح.');
              } else {
                Get.snackbar(
                  'تحقق من البيانات',
                  'يجب أن تتطابق كلمتا المرور وألا تقل الجديدة عن 8 أحرف.',
                );
              }
            },
          ),
        ),
        child: Column(
          children: <Widget>[
            _PasswordField(
              controller: controller.currentPasswordController,
              label: 'كلمة المرور الحالية',
              hidden: controller.hideCurrentPassword,
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              controller: controller.newPasswordController,
              label: 'كلمة المرور الجديدة',
              hidden: controller.hideNewPassword,
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              controller: controller.confirmPasswordController,
              label: 'تأكيد كلمة المرور الجديدة',
              hidden: controller.hideConfirmPassword,
              action: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.md),
            AccountInfoBanner(
              text:
                  'استخدم ثمانية أحرف على الأقل، ويفضل الجمع بين الحروف والأرقام والرموز.',
              icon: Icons.security_rounded,
            ),
          ],
        ),
      );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hidden,
    this.action = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final RxBool hidden;
  final TextInputAction action;

  @override
  Widget build(BuildContext context) => Obx(
        () => AppTextField(
          controller: controller,
          label: label,
          obscureText: hidden.value,
          textInputAction: action,
          prefixIcon: Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: hidden.value ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
            onPressed: hidden.toggle,
            icon: Icon(
              hidden.value
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      );
}

class LanguagePage extends GetView<LanguageController> {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'لغة التطبيق',
        child: Obx(
          () => Column(
            children: <({String code, String label, String flag})>[
              (code: 'ar', label: 'العربية', flag: '🇸🇦'),
              (code: 'en', label: 'English', flag: '🇬🇧'),
            ]
                .map(
                  (language) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      onTap: () => controller.changeLanguage(language.code),
                      child: Row(
                        children: <Widget>[
                          Text(
                            language.flag,
                            style: TextStyle(fontSize: 28),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              language.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            controller.selectedLanguage.value == language.code
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: controller.selectedLanguage.value ==
                                    language.code
                                ? AppColors.primaryDark
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'سياسة الخصوصية',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AccountInfoBanner(
              text: 'آخر تحديث: 11 أغسطس 2026',
              icon: Icons.update_rounded,
            ),
            SizedBox(height: AppSpacing.lg),
            _LegalSection(
              title: '1. البيانات التي نجمعها',
              body:
                  'نجمع بيانات الحساب الأساسية، ومواقع الانطلاق والوصول، وسجل الرحلات، وبيانات الجهاز اللازمة لتشغيل الخدمة وحمايتها. لا نخزن بيانات البطاقة الكاملة داخل التطبيق.',
            ),
            _LegalSection(
              title: '2. كيفية استخدام البيانات',
              body:
                  'نستخدم البيانات لتنفيذ الحجوزات، وربطك بالسائق، واحتساب الأجرة، ومعالجة المدفوعات، وتحسين جودة الخدمة، والرد على طلبات الدعم.',
            ),
            _LegalSection(
              title: '3. مشاركة البيانات',
              body:
                  'نشارك الحد الأدنى المطلوب مع السائق ومزود الدفع ومقدمي الخدمات التقنيين. لا نبيع بياناتك الشخصية لأي طرف.',
            ),
            _LegalSection(
              title: '4. الحفظ والأمان',
              body:
                  'تُحمى البيانات أثناء النقل عبر اتصال HTTPS الآمن، وتُحدد مدة الاحتفاظ وفق المتطلبات النظامية واحتياجات التشغيل وتسوية النزاعات.',
            ),
            _LegalSection(
              title: '5. حقوقك',
              body:
                  'يمكنك طلب نسخة من بياناتك أو تصحيحها أو حذف حسابك، مع مراعاة البيانات التي يلزم الاحتفاظ بها نظاميًا.',
            ),
          ],
        ),
      );
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(body),
          ],
        ),
      );
}

class ContactPage extends GetView<ContactController> {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تواصل معنا',
        bottomAction: Obx(
          () => AppButton(
            label: 'إرسال الرسالة',
            isLoading: controller.isSubmitting.value,
            onPressed: () async {
              if (await controller.send()) {
                Get.back<void>();
                Get.snackbar('تم الإرسال', 'وصلت رسالتك إلى فريق الدعم.');
              } else {
                Get.snackbar(
                  'تحقق من الحقول',
                  'أدخل الاسم والبريد ورسالة واضحة.',
                );
              }
            },
          ),
        ),
        child: Column(
          children: <Widget>[
            AccountInfoBanner(
              text: 'ساعات الدعم: يوميًا من 8 صباحًا حتى 12 منتصف الليل.',
              icon: Icons.support_agent_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: controller.nameController,
              label: 'الاسم',
              textInputAction: TextInputAction.next,
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.emailController,
              label: 'البريد الإلكتروني',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icon(Icons.email_outlined),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.phoneController,
              label: 'رقم الجوال (اختياري)',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.messageController,
              label: 'الرسالة',
              minLines: 5,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              prefixIcon: Icon(Icons.message_outlined),
            ),
          ],
        ),
      );
}

class DeleteAccountPage extends GetView<DeleteAccountController> {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'حذف الحساب',
        child: Column(
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: .14),
              ),
              child: Icon(
                Icons.delete_forever_rounded,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'هل تريد حذف حسابك؟',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'سيؤدي الحذف إلى إلغاء الوصول إلى حسابك ومسح الأماكن المفضلة والإعدادات الشخصية. قد نحتفظ ببعض سجلات المعاملات للمدة المطلوبة نظاميًا.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AccountInfoBanner(
              text:
                  'هذا الإجراء نهائي ولا يمكن التراجع عنه بعد تأكيده من الخادم.',
              icon: Icons.warning_amber_rounded,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Obx(
              () => AppButton(
                label: 'حذف الحساب نهائيًا',
                variant: AppButtonVariant.danger,
                isLoading: controller.isSubmitting.value,
                onPressed: () => _confirmDelete(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'إلغاء',
              variant: AppButtonVariant.outline,
              onPressed: () => Get.back<void>(),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تأكيد حذف الحساب'),
              content: const Text(
                'اكتب طلب الحذف فقط بعد التأكد من تنزيل أي بيانات تحتاجها.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('تراجع'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('تأكيد الحذف'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (await controller.deleteAccount()) {
      await Get.offAllNamed<void>('/login');
    }
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'المساعدة والدعم',
        child: Column(
          children: <Widget>[
            AccountInfoBanner(
              text:
                  'إن كانت لديك مشكلة عاجلة أثناء رحلة نشطة، استخدم زر الطوارئ داخل شاشة الرحلة.',
              icon: Icons.support_agent_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _FaqTile(
              question: 'كيف أحجز رحلة؟',
              answer:
                  'حدد موقع الانطلاق والوجهة، اختر فئة المركبة وطريقة الدفع، ثم راجع التفاصيل واضغط تأكيد الحجز.',
            ),
            const _FaqTile(
              question: 'كيف ألغي رحلة؟',
              answer:
                  'افتح الرحلة النشطة واختر إلغاء الرحلة، ثم حدد السبب. قد تُطبق رسوم وفق الوقت وحالة وصول السائق.',
            ),
            const _FaqTile(
              question: 'متى يُعاد المبلغ إلى المحفظة؟',
              answer:
                  'تظهر المبالغ المستردة إلى المحفظة فور اعتمادها. أما البطاقات فقد تستغرق عدة أيام عمل حسب البنك.',
            ),
            const _FaqTile(
              question: 'نسيت غرضًا في السيارة',
              answer:
                  'افتح الرحلة المكتملة من السجل، ثم تواصل مع الدعم واذكر وصف الغرض ورقم الرحلة.',
            ),
            const _FaqTile(
              question: 'كيف أحافظ على أمان حسابي؟',
              answer:
                  'لا تشارك رمز التحقق أو كلمة المرور، واستخدم كلمة قوية، وسجل الخروج من الأجهزة غير المعروفة.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'تواصل مع الدعم',
              leading: Icon(Icons.chat_bubble_outline_rounded),
              onPressed: () => Get.toNamed<void>(AccountRoutes.contact),
            ),
          ],
        ),
      );
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
              Icons.help_outline_rounded,
              color: AppColors.primaryDark,
            ),
            title: Text(
              question,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(answer),
              ),
            ],
          ),
        ),
      );
}
