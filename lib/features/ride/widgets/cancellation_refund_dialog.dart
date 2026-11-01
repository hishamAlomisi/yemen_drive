import 'package:flutter/material.dart';

class CancellationRefundDialog extends StatelessWidget {
  const CancellationRefundDialog({required this.quote, super.key});
  final Map<String, Object?> quote;

  num? _number(String key) => num.tryParse('${quote[key] ?? ''}');
  String _money(String key) {
    final value = _number(key);
    final currency =
        quote['currency'] == 'YER' ? 'ريال يمني' : '${quote['currency'] ?? ''}';
    return value == null
        ? 'تقدّره الإدارة بعد المراجعة'
        : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)} $currency';
  }

  @override
  Widget build(BuildContext context) {
    final started = quote['rideStarted'] == true;
    return AlertDialog(
      key: const ValueKey('cancellation-refund-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      icon: Icon(Icons.account_balance_wallet_outlined,
          color: Theme.of(context).colorScheme.primary, size: 40),
      title: const Text('استرداد المبلغ بعد الإلغاء'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(started
                ? 'بعد موافقة السائق والإدارة، يُعاد المبلغ إلى محفظة التطبيق بعد خصم الجزء المقطوع والرسوم.'
                : 'بعد موافقة السائق والإدارة، يُعاد المبلغ إلى محفظة التطبيق بعد خصم الرسوم.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('المبلغ المتوقع استرداده: ${_money('refundAmount')}',
                  key: const ValueKey('cancellation-refund-amount'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            _row('إجمالي المبلغ المخصوم', _money('totalDeductions')),
            const Divider(height: 24),
            _row('المبلغ المدفوع', _money('paidAmount')),
            _row('رسوم الرحلة', _money('serviceFee')),
            _row('رسوم الإلغاء', _money('cancellationFee')),
            if (started) _row('أجرة الجزء المقطوع', _money('travelledFare')),
            if ((_number('waitingFee') ?? 0) > 0)
              _row('رسوم الانتظار', _money('waitingFee')),
            if ((_number('routeChangeFees') ?? 0) > 0)
              _row('رسوم تغيير المسار', _money('routeChangeFees')),
            if (quote['canCalculateRefund'] != true) ...[
              const SizedBox(height: 12),
              Text(
                  '${quote['calculationMessage'] ?? 'تراجع الإدارة تفاصيل المسافة قبل اعتماد مبلغ الاسترداد.'}'),
            ],
            const SizedBox(height: 12),
            const Text(
                'يُثبت المبلغ عند إرسال الطلب، ويصلك إشعار عند اعتماد الاسترداد.'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('العودة')),
        FilledButton(
          key: const ValueKey('confirm-cancellation-refund'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('إرسال طلب الإلغاء'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(spacing: 12, runSpacing: 4, children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
        ]),
      );
}
