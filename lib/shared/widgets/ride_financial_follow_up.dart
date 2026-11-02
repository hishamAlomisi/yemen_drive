import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';

String operationalText(String ar, String en) =>
    Get.locale?.languageCode == 'en' ? en : ar;

/// Decisions are reloaded from the server, including when opened from old alerts.
class RideFinancialFollowUp extends StatefulWidget {
  const RideFinancialFollowUp(
      {required this.rideId, this.isDriver = false, this.onPay, super.key});
  final int rideId;
  final bool isDriver;
  final Future<void> Function()? onPay;
  @override
  State<RideFinancialFollowUp> createState() => _RideFinancialFollowUpState();
}

class _RideFinancialFollowUpState extends State<RideFinancialFollowUp>
    with WidgetsBindingObserver {
  Map<String, Object?> _detail = {};
  Map<String, Object?>? _cancellation;
  List<Map<String, Object?>> _cases = [];
  bool _busy = false;
  String? _error;
  Timer? _timer;
  ApiClient get _api => Get.find<ApiClient>();
  static Map<String, Object?> _map(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : {};
  double _amount(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  String _money(Object? value) => '${_amount(value).toStringAsFixed(2)} YER';
  Future<Object?> _execute(
      String model, String operation, Map<String, Object?> data) async {
    final result = await _api.execute<Object?>(
        model: model, operation: operation, data: data);
    if (result is ApiFailure)
      throw FormatException(result.problem.detail ?? result.problem.title);
    return (result as ApiSuccess).data;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final detail =
        _map(await _execute('RideModel', 'get', {'id': widget.rideId}));
    final cases = await _execute(
        'RideFinancialCaseModel', 'list', {'rideId': widget.rideId});
    // No cancellation is a normal outcome for completed trips.
    final result = await _api.execute<Object?>(
        model: 'RideCancellationRequestModel',
        operation: 'get',
        data: {'rideId': widget.rideId});
    if (result is ApiFailure &&
        result.problem.code != 'cancellation_request_not_found') {
      throw FormatException(result.problem.detail ?? result.problem.title);
    }
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _cases = cases is List ? cases.map(_map).toList() : [];
      _cancellation = result is ApiSuccess ? _map(result.data) : null;
      _error = null;
    });
  }

  Future<void> _decide(String model, String action, Map<String, Object?> data,
      {String? confirmation}) async {
    if (_busy) return;
    if (confirmation != null &&
        await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                      title: Text(
                          operationalText('تأكيد القرار', 'Confirm decision')),
                      content: Text(confirmation),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(operationalText('رجوع', 'Back'))),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(operationalText('تأكيد', 'Confirm')))
                      ],
                    )) !=
            true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _execute(model, action, data);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dispute() async {
    final input = TextEditingController();
    final note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(operationalText('اعتراض مالي', 'Financial dispute')),
              content: TextField(
                  controller: input,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                      labelText: operationalText('السبب والأدلة المتاحة',
                          'Reason and available evidence'))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(operationalText('رجوع', 'Back'))),
                FilledButton(
                    onPressed: () {
                      if (input.text.trim().length >= 3)
                        Navigator.pop(context, input.text.trim());
                    },
                    child: Text(
                        operationalText('إرسال للمراجعة', 'Submit for review')))
              ],
            ));
    // Wait for the dialog's reverse animation before disposing its controller.
    unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400), input.dispose));
    if (note != null && mounted)
      await _decide('RideFinancialCaseModel', 'add',
          {'rideId': widget.rideId, 'note': note});
  }

  Widget _line(String ar, String en, Object? amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(operationalText(ar, en))),
        Text(_money(amount),
            style: const TextStyle(fontWeight: FontWeight.bold))
      ]));
  Widget _button(String ar, String en, VoidCallback action) => OutlinedButton(
      onPressed: _busy || (_error != null && ar != 'تحديث الحالة المؤكدة')
          ? null
          : action,
      child: Text(operationalText(ar, en)));
  @override
  Widget build(BuildContext context) {
    final money = _map(_detail['finance']);
    final ride = _map(_detail['ride']);
    final ended = ride['serviceEndedAtUtc'] != null ||
        {'6', '7', 'Completed', 'Cancelled'}.contains('${ride['status']}');
    return Scaffold(
        appBar: AppBar(
            title: Text(operationalText('فاتورة الرحلة والمتابعة المالية',
                'Trip invoice and financial follow-up'))),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(padding: const EdgeInsets.all(18), children: [
              Text('${operationalText('الرحلة', 'Trip')} #${widget.rideId}',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(ended
                  ? operationalText(
                      'انتهت خدمة النقل. التسوية المالية مستقلة ويمكن متابعتها هنا.',
                      'Transport has ended. Financial settlement remains available here.')
                  : operationalText('خدمة النقل نشطة', 'Transport is active')),
              _line(
                  money['amountUnderReview'] == true
                      ? 'المبلغ قبل مراجعة خصومات الإلغاء'
                      : 'المبلغ المستحق',
                  money['amountUnderReview'] == true
                      ? 'Amount before cancellation review'
                      : 'Amount due',
                  money['amountDue']),
              if (money['amountUnderReview'] == true)
                Text(operationalText(
                    'هذا المبلغ قيد مراجعة الجزء المنفذ والمسؤولية، ولا يمثل ديناً نهائياً يمنع رحلة جديدة. لا يُطلب تحصيله حتى اعتماد التسوية.',
                    'Delivered service and responsibility are under review. This is not confirmed debt blocking a new ride; collection waits for settlement.')),
              _line('المقبوض المؤكد', 'Verified receipts', money['paidAmount']),
              _line('المسترد فعلياً', 'Completed refunds',
                  money['refundedAmount']),
              _line('المتبقي للسداد', 'Outstanding balance',
                  money['outstandingAmount']),
              _line('حق الاسترداد المتبقي', 'Remaining refund entitlement',
                  money['refundDue']),
              if (money['providerPending'] == true)
                Text(operationalText(
                    'نتيجة محاولة المزود الأصلية لم تُحسم. لا يُحصّل مبلغ بديل قبل التحقق منها.',
                    'The original provider outcome is unresolved. A replacement collection is blocked until reconciliation.')),
              if (!widget.isDriver &&
                  widget.onPay != null &&
                  _amount(money['outstandingAmount']) > 0 &&
                  money['providerPending'] != true &&
                  money['amountUnderReview'] != true)
                _button('سداد المتبقي / تغيير طريقة الدفع',
                    'Pay remaining balance / change method', () async {
                  await widget.onPay!();
                  if (mounted) await _refresh();
                }),
              if (!widget.isDriver)
                _button('اعتراض على المبلغ أو طلب مراجعة',
                    'Dispute amount or request review', _dispute),
              if (_cancellation case final request?) ...[
                const Divider(),
                Text(
                    operationalText('متابعة الإلغاء والاسترداد',
                        'Cancellation and refund follow-up'),
                    style: Theme.of(context).textTheme.titleMedium),
                Text('${request['reason'] ?? ''}'),
                _line('صافي الاسترداد المطلوب', 'Requested net refund',
                    request['requestedRefundAmount']),
                Text(switch (request['refundDestination']) {
                  'YemenDriveWallet' => operationalText(
                      'الاسترداد لمحفظة التطبيق بعد موافقتك',
                      'Refund to app wallet with your consent'),
                  'VerifiedAlternative' => operationalText(
                      'استرداد بديل مثبت بدليل تحويل واستلام',
                      'Verified alternative refund with payout and receipt evidence'),
                  'Cash' => operationalText('استرداد نقدي يحتاج تأكيد الاستلام',
                      'Cash refund requires receipt confirmation'),
                  _ => operationalText('تراجع الإدارة طريقة الاسترداد والأدلة',
                      'Administration reviews refund method and evidence'),
                }),
                if (request['financialReviewPending'] == true)
                  Text(operationalText(
                      'قيد المعالجة المالية لدى الإدارة؛ النقل منتهٍ.',
                      'Financial review is assigned to administration; transport has ended.')),
                if (request['canDecide'] == true && widget.isDriver) ...[
                  _button(
                      'أوافق على طلب الإلغاء',
                      'Accept cancellation request',
                      () => _decide('RideCancellationRequestModel', 'accept',
                          {'id': request['id']},
                          confirmation: operationalText(
                              'الموافقة تسجل قرارك. مراجعة المسؤولية والاسترداد لدى الإدارة مستقلة عن النقل المنتهي.',
                              'Acceptance records your decision. Administrative responsibility and refund review remain separate from ended transport.'))),
                  _button(
                      'أعترض وأحيل للمراجعة',
                      'Disagree and refer for review',
                      () => _decide('RideCancellationRequestModel', 'reject',
                          {'id': request['id']})),
                ],
                if (request['canDecide'] == true && !widget.isDriver) ...[
                  if (request['cashReceiptPending'] == true)
                    _button(
                        'استلمت المبلغ نقداً',
                        'I received the cash refund',
                        () => _decide('RideCancellationRequestModel', 'accept',
                            {'id': request['id'], 'refundChoiceRevision': request['refundChoiceRevision']},
                            confirmation: operationalText(
                                'أكد استلام المبلغ فعلياً من السائق. هذا يؤكد الاسترداد النقدي.',
                                'Confirm you physically received the refund from the driver.')))
                  else if (request['refundConsentPending'] == true)
                    _button(
                        'أوافق على الاسترداد لمحفظة التطبيق',
                        'Accept refund to app wallet',
                        () => _decide('RideCancellationRequestModel', 'accept',
                            {'id': request['id'], 'refundChoiceRevision': request['refundChoiceRevision']},
                            confirmation: operationalText(
                                'سيضاف المبلغ إلى محفظة يمن درايف. السحب الخارجي غير متاح حالياً. يمكنك رفض الطريقة وطلب بديل من الإدارة.',
                                'Funds will be credited to the Yemen Drive wallet. External withdrawal is currently unavailable; you may request an alternative.')))
                  else
                    _button('الموافقة على طلب الإلغاء', 'Accept cancellation request', () => _decide('RideCancellationRequestModel', 'accept', {'id': request['id']})),
                  _button(
                      'لم أستلم / أطلب طريقة بديلة أو مراجعة',
                      'Not received / request alternative or review',
                      () => _decide('RideCancellationRequestModel', 'reject', {
                            'id': request['id'],
                            'refundChoiceRevision':
                                request['refundChoiceRevision']
                          })),
                ],
                if (widget.isDriver &&
                    request['canChooseRefundMethod'] == true) ...[
                  _button(
                      'أعدت المبلغ نقداً، اطلب تأكيد الراكب',
                      'Cash returned: request rider receipt confirmation',
                      () => _decide('RideCancellationRequestModel', 'update', {
                            'id': request['id'],
                            'requestedRefundMethod': 1,
                            'cashReturned': true,
                            'refundChoiceRevision':
                                request['refundChoiceRevision']
                          })),
                  _button(
                      'اقتراح الاسترداد لمحفظة الراكب',
                      'Propose refund to rider wallet',
                      () => _decide('RideCancellationRequestModel', 'update', {
                            'id': request['id'],
                            'requestedRefundMethod': 2,
                            'refundChoiceRevision':
                                request['refundChoiceRevision']
                          })),
                ],
              ],
              for (final item in _cases)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  '${operationalText('معالجة مالية', 'Financial case')} #${item['id']} — ${_status(item['status'])}'),
                              Text(_money(item['amount'])),
                              Text('${item['note'] ?? ''}'),
                              if (item['assignedAdminId'] != null)
                                Text(
                                    '${operationalText('مسؤول المراجعة', 'Review owner')}: #${item['assignedAdminId']}'),
                              if (!widget.isDriver &&
                                  {
                                    'AwaitingCashReceipt',
                                    'AwaitingCustomer',
                                    'AwaitingConsent'
                                  }.contains(item['status'])) ...[
                                _button(
                                    item['status'] == 'AwaitingCashReceipt'
                                        ? 'استلمت الباقي نقداً'
                                        : 'أختار إضافة المبلغ لمحفظتي',
                                    item['status'] == 'AwaitingCashReceipt'
                                        ? 'I received the cash change'
                                        : 'Choose credit to my wallet',
                                    () => _decide('RideFinancialCaseModel',
                                        'accept', {'id': item['id']},
                                        confirmation: item['status'] ==
                                                'AwaitingCashReceipt'
                                            ? operationalText(
                                                'أكد استلامك الفعلي للباقي.',
                                                'Confirm physical receipt of the change.')
                                            : operationalText(
                                                'المبلغ سيبقى رصيداً داخل التطبيق. الإضافة اختيارية والسحب الخارجي غير متاح حالياً.',
                                                'The amount becomes app wallet balance. This is optional; external withdrawal is currently unavailable.'))),
                                _button(
                                    'أطلب النقد أو معالجة بديلة',
                                    'Request cash or alternative review',
                                    () => _decide('RideFinancialCaseModel',
                                        'reject', {'id': item['id']})),
                              ],
                              if (!widget.isDriver &&
                                  item['kind'] == 'FareDecrease' &&
                                  item['status'] == 'AwaitingConsent')
                                _button(
                                    'أختار استلام فرق الأجرة نقداً',
                                    'Choose cash fare refund',
                                    () => _decide('RideFinancialCaseModel',
                                            'update', {
                                          'id': item['id'],
                                          'resolution': 'RequestCash'
                                        })),
                              if (widget.isDriver &&
                                  ((item['kind'] == 'CashChange' &&
                                          item['status'] ==
                                              'AwaitingCustomer') ||
                                      (item['kind'] == 'FareDecrease' &&
                                          item['status'] ==
                                              'AwaitingCashReturn')))
                                _button(
                                    'أعدت الباقي نقداً، اطلب تأكيد الراكب',
                                    'Cash change returned: request receipt confirmation',
                                    () => _decide('RideFinancialCaseModel',
                                            'update', {
                                          'id': item['id'],
                                          'resolution': 'CashReturned'
                                        })),
                            ]))),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_busy) const LinearProgressIndicator(),
              _button(
                  'تحديث الحالة المؤكدة', 'Refresh verified state', _refresh),
            ])));
  }

  String _status(Object? value) => switch ('$value') {
        'AwaitingCashReturn' => operationalText(
            'اختار الراكب الاسترداد نقداً من السائق',
            'Rider chose a cash refund from driver'),
        'Superseded' => operationalText('أعيد الاحتساب بتغيير وجهة أحدث',
            'Recalculated by a newer route change'),
        'Resolved' => operationalText('تمت التسوية', 'Resolved'),
        'Disputed' || 'ManualReview' => operationalText(
            'اعتراض قيد مراجعة الإدارة', 'Dispute under administrative review'),
        'AwaitingCashReceipt' => operationalText(
            'بانتظار تأكيد استلام النقد', 'Awaiting cash receipt confirmation'),
        'AwaitingConsent' ||
        'AwaitingCustomer' =>
          operationalText('بانتظار اختيار الراكب', 'Awaiting rider choice'),
        'AwaitingProvider' => operationalText('بانتظار نتيجة المزود الأصلية',
            'Awaiting original provider outcome'),
        _ => operationalText(
            'مبلغ مستحق للمتابعة', 'Outstanding amount for follow-up'),
      };
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
