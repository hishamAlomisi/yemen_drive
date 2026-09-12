# التعليقات المؤقتة

## TEMPORARY_ROUTE_BYPASS

- تم تعليق اشتراط نجاح Google Routes API مؤقتًا حتى يمكن تجربة الانتقال بين شاشات الرحلة.
- عند تفعيل التعليق، يكفي تحديد نقطة الانطلاق والوجهة للانتقال إلى الشاشة التالية، حتى لو فشل حساب المسار أو كانت `routePoints` فارغة.
- ما زال التطبيق يحاول طلب المسار ويعرضه عند نجاح الطلب.
- لإلغاء التعليق بعد انتهاء التجارب: اجعل `LocationController.temporaryRouteBypass` تساوي `false`، ثم أعد استخدام شرط `hasDrivingRoute` في زر الانتقال و `openAddressDetails()` و `confirmLocation()`.
