import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/config/app_environment.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_skeleton.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../account_routes.dart';
import '../../models/account_models.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/wallet_controller.dart';
import '../../../ride/widgets/wallet_ride_payment_panel.dart';
import '../../../ride/widgets/external_payment_methods.dart';
import '../../../ride/controllers/ride_controller.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  WalletController get controller => Get.find<WalletController>();

  @override
  void initState() {
    super.initState();
    final walletController = controller;
    final args = Get.arguments;
    if (!widget.embedded && args is Map && args['topUpId'] != null) {
      final id = '${args['topUpId']}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) walletController.openInvoice(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'المحفظة',
        showBack: false,
        bottomNavIndex: widget.embedded ? null : 2,
        actions: <Widget>[
          IconButton(
            tooltip: 'تحويل لحساب',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => Get.toNamed<void>(AccountRoutes.walletTransfer),
          ),
          IconButton(
            tooltip: 'شحن المحفظة',
            onPressed: controller.newTopUp,
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
            Obx(() => controller.ledgerDebt.value <= 0
                ? const SizedBox.shrink()
                : AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        Text(
                            'مديونية المحفظة: ${controller.ledgerDebt.value.toStringAsFixed(2)} ر.ي',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const Text(
                            'تسدد الإيداعات القادمة المديونية أولاً، ثم يضاف المتبقي إلى الرصيد المتاح.'),
                      ]))),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed<void>(AccountRoutes.walletTransfer),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('تحويل لحساب'),
            ),
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => controller.outstandingRideDebt.value <= 0
                  ? const SizedBox.shrink()
                  : AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'مديونية الرحلات غير المسددة: ${controller.outstandingRideDebt.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'مبلغ مستحق عليك؛ لا يمثل خصماً جديداً أو دفعاً تم بالفعل.',
                          ),
                          for (final debt in controller.rideDebts)
                            TextButton.icon(
                              icon: const Icon(Icons.receipt_long),
                              label: Text(
                                'رحلة #${debt['rideId']} — ${debt['amount']} ر.ي: التفاصيل والسداد',
                              ),
                              onPressed: () async {
                                await Get.find<RideController>()
                                    .openFinancialFollowUp('${debt['rideId']}');
                                await controller.loadTransactions();
                              },
                            ),
                        ],
                      ),
                    ),
            ),
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
      child: InkWell(
        onTap: transaction.transferReference != null
            ? () => Get.toNamed<void>(AccountRoutes.walletTransfer,
                arguments: {'reference': transaction.transferReference})
            : transaction.topUpId == null
                ? null
                : () => Get.find<WalletController>()
                    .openInvoice(transaction.topUpId!),
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
            label: 'متابعة',
            isLoading: controller.methodsLoading.value ||
                controller.topUp?.busy.value == true,
            onPressed: controller.methodsLoading.value ||
                    controller.topUp?.busy.value == true
                ? null
                : _continue,
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
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫]')),
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
              controller.catalogRevision.value;
              final methods = AppEnvironment.topUpPaymentMethods;
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
                        child: ListTile(
                          enabled: method.canTopUp &&
                              controller.methodsError.value.isEmpty &&
                              !controller.methodsLoading.value,
                          leading: Opacity(
                            opacity: method.canTopUp &&
                                    controller.methodsError.value.isEmpty
                                ? 1
                                : .35,
                            child: PaymentCatalogIcon(method: method, size: 40),
                          ),
                          title: Text(method.label),
                          subtitle: Text(
                            method.canTopUp &&
                                    controller.methodsError.value.isEmpty
                                ? method.subtitle
                                : 'الخدمة غير متاحة',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Icon(
                            controller.selectedPaymentMethodId.value ==
                                    method.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          onTap: method.canTopUp
                              ? () => controller.selectPaymentMethod(method.id)
                              : null,
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
    await controller.startTopUp();
  }
}

class WalletTopUpPaymentPage extends GetView<WalletController> {
  const WalletTopUpPaymentPage({super.key});
  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'شحن المحفظة',
        child: controller.topUp == null
            ? const Text('سجل الدخول لمتابعة الشحن.')
            : WalletRidePaymentPanel(
                controller: controller.topUp!,
                onRefresh: () => controller.topUp!.refresh('topup'),
                onRetry: controller.changeTopUpMethod,
                onChangeMethod: controller.changeTopUpMethod,
                onDone: () {
                  controller.loadTransactions();
                  Get.offNamed<void>(AccountRoutes.wallet);
                },
              ),
      );
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
