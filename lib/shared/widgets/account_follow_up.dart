import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';
import 'ride_financial_follow_up.dart';

class AccountFollowUp extends StatefulWidget {
  const AccountFollowUp({super.key});
  @override
  State<AccountFollowUp> createState() => _AccountFollowUpState();
}
class _AccountFollowUpState extends State<AccountFollowUp> with WidgetsBindingObserver {
  List<Map<String, Object?>> _tickets = [];
  List<Map<String, Object?>> _deletions = [];
  bool _busy = false;
  String? _error;
  Timer? _timer;
  static Map<String, Object?> _map(Object? value) => value is Map ? Map<String, Object?>.from(value) : {};
  Future<Object?> _call(String model, String operation, Map<String, Object?> data) async {
    final result = await Get.find<ApiClient>().execute<Object?>(model: model, operation: operation, data: data);
    if (result is ApiFailure) throw FormatException(result.problem.detail ?? result.problem.title);
    return (result as ApiSuccess).data;
  }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); unawaited(_refresh()); _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh()); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) unawaited(_refresh()); }
  Future<void> _load() async {
    final tickets = await _call('SupportTicketModel', 'list', {});
    final deletions = await _call('AccountDeletionModel', 'list', {});
    if (mounted) setState(() { _tickets = tickets is List ? tickets.map(_map).toList() : []; _deletions = deletions is List ? deletions.map(_map).toList() : []; _error = null; });
  }
  Future<void> _refresh() async {
    if (_busy) return; setState(() => _busy = true);
    try { await _load(); } catch (error) { if (mounted) setState(() => _error = '$error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<String?> _message(String title, String hint) async {
    final input = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: TextField(controller: input, maxLength: 2000, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: hint)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(operationalText('رجوع', 'Back'))),
        FilledButton(onPressed: () { if (input.text.trim().length >= 3) Navigator.pop(context, input.text.trim()); }, child: Text(operationalText('إرسال', 'Send')))],
    ));
    unawaited(Future<void>.delayed(const Duration(milliseconds: 400), input.dispose)); return result;
  }
  Future<void> _submit(String model, String operation, Map<String, Object?> data) async {
    if (_busy) return; setState(() => _busy = true);
    try { await _call(model, operation, data); await _load(); }
    catch (error) { if (mounted) setState(() => _error = '$error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  String _status(Object? value) => switch ('$value') {
    'Open' => operationalText('تم الاستلام', 'Received'),
    'Assigned' => operationalText('أُسند إلى مسؤول', 'Assigned'),
    'Investigating' => operationalText('تجري المراجعة', 'Under investigation'),
    'AwaitingCustomer' => operationalText('بانتظار ردك', 'Awaiting your reply'),
    'Resolved' => operationalText('تمت المعالجة', 'Resolved'),
    'Closed' => operationalText('مغلق', 'Closed'),
    'Pending' => operationalText('بانتظار مراجعة الإدارة', 'Awaiting administrative review'),
    'Rejected' => operationalText('لم توافق الإدارة', 'Request rejected'),
    'AccountDisabledRetentionReview' => operationalText('عُطّل الحساب وتُراجع البيانات المحتفظ بها', 'Account disabled; retained evidence under review'),
    _ => operationalText('تجري المتابعة', 'Follow-up in progress'),
  };
  Future<void> _openTicket(Map<String, Object?> ticket) async {
    try {
      final result = _map(await _call('SupportTicketModel', 'get', {'id': ticket['id']}));
      final entries = result['entries'];
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text(operationalText('سجل البلاغ #${ticket['id']}', 'Ticket history #${ticket['id']}')),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: entries is List ? entries.map((raw) { final x = _map(raw); return Padding(padding: const EdgeInsets.only(bottom: 15), child: Text('${x['createdAtUtc']}\n${_status(x['status'])}\n${x['message']}')); }).toList() : [Text(operationalText('لا توجد رسائل إضافية.', 'No additional messages.'))]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(operationalText('إغلاق', 'Close')))],
      ));
    } catch (error) { if (mounted) setState(() => _error = '$error'); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(operationalText('الدعم ومتابعة الحساب', 'Support and account follow-up'))),
    body: RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Container(color: Colors.red.shade50, padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade900))),
      FilledButton.icon(onPressed: _busy ? null : () async { final note = await _message(operationalText('بلاغ جديد', 'New support ticket'), operationalText('التفاصيل ورقم الرحلة والأدلة المتاحة', 'Details, trip number and available evidence')); if (note != null) await _submit('SupportTicketModel', 'add', {'message': note, 'category': 'General'}); }, icon: const Icon(Icons.support_agent), label: Text(operationalText('إرسال بلاغ', 'Submit a support ticket'))),
      Text(operationalText('تعرض هنا الردود وحالة المراجعة. بلاغ السلامة داخل الرحلة مستقل عن الدفع أو الإلغاء.', 'Replies and review status appear here. In-trip safety reporting is independent of payment or cancellation.')),
      for (final x in _tickets) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('بلاغ #${x['id']} • ${_status(x['status'])}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('${x['message']}'),
        if (x['adminReply'] != null) Text(operationalText('رد الإدارة: ${x['adminReply']}', 'Administrative reply: ${x['adminReply']}')),
        Text(x['assignedAdminId'] == null ? operationalText('يحتاج إسناداً من الإدارة', 'Needs administrative assignment') : operationalText('أُسند إلى مسؤول للمراجعة', 'Assigned to a reviewer')),
        TextButton(onPressed: () => _openTicket(x), child: Text(operationalText('عرض سجل المعالجة', 'View case history'))),
        OutlinedButton(onPressed: _busy ? null : () async { final note = await _message(operationalText('رد على البلاغ #${x['id']}', 'Reply to ticket #${x['id']}'), operationalText('ردك أو اعتراضك مع التفاصيل', 'Your reply or objection with details')); if (note != null) await _submit('SupportTicketModel', 'update', {'id': x['id'], 'message': note}); }, child: Text(operationalText('رد أو طلب إعادة المراجعة', 'Reply or request another review'))),
      ]))),
      if (_tickets.isEmpty && !_busy) Text(operationalText('لا توجد بلاغات مسجلة.', 'No support tickets recorded.')),
      const Divider(), Text(operationalText('طلب حذف الحساب', 'Account deletion request'), style: TextStyle(fontWeight: FontWeight.bold)),
      Text(operationalText('تراجع الإدارة الأرصدة والديون والاسترجاع قبل تعطيل الحساب. تُلغى الجلسات عند التعطيل، وتحفظ الأدلة المالية والتاريخية وفق السياسة المعتمدة. تقديم الطلب لا يمسح السجلات فوراً.', 'Administration reviews balances, debts and refunds before disabling the account. Sessions are revoked on disabling; financial and historical evidence is retained under approved policy. A request does not immediately erase records.')),
      for (final x in _deletions) ListTile(title: Text('طلب #${x['id']} • ${_status(x['status'])}'), subtitle: Text('${x['reason']}\n${x['adminNote'] ?? operationalText('لم تصدر نتيجة بعد', 'No decision yet')}')),
      OutlinedButton.icon(onPressed: _busy || _deletions.any((x) => x['status'] == 'Pending') ? null : () async { final note = await _message(operationalText('طلب حذف الحساب', 'Account deletion request'), operationalText('سبب الطلب؛ أقر بفهم مراجعة الأموال وحفظ الأدلة', 'Reason; acknowledge financial review and evidence retention')); if (note != null) await _submit('AccountDeletionModel', 'add', {'reason': '$note — فهمت مراجعة الالتزامات وحفظ الأدلة المالية والتاريخية.'}); }, icon: const Icon(Icons.person_remove_outlined), label: Text(operationalText('تقديم طلب حذف للمراجعة', 'Submit deletion request for review'))),
    ])));
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); super.dispose(); }
}
