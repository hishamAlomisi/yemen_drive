import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../controllers/wallet_ride_payment_controller.dart';
import '../models/wallet_ride_payment.dart';
import 'external_payment_methods.dart';

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
  String? _lastRejection;
  bool _dialogOpen = false;

  void _queueRejection(WalletRidePayment payment) {
    final flow = widget.controller;
    final revision = flow.rejectionRevision.value;
    final reason = flow.rejectionMessage.value.trim();
    if (flow.busy.value || payment.succeeded || _dialogOpen) return;
    if (reason.isEmpty && payment.status != 'Failed') return;
    final message = reason.isNotEmpty ? reason : _description(payment);
    final token = '${payment.id}:$revision:$message';
    if (_lastRejection == token) return;
    _lastRejection = token;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final current = flow.payment.value;
      if (current?.id != payment.id || current?.succeeded == true) {
        _dialogOpen = false;
        return;
      }
      final colors = Theme.of(context).colorScheme;
      final change = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('wallet-rejection-dialog'),
          icon:
              Icon(Icons.error_outline_rounded, color: colors.error, size: 44),
          title: Text('لم تكتمل عملية الدفع',
              style: TextStyle(color: colors.error)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(payment.providerName, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                _errorBanner(message),
              ],
            ),
          ),
          actions: [
            if (flow.stateKnown.value &&
                (current!.canStartAnother || current.canCancel))
              FilledButton.icon(
                key: const ValueKey('wallet-dialog-change-method'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('تغيير طريقة الدفع'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(payment.awaitingCode ? 'تصحيح الرمز' : 'حسناً'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _dialogOpen = false);
      if (change == true) widget.onChangeMethod();
    });
  }

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
        _queueRejection(payment);
        final description = _description(payment);
        final rejected = payment.status == 'Failed' ||
            flow.rejectionMessage.value.trim() == description ||
            (flow.error.value.isNotEmpty &&
                flow.error.value.trim() == description);
        final method = AppEnvironment.paymentMethods
                .where(
                    (item) => item.paymentMethodId == payment.paymentMethodId)
                .firstOrNull ??
            AppEnvironment.paymentMethods
                .where((item) =>
                    item.providerCode.toLowerCase() ==
                    payment.providerCode.toLowerCase())
                .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!payment.succeeded)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('wallet-header-change-method'),
                  onPressed: !busy &&
                          known &&
                          (payment.canStartAnother || payment.canCancel)
                      ? widget.onChangeMethod
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('تغيير طريقة الدفع'),
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: method != null
                  ? Semantics(
                      label: payment.providerName,
                      image: true,
                      child: Container(
                        key: const ValueKey('wallet-provider-logo'),
                        width: 88,
                        height: 88,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: PaymentCatalogIcon(method: method, size: 72),
                      ),
                    )
                  : CircleAvatar(
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
            Text(
                payment.isTopUp && payment.succeeded
                    ? 'تم شحن محفظتك'
                    : _title(payment),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (rejected)
              _errorBanner(description,
                  key: const ValueKey('wallet-provider-message'))
            else
              Text(description,
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
                  _detail(
                      context,
                      payment.isTopUp ? 'مبلغ الشحن' : 'مبلغ الرحلة',
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
                    if (!payment.isTopUp)
                      _detail(context, 'رقم الرحلة', payment.rideId, ltr: true),
                    if (payment.receipt != null) ...[
                      if (payment.feesKnown)
                        _detail(context, 'إجمالي المبلغ مع رسوم المزود',
                            '${_money(payment.amount + payment.fees!)} ${_currency(payment.currency)}'),
                      _detail(context, 'رقم فاتورة الشحن',
                          '${payment.receipt!['number']}',
                          ltr: true),
                      _detail(context, 'المبلغ المضاف لمحفظتك',
                          '${_money(payment.amount)} ${_currency(payment.currency)}'),
                      _detail(context, 'الرصيد بعد الشحن',
                          '${payment.receipt!['balanceAfter']} ${_currency(payment.currency)}'),
                      const Text(
                          'رسوم المزود معروضة بصورة مستقلة؛ مبلغ الشحن يضاف كاملاً إلى محفظتك.'),
                    ],
                    if (payment.requestId.isNotEmpty)
                      _detail(context, 'مرجع الطلب', payment.requestId,
                          ltr: true),
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
              _errorBanner(flow.error.value),
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
                      ? payment.providerCode == 'Jaib'
                          ? 'تأكيد البيانات والمتابعة إلى رمز التحقق'
                          : 'إتمام السحب وإرسال رمز التحقق'
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
                key: const ValueKey('wallet-change-method'),
                label: 'تغيير طريقة الدفع',
                leading: const Icon(Icons.swap_horiz_rounded),
                onPressed: busy ? null : widget.onChangeMethod,
              ),
              TextButton.icon(
                  onPressed: busy ? null : widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة بهذه المحفظة')),
            ] else if (payment.status == 'ReviewRequired' &&
                payment.canCancel) ...[
              AppButton(
                  key: const ValueKey('wallet-restart-preparation'),
                  label: 'إعادة طلب بيانات الحساب',
                  isLoading: busy,
                  onPressed: widget.onRetry),
              TextButton(
                  onPressed: busy ? null : widget.onRefresh,
                  child: const Text('تحديث حالة الدفع')),
            ] else
              AppButton(
                  label: 'تحديث حالة الدفع',
                  isLoading: busy,
                  onPressed: widget.onRefresh),
            if (payment.canCancel &&
                !payment.awaitingConfirmation &&
                known) ...[
              const SizedBox(height: 12),
              AppButton(
                  key: const ValueKey('wallet-change-method'),
                  variant: AppButtonVariant.outline,
                  leading: const Icon(Icons.swap_horiz_rounded),
                  onPressed: busy ? null : widget.onChangeMethod,
                  label: 'تغيير طريقة الدفع'),
            ],
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

  Widget _errorBanner(String message, {Key? key}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: colors.onErrorContainer, fontWeight: FontWeight.w600)),
      ),
    );
  }

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
        ? payment.isTopUp
            ? 'فاتورة شحن محفظتك عبر ${payment.providerName}.'
            : 'فاتورة دفع الرحلة عبر ${payment.providerName}. تم تسجيل المبلغ لدى يمن درايف.'
        : payment.awaitingConfirmation
            ? 'راجع بيانات حسابك ومبلغ السحب قبل المتابعة.'
            : payment.awaitingCode && payment.nextAction == 'OneTimePassword'
                ? 'أدخل رمز التحقق المرسل إليك برسالة نصية من ${payment.providerName}.'
                : payment.status == 'Failed'
                    ? 'لم تقبل المحفظة عملية الدفع. يمكنك اختيار طريقة دفع أخرى.'
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
