import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/config/app_environment.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_skeleton.dart';
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
              () => AppSkeleton(
                enabled:
                    controller.isLoading.value && !controller.hasLoaded.value,
                child: AccountResponsiveGrid(
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
              if (controller.isLoading.value && !controller.hasLoaded.value) {
                return const AppSkeletonList(count: 2);
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
        bottomAction: AppButton(
          label: 'متابعة',
          onPressed: _continue,
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
            const SizedBox(height: AppSpacing.lg),
            const AccountSectionTitle(
              title: 'طريقة الدفع',
              subtitle: 'اختر وسيلة الشحن المفعلة من الخادم',
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(() {
              final methods = AppEnvironment.paymentMethods
                  .where((method) => method.availableForWalletTopUp)
                  .toList(growable: false);
              if (methods.isEmpty) {
                return const AccountInfoBanner(
                  text: 'لا توجد وسائل شحن مفعلة حالياً.',
                  icon: Icons.info_outline_rounded,
                );
              }
              return Column(
                children: methods
                    .map(
                      (method) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AccountChoiceTile(
                          title: method.label,
                          subtitle: method.subtitle,
                          icon: method.icon,
                          imageUrl: method.imageUrl,
                          selected: controller.selectedPaymentMethodId.value ==
                              method.id,
                          onTap: () =>
                              controller.selectPaymentMethod(method.id),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            }),
            const SizedBox(height: AppSpacing.sm),
            const AccountInfoBanner(
              text:
                  'يُضاف الرصيد بعد تأكيد عملية الدفع من مزود الدفع أو بعد اعتماد طلب شحن من الخادم.',
              icon: Icons.lock_outline_rounded,
            ),
          ],
        ),
      );

  Future<void> _continue() async {
    if ((controller.parsedAmount ?? 0) <= 0) {
      Get.snackbar('تحقق من المبلغ', 'أدخل مبلغاً أكبر من صفر.');
      return;
    }
    if (controller.selectedPaymentMethod == null) {
      Get.snackbar('طريقة الدفع', 'اختر وسيلة شحن مفعلة أولاً.');
      return;
    }
    if (controller.requiresBankAccount) {
      await Get.toNamed<void>(AccountRoutes.bank);
      return;
    }
    Get.snackbar(
      'شحن المحفظة',
      'لم يُربط مزود الدفع لهذه الوسيلة بعد، لذلك لن يُضاف أي رصيد قبل التأكيد الفعلي.',
    );
  }
}

class BankAccountPage extends GetView<WalletController> {
  const BankAccountPage({super.key});

  @override
  Widget build(BuildContext context) => const AccountPageTemplate(
        title: 'الشحن البنكي',
        child: Center(
          child: AccountInfoBanner(
            text:
                'يتطلب الشحن البنكي طلب شحن مؤكد من الخادم. لن تُحفظ بيانات حساب أو يُضاف رصيد قبل تنفيذ هذه العملية.',
            icon: Icons.account_balance_outlined,
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
