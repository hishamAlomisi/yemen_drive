import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/ride_controller.dart';

Future<void> showRideOptions(BuildContext context) async {
  final ride = Get.find<RideController>();
  if (ride.bookingLocked) return;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const RideOptionsSheet());
}

class RideOptionsSheet extends StatefulWidget {
  const RideOptionsSheet({super.key});
  @override
  State<RideOptionsSheet> createState() => _RideOptionsSheetState();
}

class _RideOptionsSheetState extends State<RideOptionsSheet> {
  final ride = Get.find<RideController>();
  late final TextEditingController notes =
      TextEditingController(text: ride.passengerNotes.value);

  @override
  Widget build(BuildContext context) => SafeArea(
          child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('خيارات الركوب',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              const SizedBox(height: 12),
              Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('أكثر من 4 ركاب'),
                  value: ride.moreThanFourPassengers.value,
                  onChanged: ride.bookingLocked
                      ? null
                      : (value) => ride.moreThanFourPassengers.value = value)),
              const SizedBox(height: 12),
              TextField(
                  controller: notes,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      hintText: 'التعليقات والملاحظات الإضافية'),
                  onChanged: (value) {
                    if (!ride.bookingLocked) ride.passengerNotes.value = value;
                  }),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Padding(
                      padding: EdgeInsets.all(12), child: Text('إغلاق'))),
            ]),
      ));

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }
}
