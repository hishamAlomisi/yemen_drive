import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../controllers/wallet_controller.dart';
import '../repositories/wallet_transfer_repository.dart';

class WalletTransferPage extends StatefulWidget {
  const WalletTransferPage({
    super.key,
    this.repository,
    this.reference,
    this.storageKey,
    this.store,
  });
  final WalletTransferRepository? repository;
  final String? reference;
  final String? storageKey;
  final GetStorage? store;
  @override
  State<WalletTransferPage> createState() => _WalletTransferPageState();
}

class _WalletTransferPageState extends State<WalletTransferPage> {
  final phone = TextEditingController(),
      amount = TextEditingController(),
      note = TextEditingController();
  final form = GlobalKey<FormState>();
  late final repository =
      widget.repository ?? ApiWalletTransferRepository(Get.find<ApiClient>());
  late final storageKey = widget.storageKey ??
      'wallet-transfer-${Get.find<AuthSessionService>().currentUserId.value}';
  late final storage = widget.store ?? GetStorage();
  String requestId = const Uuid().v4();
  String? error;
  bool busy = false;
  Map<String, dynamic>? invoice;
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ref = widget.reference ??
          (Get.arguments is Map
              ? Get.arguments['reference']?.toString()
              : null) ??
          storage.read<String>(storageKey);
      if (ref != null) await recover(ref);
      try {
        final items = await repository.history();
        if (mounted) setState(() => history = items);
      } catch (_) {/* The form remains usable when history is unavailable. */}
    });
  }

  String message(Object e) => e.toString().replaceFirst('Exception: ', '');
  Future<void> recover(String reference) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await repository.request('get', {'reference': reference});
      if (!mounted) return;
      if (data['status'] == 'Completed') {
        await showInvoice(data);
      } else if (data['status'] == 'Expired') {
        await storage.remove(storageKey);
        setState(
          () => error =
              'انتهت صلاحية التأكيد السابق. أدخل البيانات وتابع من جديد.',
        );
      } else {
        setState(() => busy = false);
        await confirmSheet(data);
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> follow() async {
    final pending = storage.read<String>(storageKey);
    if (!busy && pending != null) {
      await recover(pending);
      return;
    }
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await repository.request('quote', {
        'requestId': requestId,
        'phoneNumber': phone.text.trim(),
        'amount': double.parse(normalizeNumber(amount.text)),
        'note': note.text.trim(),
      });
      await storage.write(storageKey, data['reference']);
      if (!mounted) return;
      if (data['status'] == 'Completed') {
        await showInvoice(data);
      } else if (data['status'] == 'Expired') {
        requestId = const Uuid().v4();
        await storage.remove(storageKey);
        setState(() => error = 'انتهت صلاحية التأكيد. اضغط متابعة مرة أخرى.');
      } else {
        setState(() => busy = false);
        await confirmSheet(data);
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmSheet(Map<String, dynamic> data) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تأكيد التحويل',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TransferDetails(data: data),
              const SizedBox(height: 12),
              const Text(
                'راجع بيانات المستلم. يسري عرض الرسوم لمدة خمس دقائق.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('تأكيد'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('تعديل البيانات'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      requestId = const Uuid().v4();
      await storage.remove(storageKey);
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordConfirmation(
        repository: repository,
        reference: data['reference'].toString(),
      ),
    );
    if (result != null && mounted) await showInvoice(result);
  }

  Future<void> showInvoice(Map<String, dynamic> data) async {
    await storage.remove(storageKey);
    if (!mounted) return;
    setState(() {
      invoice = data;
      error = null;
      history = [
        data,
        ...history.where((item) => item['reference'] != data['reference'])
      ];
    });
    if (Get.isRegistered<WalletController>()) {
      await Get.find<WalletController>().loadTransactions();
    }
  }

  void resetRequest(String _) {
    requestId = const Uuid().v4();
  }

  @override
  void dispose() {
    phone.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تحويل لحساب')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: invoice != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 60,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'فاتورة التحويل',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Text(
                        'تم التحويل بنجاح',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TransferDetails(data: invoice!),
                            const Divider(),
                            SelectableText(
                              'رقم العملية: ${invoice!['reference']}',
                            ),
                            Text(
                              'التاريخ: ${DateTime.tryParse('${invoice!['completedAtUtc']}')?.toLocal() ?? ''}',
                            ),
                            Text(
                              'رصيدك بعد التحويل: ${money(invoice!['senderBalanceAfter'])}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            invoice = null;
                            requestId = const Uuid().v4();
                            phone.clear();
                            amount.clear();
                            note.clear();
                          });
                        },
                        child: const Text('تحويل جديد'),
                      ),
                    ],
                  )
                : Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'حوّل من محفظتك إلى محفظة عميل أو سائق برقم هاتفه.',
                        ),
                        const SizedBox(height: 20),
                        AppTextField(
                          controller: phone,
                          label: 'رقم هاتف المستلم',
                          keyboardType: TextInputType.phone,
                          enabled: !busy,
                          onChanged: resetRequest,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'أدخل رقم هاتف المستلم'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: amount,
                          label: 'المبلغ (ر.ي)',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          enabled: !busy,
                          onChanged: resetRequest,
                          validator: (v) {
                            final n = double.tryParse(normalizeNumber(v ?? ''));
                            return n == null ||
                                    !n.isFinite ||
                                    n <= 0 ||
                                    !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(
                                      normalizeNumber(v ?? ''),
                                    )
                                ? 'أدخل مبلغاً صحيحاً بمنزلتين عشريتين كحد أقصى'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: note,
                          label: 'ملاحظة (اختياري)',
                          maxLines: 3,
                          enabled: !busy,
                          onChanged: resetRequest,
                          validator: (v) => (v ?? '').length > 500
                              ? 'الحد الأقصى 500 حرف'
                              : null,
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: busy ? null : follow,
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: const Text('متابعة'),
                        ),
                        if (storage.read<String>(storageKey) != null)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => recover(
                                      storage.read<String>(storageKey)!,
                                    ),
                            child: const Text('متابعة التحويل السابق'),
                          ),
                        if (history.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'التحويلات السابقة',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final item in history)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text('${item['recipientName']}'),
                              subtitle: Text(
                                '${money(item['amount'])} — ${item['recipientPhone']}',
                              ),
                              onTap: busy
                                  ? null
                                  : () => recover('${item['reference']}'),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      );
}

