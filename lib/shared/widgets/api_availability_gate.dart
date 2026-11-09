import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/startup_connection_service.dart';

/// Preserves navigation, form input and local GPS during a temporary outage.
class ApiAvailabilityGate extends StatelessWidget {
  const ApiAvailabilityGate(
      {required this.connection, required this.child, super.key});
  final StartupConnectionService connection;
  final Widget child;
  @override
  Widget build(BuildContext context) => Obx(() {
        final unavailable = connection.runtimeUnavailable.value;
        final checking = !connection.status.value.hasFailed;
        final colors = Theme.of(context).colorScheme;
        return Stack(fit: StackFit.expand, children: [
          child,
          if (unavailable)
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: SafeArea(
                bottom: false,
                child: Material(
                  key: const ValueKey('api-unavailable-banner'),
                  color: colors.surfaceContainerHigh,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.wifi_off_rounded, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text(
                              'الاتصال غير متاح. تجري إعادة الاتصال تلقائياً.',
                              style: TextStyle(fontSize: 12))),
                      TextButton(
                          key: const ValueKey('connection-retry-button'),
                          onPressed: checking
                              ? null
                              : () => unawaited(connection.retryConnection()),
                          child: Text(
                              checking ? 'جارٍ الاتصال…' : 'إعادة المحاولة')),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      });
}

/// Retained for app wiring; availability no longer locks navigation or focus.
class ApiAvailabilityNavigatorObserver extends NavigatorObserver {
  ApiAvailabilityNavigatorObserver(StartupConnectionService connection);
  void dispose() {}
}
