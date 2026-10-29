import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../controllers/wallet_ride_payment_controller.dart';
import '../models/wallet_ride_payment.dart';

class WalletRidePaymentPanel extends StatefulWidget {
  const WalletRidePaymentPanel({
    required this.controller,
    required this.onRefresh,
    required this.onRetry,
    required this.onChangeMethod,
    required this.onDone,
    super.key,
  });

  final WalletRidePaymentController controller;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onChangeMethod;
  final VoidCallback onDone;

  @override
  State<WalletRidePaymentPanel> createState() => _WalletRidePaymentPanelState();
}

class _WalletRidePaymentPanelState extends State<WalletRidePaymentPanel> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  void _complete() {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    _code.clear();
    FocusScope.of(context).unfocus();
    widget.controller.complete(code);
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final flow = widget.controller;
        final payment = flow.payment.value;
        if (payment == null) return const SizedBox.shrink();
        final busy = flow.busy.value;
        final known = flow.stateKnown.value;
        final colors = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: CircleAvatar(
                radius: 32,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  payment.succeeded
                      ? Icons.check_circle_outline_rounded
                      : payment.awaitingCode
                          ? Icons.sms_outlined
                          : payment.awaitingConfirmation
                              ? Icons.account_balance_wallet_outlined
                              : Icons.receipt_long_outlined,
                  size: 34,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_title(payment),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_description(payment),
                key: const ValueKey('wallet-provider-message'),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(payment.providerName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (payment.customerIsProviderVerified &&
                      payment.customerName.isNotEmpty)
                    _detail(context, 'اسم العميل', payment.customerName)
                  else if (!payment.succeeded)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child:
                          Text('بيانات الحساب غير متاحة من مزود الدفع حالياً.'),
                    ),
                  _detail(context, 'رقم الهاتف', payment.mobile, ltr: true),
                  _detail(context, 'المستلم', payment.recipient),
                  const Divider(height: 24),
                  _detail(context, 'مبلغ الرحلة',
                      '${_money(payment.amount)} ${_currency(payment.currency)}'),
                  _detail(
                      context,
                      'العمولة',
                      payment.feesKnown
                          ? '${_money(payment.fees!)} ${_currency(payment.feeCurrency)}'
                          : 'غير محددة من المزود'),
                  _detail(context, 'العملة', _currency(payment.currency)),
                  if (payment.succeeded) ...[
                    const Divider(height: 24),
                    _detail(context, 'رقم الرحلة', payment.rideId, ltr: true),
                    _detail(context, 'رقم العملية', payment.id, ltr: true),
                    if (payment.providerReference?.isNotEmpty == true)
                      _detail(
                          context, 'مرجع المزود', payment.providerReference!,
                          ltr: true),
                    if (payment.paidAtUtc != null)
                      _detail(context, 'وقت الدفع', _date(payment.paidAtUtc!),
                          ltr: true),
                  ],
                ],
              ),
            ),
            if (flow.error.value.isNotEmpty &&
                flow.error.value.trim() != payment.message.trim()) ...[
              const SizedBox(height: 16),
              Text(flow.error.value,
                  style: TextStyle(color: colors.error),
                  textAlign: TextAlign.center),
            ],
            if (payment.awaitingCode && known) ...[
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('wallet-verification-code'),
                controller: _code,
                enabled: !busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: payment.nextAction == 'Voucher'
                    ? TextInputType.text
                    : TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                maxLength: 256,
                autofillHints: payment.nextAction == 'OneTimePassword'
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                decoration: InputDecoration(
                    labelText: _codeLabel(payment.nextAction),
                    counterText: '',
                    border: const OutlineInputBorder()),
                onSubmitted: busy ? null : (_) => _complete(),
              ),
            ],
            const SizedBox(height: 24),
            if (payment.succeeded)
              AppButton(
                  key: const ValueKey('wallet-receipt-done'),
                  label: 'متابعة',
                  onPressed: widget.onDone)
            else if (!known)
              AppButton(
                  label: 'التحقق من حالة الدفع',
                  isLoading: busy,
                  onPressed: widget.onRefresh)
            else if (payment.awaitingConfirmation) ...[
              AppButton(
                  key: const ValueKey('wallet-confirm'),
                  label: payment.customerIsProviderVerified
                      ? 'تأكيد والمتابعة'
                      : 'تحديث بيانات الحساب',
                  isLoading: busy,
                  onPressed: payment.customerIsProviderVerified
                      ? () => flow.confirm(true)
                      : widget.onRefresh),
              TextButton(
                  onPressed: busy ? null : () => flow.confirm(false),
                  child: const Text('إلغاء عملية الدفع')),
            ] else if (payment.awaitingCode)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _code,
                builder: (_, value, __) => AppButton(
                    key: const ValueKey('wallet-complete'),
                    label: 'موافق — متابعة العملية',
                    isLoading: busy,
                    onPressed: value.text.trim().isEmpty ? null : _complete),
              )
            else if (payment.canStartAnother) ...[
              AppButton(
                  label: 'إعادة المحاولة',
                  isLoading: busy,
                  onPressed: widget.onRetry),
              TextButton(
                  onPressed: busy ? null : widget.onChangeMethod,
                  child: const Text('اختيار طريقة دفع أخرى')),
            ] else
              AppButton(
                  label: 'تحديث حالة الدفع',
                  isLoading: busy,
                  onPressed: widget.onRefresh),
            if (payment.awaitingCode) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                  onPressed: busy ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تحديث حالة العملية')),
              const Text('ستُستعاد العملية نفسها إذا أعدت فتح التطبيق.',
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
          ],
        );
      });

  Widget _detail(BuildContext context, String label, String value,
          {bool ltr = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: SelectableText(value.isEmpty ? '—' : value,
                  textAlign: TextAlign.left,
                  textDirection: ltr ? TextDirection.ltr : null,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  String _title(WalletRidePayment payment) => payment.succeeded
      ? 'تم دفع الرحلة بنجاح'
      : payment.awaitingConfirmation
          ? 'تأكيد بيانات الدفع'
          : payment.awaitingCode
              ? _codeLabel(payment.nextAction)
              : payment.processing
                  ? 'جارٍ التحقق من الدفع'
                  : payment.status == 'Cancelled'
                      ? 'أُلغيت عملية الدفع'
                      : payment.status == 'Failed'
                          ? 'لم تكتمل عملية الدفع'
                          : 'عملية الدفع قيد المراجعة';

  String _description(WalletRidePayment payment) {
    // The API persists and rephrases provider messages. Show that reason at
    // every step; titles, controls and receipts still depend only on status.
    final message = payment.message.trim();
    if (message.isNotEmpty) return message;
    return payment.succeeded
        ? 'فاتورة دفع الرحلة عبر ${payment.providerName}. تم تسجيل المبلغ لدى يمن درايف.'
        : payment.awaitingConfirmation
            ? 'راجع بيانات حسابك ومبلغ السحب قبل المتابعة.'
            : payment.awaitingCode && payment.nextAction == 'OneTimePassword'
                ? 'أدخل رمز التحقق المرسل إليك برسالة نصية من ${payment.providerName}.'
                : 'تابع حالة العملية هنا قبل إجراء أي دفع آخر.';
  }

  String _codeLabel(String action) => switch (action) {
        'Voucher' => 'رقم القسيمة',
        'Pin' => 'رمز PIN',
        _ => 'رمز التحقق',
      };

  String _currency(String value) => value == 'YER' ? 'ريال يمني' : value;
  String _money(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  String _date(DateTime value) {
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
