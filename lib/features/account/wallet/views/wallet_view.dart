import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/config/app_environment.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_states.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../account_routes.dart';
import '../../models/account_models.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/wallet_controller.dart';

class WalletPage extends GetView<WalletController> {
  const WalletPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'المحفظة',
        showBack: false,
        bottomNavIndex: embedded ? null : 2,
        actions: <Widget>[
          IconButton(
            tooltip: 'شحن المحفظة',
            onPressed: () => Get.toNamed<void>(AccountRoutes.addAmount),
            icon: Icon(Icons.add_card_rounded),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Obx(
              () => AccountResponsiveGrid(
                children: <Widget>[
                  AccountMetricCard(
                    label: 'الرصيد المتاح',
                    value:
                        '${controller.walletBalance.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                    icon: Icons.account_balance_wallet_rounded,
                    highlighted: true,
                  ),
                  AccountMetricCard(
                    label: 'إجمالي المصروفات',
                    value:
                        '${controller.totalSpent.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
                    icon: Icons.receipt_long_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AccountSectionTitle(
              title: 'آخر العمليات',
              subtitle: 'كل عمليات الشحن والدفع من المحفظة',
              trailing: TextButton(
                onPressed: controller.loadTransactions,
                child: const Text('تحديث'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(() {
              if (controller.isLoading.value) {
                return const SizedBox(height: 240, child: AppLoading());
              }
              return Column(
                children: controller.transactions
                    .map(
                      (transaction) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TransactionTile(transaction: transaction),
                      ),
                    )
                    .toList(growable: false),
              );
            }),
          ],
        ),
      );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final color = transaction.isCredit ? AppColors.success : AppColors.error;
    return AppCard(
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .14),
            foregroundColor: color,
            child: Icon(
              transaction.isCredit
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.title,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _arabicDate(transaction.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${transaction.isCredit ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class AddAmountPage extends GetView<WalletController> {
  const AddAmountPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'إضافة رصيد',
        bottomAction: Obx(
          () => AppButton(
            label: controller.selectedPaymentMethodId.value == 'bank'
                ? 'متابعة إلى بيانات البنك'
                : 'إضافة الرصيد',
            isLoading: controller.isSubmitting.value,
            onPressed: () => _continue(),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AccountSectionTitle(
              title: 'المبلغ المطلوب',
              subtitle: 'أدخل قيمة الشحن بالريال اليمني',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: controller.amountController,
              hint: '0.00',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              prefixIcon: Icon(Icons.payments_outlined),
              suffixIcon: Padding(
                padding: EdgeInsets.all(16),
                child: Text(AppEnvironment.defaultCurrency),
              ),
              onChanged: controller.setAmount,
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountResponsiveGrid(
              mobileColumns: 3,
              wideColumns: 5,
              children: <double>[500, 1000, 2000, 3000, 5000]
                  .map(
                    (amount) => OutlinedButton(
                      onPressed: () => controller.selectQuickAmount(amount),
                      child: Text(
                        '${amount.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: AppSpacing.lg),
            const AccountSectionTitle(
              title: 'طريقة الدفع المفضلة',
              subtitle: 'اختر وسيلة آمنة لإتمام عملية الشحن',
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => Column(
                children: AppEnvironment.paymentMethods
                    .map(
                      (method) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AccountChoiceTile(
                          title: method.label,
                          subtitle: method.subtitle,
                          icon: method.icon,
                          selected: controller.selectedPaymentMethodId.value ==
                              method.id,
                          onTap: () =>
                              controller.selectPaymentMethod(method.id),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            AccountInfoBanner(
              text:
                  'بيانات الدفع لا تُحفظ داخل التطبيق، وستُرسل مشفّرة إلى مزوّد الدفع عند ربط الواجهة الخلفية.',
              icon: Icons.lock_outline_rounded,
            ),
          ],
        ),
      );

  Future<void> _continue() async {
    if ((controller.parsedAmount ?? 0) <= 0) {
      Get.snackbar('تحقق من المبلغ', 'أدخل مبلغًا أكبر من صفر.');
      return;
    }
    if (controller.selectedPaymentMethodId.value == 'bank') {
      await Get.toNamed<void>(AccountRoutes.bank);
      return;
    }
    if (await controller.addAmount()) {
      await Get.toNamed<void>(AccountRoutes.walletSuccess);
    }
  }
}

class BankAccountPage extends GetView<WalletController> {
  const BankAccountPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'الحساب البنكي',
        bottomAction: Obx(
          () => AppButton(
            label: 'تأكيد وإضافة الرصيد',
            isLoading: controller.isSubmitting.value,
            onPressed: _submit,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AccountInfoBanner(
              text:
                  'تأكد أن اسم صاحب الحساب البنكي مطابق لاسم المستخدم المسجل.',
              icon: Icons.account_balance_outlined,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'المبلغ',
              controller: controller.amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: controller.setAmount,
              prefixIcon: Icon(Icons.payments_outlined),
              suffixIcon: Padding(
                padding: EdgeInsets.all(16),
                child: Text(AppEnvironment.defaultCurrency),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: 'riyad',
              decoration: const InputDecoration(
                labelText: 'اسم البنك',
                prefixIcon: Icon(Icons.account_balance_rounded),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'riyad',
                  child: Text('بنك اليمن الدولي'),
                ),
                DropdownMenuItem(value: 'rajhi', child: Text('مصرف الراجحي')),
                DropdownMenuItem(value: 'snb', child: Text('بنك الكريمي')),
                DropdownMenuItem(value: 'other', child: Text('بنك آخر')),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller.bankAccountController,
              label: 'رقم الحساب أو الآيبان',
              hint: 'SA00 0000 0000 0000 0000 0000',
              textInputAction: TextInputAction.done,
              prefixIcon: Icon(Icons.numbers_rounded),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                LengthLimitingTextInputFormatter(29),
              ],
            ),
          ],
        ),
      );

  Future<void> _submit() async {
    if (await controller.addAmount(includeBankAccount: true)) {
      await Get.toNamed<void>(AccountRoutes.walletSuccess);
    } else {
      Get.snackbar(
        'تحقق من البيانات',
        'أدخل مبلغًا صحيحًا ورقم حساب أو آيبان مكتملًا.',
      );
    }
  }
}

class WalletSuccessPage extends GetView<WalletController> {
  const WalletSuccessPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تمت العملية',
        scrollable: false,
        child: Center(
          child: Obx(
            () => AccountSuccessPanel(
              title: 'تمت إضافة الرصيد بنجاح',
              value:
                  '${controller.lastAddedAmount.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
              message: 'أصبح المبلغ متاحًا الآن في محفظتك.',
              actionLabel: 'العودة إلى المحفظة',
              onAction: () => Get.offAllNamed<void>(AccountRoutes.wallet),
            ),
          ),
        ),
      );
}

String _arabicDate(DateTime date) {
  const months = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  return '${date.day} ${months[date.month - 1]}، ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
