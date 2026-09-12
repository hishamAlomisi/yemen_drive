import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../account_routes.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/complaint_controller.dart';
import '../controllers/referral_controller.dart';

class ComplaintPage extends GetView<ComplaintController> {
  const ComplaintPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تقديم شكوى',
        bottomAction: Obx(
          () => AppButton(
            label: 'إرسال الشكوى',
            isLoading: controller.isSubmitting.value,
            onPressed: _submit,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AccountSectionTitle(
              title: 'كيف يمكننا مساعدتك؟',
              subtitle:
                  'أرسل تفاصيل واضحة وسيتواصل معك فريق الدعم في أقرب وقت.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Obx(
              () => DropdownButtonFormField<String>(
                key: ValueKey<String>(controller.category.value),
                initialValue: controller.category.value,
                decoration: const InputDecoration(
                  labelText: 'نوع الشكوى',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const <String>[
                  'السائق',
                  'المركبة',
                  'الدفع',
                  'التطبيق',
                  'أخرى',
                ]
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) controller.category.value = value;
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.messageController,
              label: 'تفاصيل الشكوى',
              hint: 'اكتب ما حدث، واذكر رقم الرحلة إن أمكن...',
              minLines: 6,
              maxLines: 9,
              textInputAction: TextInputAction.newline,
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
            const SizedBox(height: AppSpacing.md),
            AccountInfoBanner(
              text:
                  'تُعامل جميع الشكاوى بسرية، ويمكن إضافة رفع صور أو مرفقات عند ربط خدمة الملفات.',
              icon: Icons.privacy_tip_outlined,
            ),
          ],
        ),
      );

  Future<void> _submit() async {
    if (await controller.submit()) {
      await Get.offNamed<void>(AccountRoutes.complaintSuccess);
    } else {
      Get.snackbar('تفاصيل غير كافية', 'اكتب وصفًا لا يقل عن عشرة أحرف.');
    }
  }
}

class ComplaintSuccessPage extends StatelessWidget {
  const ComplaintSuccessPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تم الإرسال',
        scrollable: false,
        child: Center(
          child: AccountSuccessPanel(
            title: 'أُرسلت الشكوى بنجاح',
            message:
                'استلم فريق الدعم طلبك، وستصلك التحديثات عبر الإشعارات والبريد الإلكتروني.',
            actionLabel: 'العودة إلى الرئيسية',
            onAction: () => Get.offAllNamed<void>('/home'),
          ),
        ),
      );
}

class ReferralPage extends GetView<ReferralController> {
  const ReferralPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'رمز الإحالة',
        child: Column(
          children: <Widget>[
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: .15),
              ),
              child: Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.primaryDark,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'اربح رصيدًا مع أصدقائك',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'أدخل رمز إحالة صديقك، أو شارك رمزك الخاص بعد ربط بيانات الحساب.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: controller.codeController,
              label: 'رمز الإحالة',
              hint: 'مثال: RIDE2026',
              textInputAction: TextInputAction.done,
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => AppButton(
                label: 'تطبيق الرمز',
                isLoading: controller.isSubmitting.value,
                onPressed: () async {
                  if (await controller.submit()) {
                    Get.snackbar(
                      'تم قبول الرمز',
                      'سيُضاف رصيد المكافأة بعد تحقق الشروط.',
                    );
                  } else {
                    Get.snackbar(
                      'رمز غير مكتمل',
                      'أدخل رمزًا من أربعة أحرف على الأقل.',
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'مشاركة رمزي',
              variant: AppButtonVariant.outline,
              leading: Icon(Icons.share_outlined),
              onPressed: () => Get.snackbar(
                'مشاركة الرمز',
                'يمكن ربط الزر بحزمة المشاركة عند إضافة الرمز من API.',
              ),
            ),
          ],
        ),
      );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'عن يمن درايف',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 98,
                height: 98,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.local_taxi_rounded,
                  color: Colors.black,
                  size: 54,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'تنقّل أسهل، وأمان أكبر',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'يمن درايف منصة لحجز سيارات الأجرة صُممت لتجعل التنقل اليومي أكثر سهولة ووضوحًا. نربط الركاب بسائقين موثوقين، ونوفر خيارات دفع متعددة وتتبعًا مباشرًا للرحلة.',
            ),
            const SizedBox(height: AppSpacing.lg),
            const _AboutValue(
              icon: Icons.verified_user_outlined,
              title: 'السلامة أولًا',
              description:
                  'تجارب واضحة، بيانات رحلة محفوظة، وقنوات دعم جاهزة للتعامل مع أي ملاحظة.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _AboutValue(
              icon: Icons.speed_rounded,
              title: 'حجز سريع',
              description:
                  'خطوات مختصرة من تحديد موقعك وحتى وصول السائق وتأكيد الدفع.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _AboutValue(
              icon: Icons.language_rounded,
              title: 'تجربة عربية كاملة',
              description:
                  'واجهة RTL متجاوبة تدعم الوضعين الفاتح والداكن ومختلف أحجام الشاشات.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Text(
                'الإصدار 1.0.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
}

class _AboutValue extends StatelessWidget {
  const _AboutValue({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: .15),
              foregroundColor: AppColors.primaryDark,
              child: Icon(icon),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
