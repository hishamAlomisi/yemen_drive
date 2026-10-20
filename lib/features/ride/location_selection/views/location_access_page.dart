import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

/// Rechecks Android settings on return, before requesting app permission.
class LocationAccessPage extends StatefulWidget {
  const LocationAccessPage({super.key});
  @override
  State<LocationAccessPage> createState() => _LocationAccessPageState();
}

class _LocationAccessPageState extends State<LocationAccessPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _waitingForSettings = false;
  bool _servicesEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(requestPermission: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      _check(requestPermission: true);
    }
  }

  Future<void> _check({required bool requestPermission}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (enabled &&
          requestPermission &&
          permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      _servicesEnabled = enabled;
      _permission = permission;
      if (enabled &&
          (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always)) {
        Get.back<bool>(result: true);
      }
    } catch (_) {
      if (mounted) _error = 'تعذر التحقق من إعدادات الموقع. حاول مرة أخرى.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (_busy) return;
    await _check(requestPermission: true);
    if (!mounted) return;
    if (!_servicesEnabled || _permission == LocationPermission.deniedForever) {
      _waitingForSettings = true;
      final opened = !_servicesEnabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) {
        _waitingForSettings = false;
        setState(() => _error =
            'افتح إعدادات الهاتف وفعّل الموقع وصلاحية التطبيق، ثم حاول مجددًا.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الموقع الحالي')),
      body: SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: SingleChildScrollView(
                  child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),
              Container(
                  height: 210,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(40)),
                  child: Icon(Icons.share_location_rounded,
                      size: 135, color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(height: 36),
              Text('فعّل موقعك', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 16),
              Text(
                  'نحتاج إلى تشغيل موقع الهاتف ثم السماح للتطبيق بالوصول إليه لتحديد موقعك الحالي على الخريطة.',
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
              Text(
                  'يمكنك العودة إلى البحث واختيار مكان الانطلاق والوجهة يدويًا.',
                  style: theme.textTheme.bodyMedium),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error))),
            ],
          ))),
          FilledButton(
              onPressed: _busy ? null : _enable,
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(!_servicesEnabled
                      ? 'تفعيل خدمة الموقع'
                      : _permission == LocationPermission.deniedForever
                          ? 'فتح صلاحيات التطبيق'
                          : 'السماح بالوصول إلى الموقع'))),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Get.back<bool>(result: false),
              child: const Text('العودة إلى البحث')),
        ]),
      )),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
