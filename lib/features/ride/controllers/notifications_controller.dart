import 'package:get/get.dart';

import '../../../core/config/app_environment.dart';
import '../models/ride_models.dart';

class NotificationsController extends GetxController {
  final RxList<RideNotificationItem> items = <RideNotificationItem>[
    const RideNotificationItem(
      id: '1',
      title: 'السائق في طريقه إليك',
      body: 'سيصل محمد خلال 3 دقائق. يمكنك متابعته على الخريطة.',
      timeLabel: 'منذ دقيقتين',
      kind: 'ride',
    ),
    const RideNotificationItem(
      id: '2',
      title: 'خصم 20٪ على رحلتك القادمة',
      body: 'استخدم الرمز YME20 قبل نهاية اليوم.',
      timeLabel: 'منذ ساعة',
      kind: 'offer',
    ),
    RideNotificationItem(
      id: '3',
      title: 'تمت إضافة المبلغ إلى محفظتك',
      body:
          'تمت إعادة 12 ${AppEnvironment.defaultCurrency} إلى رصيد المحفظة بنجاح.',
      timeLabel: 'أمس',
      kind: 'wallet',
      isRead: true,
    ),
  ].obs;

  void markAllRead() {
    final updated = items
        .map((item) => item.copyWith(isRead: true))
        .toList(growable: false);
    items.assignAll(updated);
  }
}