String normalizeNumber(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  return value
      .trim()
      .split('')
      .map(
        (c) => arabic.contains(c)
            ? '${arabic.indexOf(c)}'
            : persian.contains(c)
                ? '${persian.indexOf(c)}'
                : c == '٫'
                    ? '.'
                    : c,
      )
      .join();
}

String money(Object? value) =>
    '${(value is num ? value : num.tryParse('$value') ?? 0).toStringAsFixed(2)} ر.ي';

class TransferDetails extends StatelessWidget {
  const TransferDetails({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${data['recipientName']} (${data['recipientType']})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('رقم الهاتف: ${data['recipientPhone']}'),
          const SizedBox(height: 8),
          Text('المبلغ: ${money(data['amount'])}'),
          const SizedBox(height: 8),
          Text('رسوم التحويل: ${money(data['fee'])}'),
          const SizedBox(height: 8),
          Text(
            'الملاحظة: ${data['note']?.toString().isNotEmpty == true ? data['note'] : 'بدون ملاحظة'}',
          ),
          const Divider(height: 28),
          Text(
            'إجمالي الخصم: ${money(data['total'])}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      );
}

class _PasswordConfirmation extends StatefulWidget {
  const _PasswordConfirmation({
    required this.repository,
    required this.reference,
  });
  final WalletTransferRepository repository;
  final String reference;
  @override
  State<_PasswordConfirmation> createState() => _PasswordConfirmationState();
}

class _PasswordConfirmationState extends State<_PasswordConfirmation> {
  final password = TextEditingController();
  bool busy = false, hidden = true;
  String? error;
  Future<void> confirm() async {
    if (busy) return;
    if (password.text.isEmpty) {
      setState(() => error = 'أدخل كلمة المرور الخاصة بحسابك');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.request(
        'confirm',
        {'reference': widget.reference, 'password': password.text},
      );
      password.clear();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      password.clear();
      // A lost response may follow a committed transfer. Recover its receipt using the same reference.
      try {
        final current = await widget.repository
            .request('get', {'reference': widget.reference});
        if (current['status'] == 'Completed') {
          if (mounted) Navigator.pop(context, current);
          return;
        }
      } catch (_) {/* Keep the reference for a safe retry. */}
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('تأكيد كلمة المرور'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('أدخل كلمة المرور الخاصة بحسابك لإتمام التحويل'),
                const SizedBox(height: 16),
                AppTextField(
                  controller: password,
                  label: 'كلمة المرور',
                  obscureText: hidden,
                  enabled: !busy,
                  onSubmitted: (_) => confirm(),
                  suffixIcon: IconButton(
                    tooltip: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: busy ? null : confirm,
              child: Text(busy ? 'جارٍ التأكيد…' : 'تأكيد'),
            ),
          ],
        ),
      );
}
