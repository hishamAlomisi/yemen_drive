class RideCancellationOptions {
  const RideCancellationOptions(this.stage, this.reasons,
      {this.showSearchViewers = false});

  final String stage;
  final List<String> reasons;
  final bool showSearchViewers;

  factory RideCancellationOptions.forRide(String status,
      {required bool hasOffers, bool paymentCompleted = false}) {
    final options = switch (status) {
      'DriverAssigned' ||
      '3' =>
        const RideCancellationOptions('تم اختيار السائق ولم تبدأ الرحلة بعد', [
          'السائق لم يبدأ التحرك إلى نقطة الانطلاق',
          'تعذر التواصل مع السائق',
          'أحتاج إلى تعديل وقت الرحلة',
          'الأجرة لا تناسبني',
          'لم أعد بحاجة إلى الرحلة',
          'سبب آخر',
        ]),
      'DriverEnRoute' ||
      '4' =>
        const RideCancellationOptions('السائق في الطريق إليك', [
          'تأخر السائق عن موعد الوصول المتوقع',
          'السائق يتجه بعيداً عن نقطة الانطلاق',
          'تعذر التواصل مع السائق',
          'نقطة الانطلاق غير مناسبة وأحتاج إلى تغييرها',
          'طرأ أمر عاجل ولم أعد أستطيع الانتظار',
          'سبب آخر',
        ]),
      'DriverArrived' ||
      '9' =>
        const RideCancellationOptions('وصل السائق ولم تبدأ الرحلة بعد', [
          'لم أتمكن من العثور على السيارة في نقطة الانطلاق',
          'السيارة أو السائق لا يطابقان البيانات المعروضة',
          'حالة السيارة غير مناسبة للرحلة',
          'لا أشعر بالأمان قبل بدء الرحلة',
          'طرأ أمر عاجل ولا أستطيع بدء الرحلة',
          'سبب آخر',
        ]),
      'InProgress' ||
      '5' =>
        const RideCancellationOptions('الرحلة جارية؛ اختر سبب طلب إيقافها', [
          'لا أشعر بالأمان أثناء الرحلة',
          'تصرف السائق غير مناسب',
          'السائق لا يتبع المسار المتفق عليه',
          'حدث عطل في السيارة',
          'طرأ ظرف صحي أو أمر عاجل',
          'أرغب في إنهاء الرحلة قبل الوصول إلى الوجهة',
          'سبب آخر',
        ]),
      'Completed' ||
      '6' ||
      'Cancelled' ||
      '7' =>
        const RideCancellationOptions('انتهت الرحلة ولا يمكن إلغاؤها', []),
      _ => RideCancellationOptions(
          hasOffers
              ? 'وصلت عروض ولم تبدأ الرحلة بعد'
              : 'لم يصلك عرض من سائق بعد',
          [
            if (!hasOffers) ...[
              'لم تصلني عروض من سائقين',
              'لا يوجد سائق متاح بالقرب مني',
              'طال انتظار العثور على سائق',
            ],
            hasOffers ? 'الأجرة المعروضة لا تناسبني' : 'الأجرة لا تناسبني',
            'طلبت الرحلة عن طريق الخطأ',
            'أحتاج إلى تعديل نقطة الانطلاق أو الوجهة',
            'تغيرت خطتي ولم أعد بحاجة إلى الرحلة',
            'سبب آخر',
          ],
          showSearchViewers: true,
        ),
    };
    if (!paymentCompleted &&
        const {
          'DriverAssigned',
          '3',
          'DriverEnRoute',
          '4',
          'DriverArrived',
          '9',
          'InProgress',
          '5'
        }.contains(status)) {
      return RideCancellationOptions(
          options.stage,
          [
            'لم أتمكن من الدفع عبر المحفظة',
            'لا يتوفر لدي رصيد كافٍ في محافظ الدفع',
            'تعذرت وسيلة الدفع ولا أستطيع إكمال الرحلة',
            ...options.reasons,
          ],
          showSearchViewers: options.showSearchViewers);
    }
    return options;
  }
}
