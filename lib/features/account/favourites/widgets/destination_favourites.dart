import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../ride/location_selection/controllers/location_selection_controller.dart';
import '../../../ride/models/ride_models.dart';
import '../../account_routes.dart';
import '../controllers/favourites_controller.dart';
import '../models/favourites_models.dart';
import '../models/saved_place_labels.dart';

class RouteFavouritesButton extends GetView<LocationController> {
  const RouteFavouritesButton({super.key});
  @override
  Widget build(BuildContext context) => Obx(() => IconButton(
      key: const ValueKey('route-favourites-picker'),
      tooltip: 'اختيار من المفضلة',
      icon: const Icon(Icons.favorite_outline),
      onPressed: controller.focusedRouteField.value == null
          ? null
          : () async {
              final field = controller.focusedRouteField.value;
              if (field == null) return;
              FocusScope.of(context).unfocus();
              final result = await Get.toNamed<dynamic>(
                  AccountRoutes.favourites,
                  arguments: {'selectPlace': true});
              await controller.loadSavedPlaces();
              if (result is! FavouritePlace ||
                  !result.hasCoordinates ||
                  controller.isClosed) return;
              final place = result;
              await controller.selectPlace(
                  RecentPlace(
                      title: place.title,
                      address: place.address,
                      kind: place.kind,
                      latitude: place.latitude!,
                      longitude: place.longitude!),
                  field: field,
                  closeSearchPage: false);
            }));
}

class SaveDestinationButton extends GetView<LocationController> {
  const SaveDestinationButton({this.iconOnly = false, super.key});

  final bool iconOnly;

  Future<void> _save(BuildContext context) async {
    await controller.loadSavedPlaces();
    if (!context.mounted) return;
    await showDialog<bool>(
        context: context,
        builder: (_) => _SaveDestinationDialog(location: controller));
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final onPressed = controller.destination.value == null
            ? null
            : () => _save(context);
        const key = ValueKey('save-destination-favourite');
        const icon = Icon(Icons.favorite_border_rounded, size: 20);
        if (iconOnly) {
          return IconButton(
              key: key,
              tooltip: 'إضافة الوجهة إلى المفضلة',
              icon: icon,
              onPressed: onPressed);
        }
        return TextButton.icon(
            key: key,
            icon: icon,
            label: const Text('حفظ الوجهة'),
            onPressed: onPressed);
      });
}

class _SaveDestinationDialog extends StatefulWidget {
  const _SaveDestinationDialog({required this.location});
  final LocationController location;
  @override
  State<_SaveDestinationDialog> createState() => _SaveDestinationDialogState();
}

class _SaveDestinationDialogState extends State<_SaveDestinationDialog> {
  final name = TextEditingController();
  String kind = 'home';
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final label = savedPlaceKinds[kind] ?? name.text.trim();
    if (saving) return;
    if (kind != 'unnamed' && label.isEmpty) {
      setState(() => error = 'اكتب اسم المكان');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final ok = await widget.location
          .saveCurrentDestination(kind: kind, label: label);
      if (!ok) {
        if (mounted)
          setState(() => error =
              'تعذر حفظ الوجهة. تحقق من الاتصال وتسجيل الدخول ثم أعد المحاولة.');
        return;
      }
      if (Get.isRegistered<FavouritesController>())
        await Get.find<FavouritesController>().load();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر حفظ الوجهة. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: AlertDialog(
          title: const Text('إضافة الوجهة إلى المفضلة'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const Text(
                    'اختيار اسم محفوظ سابقاً يحدّث إحداثياته بهذه الوجهة.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'اسم الوجهة'),
                    isExpanded: true,
                    items: [
                      for (final entry in savedPlaceKinds.entries)
                        DropdownMenuItem(
                            value: entry.key,
                            child: Row(children: [
                              Icon(savedPlaceIcon(entry.key), size: 20),
                              const SizedBox(width: 8),
                              Text(entry.value)
                            ])),
                      const DropdownMenuItem(
                          value: 'unnamed', child: Text('بدون اسم')),
                      const DropdownMenuItem(
                          value: 'place', child: Text('كتابة اسم جديد'))
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                              kind = v!;
                              error = null;
                            })),
                if (kind == 'place') ...[
                  const SizedBox(height: 12),
                  TextField(
                      controller: name,
                      maxLength: 200,
                      decoration:
                          const InputDecoration(labelText: 'اسم المكان'),
                      enabled: !saving),
                  Wrap(spacing: 6, children: [
                    for (final place in widget.location.shortcutPlaces
                        .where((p) => !savedPlaceKinds.containsKey(p.kind)))
                      ActionChip(
                          label: Text(place.title),
                          onPressed:
                              saving ? null : () => name.text = place.title)
                  ])
                ],
                if (kind == 'unnamed')
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                          'تُحفظ الوجهة في المفضلة فقط، دون اختصار في شاشة المسار.')),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ])),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'جارٍ الحفظ…' : 'حفظ'))
          ]));
}

class FavouriteDestinationShortcuts extends GetView<LocationController> {
  const FavouriteDestinationShortcuts({super.key});
  @override
  Widget build(BuildContext context) =>
      Obx(() => Wrap(spacing: 8, runSpacing: 4, children: [
            for (final place in controller.shortcutPlaces)
              ActionChip(
                  avatar: Icon(savedPlaceIcon(place.kind), size: 19),
                  label: Text(place.title),
                  onPressed: () => controller.selectPlace(place,
                      field: 1, closeSearchPage: false)),
          ]));
}
