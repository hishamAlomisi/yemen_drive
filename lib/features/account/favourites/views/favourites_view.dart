import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_spacing.dart';
import '../../../../../shared/widgets/app_states.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../models/account_models.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/favourites_controller.dart';

class FavouritesPage extends GetView<FavouritesController> {
  const FavouritesPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'الأماكن المفضلة',
        showBack: false,
        bottomNavIndex: embedded ? null : 1,
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة مكان',
            onPressed: () => _openAddPlaceDialog(context),
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
        child: Obx(() {
          if (controller.isLoading.value) {
            return const SizedBox(height: 420, child: AppLoading());
          }
          if (controller.places.isEmpty) {
            return const SizedBox(
              height: 420,
              child: AppEmptyState(
                title: 'لا توجد أماكن محفوظة',
                message: 'احفظ وجهاتك المتكررة لتصل إليها بسرعة.',
                icon: Icons.favorite_border_rounded,
              ),
            );
          }
          return Column(
            children: controller.places
                .map(
                  (place) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _FavouritePlaceTile(
                      place: place,
                      onDelete: () async {
                        await controller.remove(place);
                        Get.snackbar('تم الحذف', 'أزيل المكان من المفضلة.');
                      },
                    ),
                  ),
                )
                .toList(growable: false),
          );
        }),
      );

  Future<void> _openAddPlaceDialog(BuildContext context) async {
    final label = TextEditingController();
    final address = TextEditingController();
    final latitude = TextEditingController();
    final longitude = TextEditingController();
    var kind = 'place';
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة مكان محفوظ'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppTextField(
                    controller: label,
                    label: 'اسم المكان *',
                    hint: 'المنزل أو العمل',
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'اكتب اسم المكان'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  AppTextField(
                    controller: address,
                    label: 'العنوان *',
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'اكتب العنوان'
                        : null,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: kind,
                    decoration: const InputDecoration(labelText: 'نوع المكان'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'home', child: Text('المنزل')),
                      DropdownMenuItem(value: 'work', child: Text('العمل')),
                      DropdownMenuItem(value: 'airport', child: Text('المطار')),
                      DropdownMenuItem(value: 'place', child: Text('مكان آخر')),
                    ],
                    onChanged: (value) =>
                        setState(() => kind = value ?? 'place'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppTextField(
                          controller: latitude,
                          label: 'خط العرض *',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          validator: (value) =>
                              double.tryParse(value ?? '') == null
                                  ? 'مطلوب'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppTextField(
                          controller: longitude,
                          label: 'خط الطول *',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          validator: (value) =>
                              double.tryParse(value ?? '') == null
                                  ? 'مطلوب'
                                  : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final ok = await controller.add(
                  label: label.text,
                  address: address.text,
                  kind: kind,
                  latitude: double.parse(latitude.text),
                  longitude: double.parse(longitude.text),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, ok);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    address.dispose();
    latitude.dispose();
    longitude.dispose();
    if (saved == true)
      Get.snackbar('تم الحفظ', 'أضيف المكان إلى الأماكن المفضلة.');
  }
}

class _FavouritePlaceTile extends StatelessWidget {
  const _FavouritePlaceTile({required this.place, required this.onDelete});

  final FavouritePlace place;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => AccountListTile(
        title: place.title,
        subtitle: place.address,
        icon: place.icon,
        onTap: () =>
            Get.snackbar(place.title, 'سيُستخدم هذا العنوان كوجهة للحجز.'),
        trailing: IconButton(
          tooltip: 'حذف',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      );
}
