# عقد ASP.NET API المقترح لتطبيق يمن درايف

هذا العقد هو نقطة اتفاق بين Flutter وASP.NET. يمكن تغيير أسماء المسارات، لكن يجب الحفاظ على الدلالات، وأنواع البيانات، وأكواد الحالات، وشكل الأخطاء بشكل موحد.

ملاحظة التنفيذ الحالية: مشروع `api_control` يطبق حاليًا `POST /api/auth/login` و`POST /api/auth/register` ومسارات الرحلات والتسعير والمحفظة الموضحة في README الخاص به. مسارات OTP وإكمال التسجيل وتجديد الرموز الواردة أدناه ما زالت عقدًا مستهدفًا وليست Endpoints منفذة في الخادم الحالي.

## 1. الأساس والإصدارات

- Base URL للخادم الحالي: `https://<host>/api` (لا توجد بادئة `/v1` في تطبيق ASP.NET الحالي).
- JSON بترميز UTF-8 وأسماء خصائص `camelCase`.
- نوع المحتوى العادي: `application/json`.
- ترسل أجسام الطلبات والاستجابات مباشرة بصيغة JSON دون JWE أو `application/jose` أو أي غلاف تشفيري على مستوى التطبيق.
- نوع الخطأ: `application/problem+json`.
- جميع المعرفات ترسل كنصوص. يفضّل استخدام UUID/Guid غير قابل للتخمين.
- العملات تستخدم رمز ISO 4217 مثل `SAR`، والقيم المالية Decimal على الخادم وليست Float.
- القيم Enum ترسل كنصوص ثابتة مثل `pending` و`accepted`، لا كأرقام ترتيبية.

## 2. الوقت والتاريخ

- كل وقت صادر من الخادم يجب أن يكون UTC بصيغة ISO 8601 وينتهي بـ `Z`:

```json
{
  "createdAt": "2026-08-11T13:25:41.482Z"
}
```

- يحول Flutter الوقت إلى المنطقة المحلية عند العرض فقط.
- المدد ترسل بالثواني مثل `estimatedArrivalSeconds`، والمسافات بالمتر مثل `distanceMeters`.
- لا يرسل الخادم أوقاتًا محلية بلا Offset.

## 3. الرؤوس المشتركة

| Header | الاستخدام |
|---|---|
| `Authorization: Bearer <token>` | كل endpoint محمي |
| `Accept-Language: ar-SA` | لغة النصوص القادمة من الخادم |
| `X-Correlation-ID` | معرف تتبع؛ ينشئه الخادم إذا لم يرسله العميل |
| `Idempotency-Key` | الطلبات الحساسة القابلة لإعادة الإرسال |
| `If-Match` | تحديث مورد يدعم ETag والتزامن المتفائل |

يجب إعادة `X-Correlation-ID` في الاستجابة وإدراجه في السجلات وProblemDetails.

## 4. المصادقة والرموز

### إنشاء حساب وإرسال OTP

`POST /auth/sign-up/request-otp`

```json
{
  "phoneNumber": "+967771234567"
}
```

استجابة `202 Accepted`:

```json
{
  "destination": "+96777*****67",
  "expiresAt": "2026-08-11T13:35:00Z",
  "resendAfterSeconds": 60
}
```

### التحقق من OTP

`POST /auth/verify-otp`

```json
{
  "destination": "+967771234567",
  "code": "251904",
  "purpose": "signUp"
}
```

استجابة `200 OK`:

```json
{
  "verificationToken": "short-lived-one-time-token",
  "expiresAt": "2026-08-11T13:40:00Z"
}
```

قيم `purpose` المتوقعة: `signUp` و`passwordReset`.

### إكمال التسجيل

`POST /auth/sign-up/complete`

يرسل بيانات التسجيل والملف الشخصي وكلمة المرور و`verificationToken`. يجب أن يكون الرمز أحادي الاستخدام وقصير العمر.

```json
{
  "phoneNumber": "+967771234567",
  "fullName": "سارة أحمد",
  "gender": "female",
  "street": "شارع الزبيري",
  "city": "صنعاء",
  "district": "التحرير",
  "password": "Strong#123",
  "verificationToken": "short-lived-one-time-token"
}
```

استجابة `201 Created`:

```json
{
  "accessToken": "jwt-access-token",
  "refreshToken": "opaque-refresh-token",
  "accessTokenExpiresAt": "2026-08-11T13:40:00Z",
  "refreshTokenExpiresAt": "2026-09-10T13:25:00Z",
  "user": {
    "id": "3f46b02e-9c2f-46a3-865b-994d88103027",
    "fullName": "سارة أحمد"
  }
}
```

### تسجيل الدخول

`POST /auth/sign-in`

```json
{
  "phoneNumber": "+967771234567",
  "password": "Strong#123",
  "deviceId": "6c692a6b-6676-4abc-991f-69612d5325d8"
}
```

إذا كان الجهاز موثوقًا تحمل الاستجابة الرموز بالشكل السابق. وإذا كان جديدًا:

```json
{
  "requiresOtp": true,
  "challengeId": "bd1aeff6-3550-4b45-9b6f-ff664a26cacf",
  "destination": "+96777*****67",
  "expiresAt": "2026-08-23T12:05:00Z"
}
```

يستكمل التطبيق عبر `POST /auth/sign-in/verify-device`. قرار الثقة يصدر من الخادم، ولا يثق الخادم في boolean مرسل من التطبيق.

### تجديد الرمز

`POST /auth/refresh`

```json
{
  "refreshToken": "opaque-refresh-token"
}
```

- يطبق الخادم Refresh Token Rotation.
- عند نجاح التجديد يبطل الرمز القديم ويعيد access وrefresh جديدين.
- إعادة استخدام refresh token مبطل تلغي سلسلة الجلسة بالكامل.
- يفضل تخزين hash للـrefresh token على الخادم.

### استعادة كلمة المرور

- `POST /auth/password/request-reset`
- `POST /auth/verify-otp` بقيمة `purpose: passwordReset`
- `POST /auth/password/reset`

طلب إعادة التعيين:

```json
{
  "identity": "+967771234567",
  "channel": "sms"
}
```

طلب الحفظ:

```json
{
  "identity": "+967771234567",
  "newPassword": "NewStrong#456",
  "verificationToken": "short-lived-one-time-token"
}
```

لا تكشف استجابة طلب الاستعادة ما إذا كان الحساب موجودًا. استخدم رسالة عامة وزمن استجابة متقاربًا.

## 5. ProblemDetails والتحقق

تعاد الأخطاء وفق RFC 7807:

```json
{
  "type": "https://api.example.com/problems/validation",
  "title": "بيانات الطلب غير صحيحة",
  "status": 400,
  "detail": "راجع الحقول وحاول مرة أخرى.",
  "instance": "/api/auth/sign-up/complete",
  "code": "validation_error",
  "traceId": "00-f9c3...-01",
  "errors": {
    "email": ["البريد الإلكتروني مستخدم بالفعل."],
    "password": ["كلمة المرور لا تحقق المتطلبات."]
  }
}
```

الأكواد المتوقعة:

- `400`: تحقق أو طلب غير صالح.
- `401`: رمز مفقود أو منتهي أو بيانات دخول خاطئة.
- `403`: المستخدم معروف لكنه لا يملك الصلاحية.
- `404`: المورد غير موجود.
- `409`: تعارض حالة أو Idempotency-Key مستخدم مع payload مختلف.
- `422`: قاعدة عمل لم تتحقق، مثل رحلة لا يمكن إلغاؤها.
- `429`: تجاوز المعدل، مع `Retry-After`.
- `500`: خطأ داخلي دون كشف stack trace.

يجب أن تكون مفاتيح `errors` مطابقة لخصائص JSON لكي تربطها واجهة Flutter بالحقول مباشرة.

## 6. Pagination والفرز

الطلب:

`GET /rides?page=1&pageSize=20&sort=-createdAt&status=completed`

- `page` يبدأ من 1.
- القيمة الافتراضية لـ`pageSize` هي 20 والحد الأعلى 100.
- الشرطة السالبة في `sort` تعني ترتيبًا تنازليًا.
- يجب أن يكون الفرز مستقرًا؛ استخدم `id` كحقل فرز ثانوي عند تساوي القيم.

الاستجابة:

```json
{
  "items": [],
  "page": 1,
  "pageSize": 20,
  "totalCount": 137,
  "totalPages": 7,
  "hasNextPage": true
}
```

للتدفقات عالية التغيير مثل الرسائل يمكن إضافة Cursor Pagination بعقد منفصل، ولا تخلط cursor وpage في endpoint واحد.

## 7. Idempotency

يلزم `Idempotency-Key` في الأقل مع:

- `POST /rides`
- `POST /payments`
- `POST /wallet/top-ups`
- أي عملية قد تخصم مبلغًا أو تنشئ موردًا مدفوعًا.

القواعد:

1. ينشئ العميل UUID v4 جديدًا لكل عملية منطقية.
2. يحتفظ الخادم بالمفتاح وhash الطلب والاستجابة لمدة 24 ساعة على الأقل.
3. إعادة نفس المفتاح ونفس payload تعيد نفس status/body دون تكرار العملية.
4. نفس المفتاح مع payload مختلف يعيد `409 idempotency_conflict`.
5. لا يعاد استخدام المفتاح بعد نجاح العملية لعملية جديدة.

## 8. عقود الرحلة الأساسية

### عرض الأسعار

`POST /rides/quotes`

```json
{
  "pickup": {"latitude": 24.7136, "longitude": 46.6753},
  "destination": {"latitude": 24.7743, "longitude": 46.7386},
  "serviceType": "transport"
}
```

تعاد خيارات المركبات مع `quoteId` و`vehicleType` و`amount` و`currency` و`distanceMeters` و`estimatedArrivalSeconds` و`expiresAt`.

### إنشاء طلب رحلة

`POST /rides` مع `Idempotency-Key`؛ التفاصيل الكاملة في القسم 16:

```json
{
  "quoteId": "31b72d3b-832a-48db-a9d6-c7bf9587863c",
  "paymentMethodId": "cash",
  "customerOfferedPrice": 2500,
  "notes": "المدخل الشرقي"
}
```

### حالات الرحلة

القيم المقترحة:

`draft`, `searchingDriver`, `negotiating`, `driverAssigned`, `driverEnRoute`, `driverArrived`, `inProgress`, `completed`, `cancelled`.

انتقالات الحالة يجب أن يتحقق منها الخادم، ولا يثق في الحالة القادمة من تطبيق العميل.

Endpoints مقترحة:

- `GET /rides/{rideId}`
- `POST /rides/{rideId}/cancel`
- `POST /rides/{rideId}/review`
- `GET /rides` للسجل
- `GET /notifications`
- `POST /notifications/read-all`
- `GET /wallet`
- `POST /wallet/top-ups`
- `POST /payments`
- `GET /users/me`
- `PATCH /users/me`

## 9. SignalR

Hub الحالي: `/hubs/tracking`.

الاتصال:

- يرسل Flutter access token عبر `accessTokenFactory`.
- يتحقق الخادم من المستخدم.
- عند استدعاء `JoinRide` يضاف الاتصال إلى `ride:{rideId}` بعد التحقق من ملكية الرحلة.

أحداث الخادم إلى العميل:

```text
offerReceived
rideUpdated
locationUpdated
```

مثال موقع السائق:

```json
{
  "rideId": "f1790ed5-f42c-4bc0-9c09-f5df5aa59667",
  "driverId": "75fc0f74-8e6d-479e-a3e6-06154d4de420",
  "latitude": 24.7201,
  "longitude": 46.6819,
  "heading": 92.5,
  "recordedAt": "2026-08-11T13:28:10.220Z",
  "sequence": 148
}
```

يستخدم `sequence` لتجاهل الرسائل القديمة أو المكررة. بعد انقطاع وإعادة اتصال SignalR يجب طلب `GET /rides/{rideId}` لمزامنة الحالة؛ أحداث Hub ليست بديلًا عن مصدر REST النهائي.

## 10. التزامن والكاش

- يمكن إعادة `ETag` مع الملف الشخصي والمفضلة والإعدادات.
- يرسل العميل `If-Match` في PATCH/DELETE؛ التعارض يعيد `412 Precondition Failed`.
- استخدم `Cache-Control: no-store` للرموز وبيانات الدفع.
- يمكن استخدام ETag أو مدة قصيرة للبيانات العامة مثل العروض وأنواع المركبات.

## 11. الأمان والتشغيل

- HTTPS إلزامي خارج بيئة التطوير المحلية.
- لا يطبق النظام تشفيرًا إضافيًا على جسم HTTP: يرسل Flutter JSON عاديًا ويستقبل JSON عاديًا. تبقى حماية النقل عبر HTTPS/TLS، والمصادقة عبر JWT للمسارات المحمية.
- Rate limiting على تسجيل الدخول وOTP والاستعادة والدفع.
- لا تسجل كلمات المرور أو الرموز أو بيانات البطاقات أو نص OTP.
- تطبيق ASP.NET Data Protection بصورة مشتركة بين النسخ عند التشغيل المتعدد.
- مفاتيح التوقيع والأسرار في Secret Manager/Key Vault، لا في repository.
- التحقق من ملكية كل `rideId` و`paymentMethodId` على الخادم.
- Webhook الدفع يتحقق من التوقيع ويكون idempotent.
- سجلات منظمة تشمل `traceId` و`userId` و`rideId` دون بيانات حساسة.

## 12. قواعد التوافق

- التغييرات الإضافية غير الكاسرة مسموحة داخل v1؛ يجب أن يتجاهل العميل الخصائص غير المعروفة.
- حذف/إعادة تسمية خاصية أو تغيير نوعها يحتاج إصدار API جديدًا.
- لا تغير معنى Enum موجود. أضف قيمة جديدة فقط بعد تجهيز Flutter لقيمة fallback.
- وثق العقد عبر OpenAPI، وولّد اختبارات Contract في CI للتحقق من العينات السابقة.

## 13. حدود النظام والمعمارية

تقسم المنظومة إلى وحدات واضحة، ويمكن أن تبدأ كتطبيق واحد Modular Monolith مع إبقاء الحدود التالية مستقلة:

| الوحدة | المسؤولية |
|---|---|
| Identity | المستخدمون، الأدوار، OTP، الأجهزة والجلسات |
| Catalog | الخدمات وأنواع المركبات وطرق الدفع المتاحة |
| Pricing | السعر الافتراضي، الحدود، العروض والخصومات |
| Rides | مسودة الطلب، عروض السائقين، التعيين وحالات الرحلة |
| Drivers | ملف السائق والمركبة والتوفر والوثائق |
| Tracking | المواقع الحية، السائقون القريبون ومسار الرحلة |
| Wallets | أرصدة العميل والسائق وعمليات الحجز والتحرير |
| Payments | بوابة الدفع، webhooks، الاسترداد وtokenized cards |
| Accounting | القيود اليومية والحسابات والتسويات والعمولات |
| Promotions | الأكواد والعروض وقواعد الاستحقاق |
| Communications | المحادثة، الإشعارات ومشاركة الرحلة |
| Safety | جهات الطوارئ والتسجيلات وبلاغات السلامة |
| Administration | إعداد الاتصال والسياسات والتقارير وAudit Log |

قواعد ثابتة:

- Domain لا يعتمد على EF Core أو HTTP أو SignalR.
- Application يحتوي use cases والعقود ونتائج العمل، لا Controllers أو SQL.
- Infrastructure يطبق EF Core، تخزين الملفات، الدفع، الإشعارات والتشفير.
- API وAdmin يستهلكان Application؛ لا يكتبان قواعد عمل مكررة.
- الهوية تؤخذ من JWT، وليس من `customerId` أو `driverId` أو `actorId` داخل body. تحديد مستخدم آخر متاح فقط لمسار إداري وصلاحية موثقة.
- كل انتقال حالة وكل قيد مالي ينفذ في الخادم داخل transaction مناسبة.
- DTOs العامة لا تعرض Entities مباشرة.

## 14. النموذج الموحد المطلوب لتطبيق Flutter

توجد حاليًا نماذج رحلة متقاربة في Flutter داخل `features/ride/models` و`shared/models`. العقد النهائي يستخدم الأسماء التالية كمصدر واحد، ثم توحّد نماذج Flutter تدريجيًا حولها:

### GeoPointDto

```json
{
  "latitude": 15.3694,
  "longitude": 44.1910,
  "label": "موقعي الحالي",
  "address": "شارع الزبيري، صنعاء",
  "street": "شارع الزبيري",
  "details": "أمام البوابة الشرقية"
}
```

`latitude` و`longitude` إجباريان. بقية الحقول وصف المستخدم أو نتيجة reverse geocoding ولا يعتمد الخادم عليها للتحقق المكاني.

### DriverSummaryDto

```json
{
  "id": "75fc0f74-8e6d-479e-a3e6-06154d4de420",
  "name": "محمد علي",
  "phoneMasked": "+967 7** *** 123",
  "photoUrl": "https://cdn.example/driver/photo.jpg",
  "rating": 4.9,
  "completedTrips": 860,
  "vehicle": {
    "type": "car",
    "make": "Toyota",
    "model": "Yaris",
    "modelYear": 2021,
    "color": "white",
    "plateNumber": "1-12345"
  }
}
```

### MoneyDto

```json
{
  "amount": 2400.00,
  "currency": "YER"
}
```

كل العملات في API تستخدم ISO 4217؛ الرمز العربي للعرض فقط في Flutter.

## 15. الكتالوج والخدمات

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/catalog/services` | نقل، توصيل، تأجير، مجدول وغيرها |
| GET | `/catalog/vehicle-types?serviceType=transport` | المركبات والصور والوصف والسعة |
| GET | `/catalog/payment-methods` | الطرق المتاحة حسب البلد والمستخدم |
| GET | `/catalog/cancellation-reasons?actor=customer` | أسباب الإلغاء القابلة للترجمة |

هذه الموارد هي التي تغذي `RideServiceType`, `RideVehicle` وطرق الدفع في Flutter. القيم التجريبية لا تبقى hard-coded عند الربط الحقيقي.

## 16. التسعير وإنشاء طلب الرحلة

### 16.1 طلب السعر

`POST /rides/quotes`

```json
{
  "pickup": {
    "latitude": 15.3694,
    "longitude": 44.1910,
    "address": "صنعاء"
  },
  "destination": {
    "latitude": 15.3547,
    "longitude": 44.2067,
    "label": "المطار",
    "address": "مطار صنعاء الدولي"
  },
  "serviceType": "transport",
  "vehicleType": "car",
  "route": {
    "distanceMeters": 8200,
    "durationSeconds": 1080,
    "provider": "googleRoutes"
  },
  "promotionCode": "YME15"
}
```

استجابة `200 OK`:

```json
{
  "quoteId": "31b72d3b-832a-48db-a9d6-c7bf9587863c",
  "suggestedPrice": 2400.00,
  "minimumPrice": 1800.00,
  "maximumPrice": 4300.00,
  "priceStep": 100.00,
  "discount": 300.00,
  "currency": "YER",
  "distanceMeters": 8200,
  "durationSeconds": 1080,
  "expiresAt": "2026-08-23T12:05:00Z"
}
```

الخادم يعيد حساب السعر والمسافة عند إنشاء الطلب ولا يثق في سعر أو مسافة Flutter.

### 16.2 إنشاء طلب والبحث عن سائقين

`POST /rides` مع `Idempotency-Key`:

```json
{
  "quoteId": "31b72d3b-832a-48db-a9d6-c7bf9587863c",
  "pickup": {
    "latitude": 15.3694,
    "longitude": 44.1910,
    "label": "موقعي الحالي",
    "address": "شارع الزبيري"
  },
  "destination": {
    "latitude": 15.3547,
    "longitude": 44.2067,
    "label": "المطار",
    "address": "مطار صنعاء الدولي",
    "street": "طريق المطار",
    "details": "البوابة الرئيسية"
  },
  "serviceType": "transport",
  "vehicleType": "car",
  "customerOfferedPrice": 2500.00,
  "currency": "YER",
  "paymentMethodId": "cash",
  "scheduledAt": null,
  "notes": "اتصل عند الوصول"
}
```

لا يحفظ Flutter العنوان باستدعاء مستقل أثناء الخطوات. ينتقل `RideRequestDraft` محليًا بين الشاشات، ثم ترسل بيانات الرحلة والعناوين مرة واحدة هنا.

استجابة `201 Created`:

```json
{
  "id": "f1790ed5-f42c-4bc0-9c09-f5df5aa59667",
  "status": "searchingDriver",
  "quote": {
    "serverPrice": 2400.00,
    "customerOfferedPrice": 2500.00,
    "currency": "YER"
  },
  "createdAt": "2026-08-23T12:00:00Z"
}
```

## 17. عروض السائقين والتفاوض

### تطبيق العميل

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/rides/{id}` | مزامنة الطلب بعد إعادة الاتصال |
| GET | `/rides/{id}/offers` | snapshot للعروض |
| POST | `/rides/{id}/offers/{offerId}/accept` | قبول عرض، idempotent |
| POST | `/rides/{id}/offers/{offerId}/reject` | رفض يدوي |
| POST | `/rides/{id}/search/retry` | إعادة البحث |
| POST | `/rides/{id}/cancel` | إلغاء البحث أو الرحلة وفق الحالة |

### تطبيق السائق

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/driver/ride-opportunities?cursor=...` | الطلبات المتاحة القريبة |
| POST | `/driver/ride-opportunities/{rideRequestId}/offers` | تقديم عرض صالح لمدة محددة |
| DELETE | `/driver/ride-opportunities/{rideRequestId}/offers/{offerId}` | سحب عرض قبل قبوله |
| POST | `/driver/rides/{rideId}/acknowledge` | تأكيد استلام تعيين الرحلة |

طلب تقديم العرض لا يحتوي `driverId`؛ يؤخذ من JWT:

```json
{
  "amount": 2600.00,
  "currency": "YER",
  "validForSeconds": 20,
  "note": "أصل خلال 4 دقائق"
}
```

قبول العرض ينفذ transaction واحدة تتأكد أن الطلب ما زال قابلًا للقبول، تحول العرض إلى `accepted`، ترفض/تنهي بقية العروض، وتربط السائق بالرحلة. المنافس الذي خسر يعيد له `409 offer_no_longer_available`.

## 18. حالات الرحلة والانتقالات

القيم الموحدة:

```text
draft
searchingDriver
negotiating
driverAssigned
driverEnRoute
driverArrived
inProgress
completed
cancelled
```

الانتقالات الأساسية:

```text
draft -> searchingDriver -> negotiating -> driverAssigned
driverAssigned -> driverEnRoute -> driverArrived -> inProgress -> completed
أي حالة مسموح منها -> cancelled وفق سياسة الإلغاء
```

Endpoints السائق:

| Method | Path | الحالة الناتجة |
|---|---|---|
| POST | `/driver/rides/{id}/start-heading` | `driverEnRoute` |
| POST | `/driver/rides/{id}/arrive` | `driverArrived` |
| POST | `/driver/rides/{id}/start` | `inProgress` |
| POST | `/driver/rides/{id}/complete` | `completed` |
| POST | `/driver/rides/{id}/cancel` | `cancelled` إذا سمحت السياسة |

Endpoints العميل المشتركة:

- `GET /rides/{id}`
- `GET /rides?status=completed&page=1&pageSize=20`
- `POST /rides/{id}/cancel`
- `POST /rides/{id}/review`
- `POST /rides/{id}/share-links`

يجب أن تتضمن كل استجابة `version` رقميًا للتزامن المتفائل، أو يعاد `ETag` ويطلب `If-Match` لعمليات الحالة الحساسة.

## 19. السائق والمركبة والتوفر

| Method | Path | الاستخدام |
|---|---|---|
| GET/PATCH | `/driver/me` | الملف، بيانات الحساب وسياسة العمولة الفعالة |
| GET/PUT | `/driver/me/vehicle` | المركبة واللوحة والصور |
| GET/POST | `/driver/me/documents` | الرخص والهوية ووثائق المركبة |
| PUT | `/driver/me/availability` | `offline`, `available`, `busy` |
| GET | `/driver/me/earnings/summary` | يومي/أسبوعي وإجمالي مستحق |
| GET | `/driver/me/settlements` | كشوف التسوية والتحويلات |
| POST | `/driver/me/payout-accounts` | حساب دفع tokenized/مشفر |

سياسة العمولة الفعالة مرتبة بالأولوية:

1. سياسة خاصة بالسائق.
2. سياسة مجموعة/مدينة/نوع مركبة.
3. السياسة العامة.

عند إنشاء/قبول الرحلة يحفظ الخادم **لقطة غير قابلة للتغيير** تشمل `commissionPolicyId`, `calculationType`, `rate/fixedAmount`, الضرائب والحدود. تغيير إعداد السائق لاحقًا لا يغير رحلة سابقة.

## 20. السائقون القريبون والتتبع

### السائقون القريبون

`GET /drivers/nearby?latitude=15.3694&longitude=44.1910&radiusMeters=3000&vehicleType=car`

تعاد بيانات آمنة للعرض على الخريطة فقط. قبل قبول الرحلة لا يعاد رقم اللوحة الكامل أو الهاتف أو موقع بالغ الدقة أكثر من الحاجة.

### إرسال موقع السائق

`POST /driver/location-updates`

```json
{
  "rideId": "f1790ed5-f42c-4bc0-9c09-f5df5aa59667",
  "latitude": 15.3701,
  "longitude": 44.1922,
  "heading": 92.5,
  "speedMetersPerSecond": 8.4,
  "accuracyMeters": 6.2,
  "sequence": 148,
  "recordedAt": "2026-08-23T12:01:10.220Z"
}
```

هوية الفاعل تؤخذ من JWT. يرفض الخادم update لرحلة غير مرتبطة بالسائق. يمكن استخدام batch عند استعادة الشبكة:

`POST /driver/location-updates/batch` بحد أقصى معلن.

Endpoints القراءة:

- `GET /rides/{rideId}/tracking` لأحدث snapshot.
- `GET /rides/{rideId}/route` للمسار الحالي.

لا تحفظ جميع نقاط الموقع إلى الأبد. تعتمد hot store لآخر موقع، history مقيدة بالرحلة وسياسة retention، ثم تحذف أو تجمع البيانات بعد المدة القانونية.

## 21. SignalR والأحداث الكاملة

Hub موحد: `/hubs/tracking`.

أحداث الخادم إلى العميل:

```text
RideRequestSearching
RideRequestPresentedToDriver
DriverOfferReceived
DriverOfferWithdrawn
DriverOfferExpired
OfferAccepted
RideStatusChanged
DriverLocationUpdated
PassengerLocationUpdated
ChatMessageReceived
NotificationReceived
PaymentStatusChanged
SafetyAlertUpdated
```

أحداث الخادم إلى السائق:

```text
RideOpportunityReceived
RideOpportunityExpired
OfferAccepted
OfferRejected
RideCancelled
PassengerLocationUpdated
ChatMessageReceived
```

كل حدث يحمل:

```json
{
  "eventId": "a3895df8-9227-4a71-8bf3-df0677e43c0f",
  "eventType": "RideStatusChanged",
  "rideId": "f1790ed5-f42c-4bc0-9c09-f5df5aa59667",
  "sequence": 149,
  "occurredAt": "2026-08-23T12:01:12Z",
  "data": {}
}
```

بعد reconnect يطلب التطبيق snapshot عبر REST ثم يستأنف الأحداث الأحدث من `sequence`. لا تعتمد صحة الحالة على وصول حدث واحد.

## 22. المحفظة والدفع

### واجهات المحفظة

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/wallets/me` | الرصيد المتاح والمحجوز |
| GET | `/wallets/me/transactions?page=1&pageSize=20` | حركة المحفظة |
| POST | `/wallets/me/top-ups` | بدء شحن، مع Idempotency-Key |
| POST | `/wallets/me/withdrawals` | طلب سحب للسائق عند السماح |
| GET | `/payment-methods` | البطاقات/الطرق المحفوظة tokenized |
| POST | `/payment-methods/setup-sessions` | بدء حفظ بطاقة لدى المزود |
| DELETE | `/payment-methods/{id}` | إزالة token من حساب المستخدم |
| POST | `/payments` | دفع رحلة أو شحن |
| POST | `/payments/{id}/refunds` | إداري/سياسة الاسترداد |
| POST | `/payments/webhooks/{provider}` | webhook موقع من مزود الدفع |

لا يعدل `Wallet.Balance` مباشرة من Controller. ينشئ Application use case عملية ledger وwallet transaction معًا ويحدث الرصيد داخل transaction. كل خصم يمر بحالة `hold` ثم `capture` أو `release` عند الحاجة.

### مثال توزيع رحلة مكتملة

قيمة الرحلة: 2,500 YER، عمولة المنصة: 20%، حصة السائق: 2,000، حصة المنصة: 500.

```text
Debit   Customer wallet / Cash clearing       2,500
Credit  Driver payable                         2,000
Credit  Platform commission revenue              500
```

يجب أن يساوي مجموع debit مجموع credit لكل `JournalEntry`. لا تحذف القيود المنشورة؛ التصحيح بقيد عكسي. العملة جزء من الحساب والقيد، ولا تجمع أرصدة عملات مختلفة.

## 23. التسويات والعمولات والمحاسبة الإدارية

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/admin/accounting/accounts` | دليل الحسابات |
| GET | `/admin/accounting/journal-entries` | القيود مع filters |
| POST | `/admin/accounting/journal-entries` | قيد يدوي بموافقة وصلاحية |
| POST | `/admin/accounting/journal-entries/{id}/post` | ترحيل غير قابل للتعديل |
| POST | `/admin/accounting/journal-entries/{id}/reverse` | عكس القيد |
| GET | `/admin/drivers/{id}/ledger` | كشف حساب السائق |
| GET/POST | `/admin/driver-commission-policies` | سياسات النسبة/المبلغ الثابت |
| GET/POST | `/admin/driver-settlements` | توليد التسويات |
| POST | `/admin/driver-settlements/{id}/approve` | موافقة منفصلة |
| POST | `/admin/driver-settlements/{id}/pay` | تنفيذ الدفع وتسجيل المرجع |
| GET | `/admin/accounting/trial-balance` | ميزان المراجعة |

الحالات المالية تحتاج maker-checker للصلاحيات الحساسة: من ينشئ التسوية لا يعتمدها وحده في الإنتاج.

## 24. الخصومات والعروض والإحالات

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/promotions/available` | عروض المستخدم الحالية |
| POST | `/promotions/validate` | تحقق قبل التسعير |
| POST | `/referrals/redeem` | استخدام رمز إحالة idempotent |
| GET/POST/PATCH | `/admin/promotions` | إدارة العروض |

يحفظ تطبيق العميل `promotionId/code` فقط؛ الخادم يقرر الأهلية، الحد الأقصى، عدد الاستخدامات، المدينة، الخدمة، المركبة، المستخدم الجديد ووقت العرض. يطبق الخصم داخل quote ويثبت snapshot في الرحلة.

## 25. المحادثة والإشعارات والتواصل

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/rides/{rideId}/messages?cursor=...` | سجل المحادثة |
| POST | `/rides/{rideId}/messages` | رسالة نصية/نوع مدعوم |
| POST | `/rides/{rideId}/messages/{id}/read` | إيصال قراءة |
| GET | `/notifications?page=1&pageSize=20` | قائمة الإشعارات |
| POST | `/notifications/{id}/read` | مقروء |
| POST | `/notifications/read-all` | الكل مقروء |
| POST | `/devices/push-tokens` | FCM/APNs token لكل جهاز |
| DELETE | `/devices/push-tokens/{id}` | تسجيل الخروج/إبطال الجهاز |
| POST | `/rides/{rideId}/contact-sessions` | جلسة اتصال masked/VoIP إن توفرت |

لا يعرض رقم السائق أو العميل الخام إن أمكن استخدام اتصال وسيط. محتوى المحادثة يقتصر على طرفي الرحلة والدعم المخول، مع retention وAudit واضحين.

## 26. السلامة والطوارئ والتسجيل الصوتي

| Method | Path | الاستخدام |
|---|---|---|
| GET/POST/PATCH/DELETE | `/safety/emergency-contacts` | جهات الطوارئ |
| POST | `/rides/{rideId}/share-links` | رابط محدود العمر قابل للإبطال |
| POST | `/rides/{rideId}/safety-alerts` | SOS/بلاغ سلامة |
| PATCH | `/rides/{rideId}/safety-alerts/{id}` | تحديث/إغلاق وفق الدور |
| POST | `/rides/{rideId}/safety/recordings` | بدء metadata للتسجيل والرفع |
| POST | `/rides/{rideId}/safety/recordings/{id}/chunks` | تسجيل chunk metadata بعد رفعه |
| POST | `/rides/{rideId}/safety/recordings/{id}/complete` | إنهاء التسجيل |
| GET | `/rides/{rideId}/safety/recordings/{id}` | metadata لصلاحية محددة فقط |

لا تحفظ ملفات الصوت كـ`varbinary(max)` في SQL Server؛ تستخدم Object Storage وروابط قصيرة العمر وصلاحيات دقيقة. بيانات التحكم والـmetadata ترسل JSON عاديًا عبر HTTPS.

## 27. إعداد اتصال قاعدة البيانات في لوحة التحكم

مسارات Bootstrap محمية بسياسة `DatabaseConfigurationAdmin`، ومقيدة بالشبكة الداخلية أو setup token عند أول تشغيل:

| Method | Path | الاستخدام |
|---|---|---|
| GET | `/admin/system/database-connection` | يعيد الإعداد دون كلمة المرور |
| POST | `/admin/system/database-connection/test` | اختبار دون حفظ |
| PUT | `/admin/system/database-connection` | حفظ مشفر ثم إعادة تحميل مزود الاتصال |
| GET | `/admin/system/database-connection/providers` | الأنواع المدعومة |

طلب الحفظ:

```json
{
  "provider": "sqlServer",
  "server": ".\\sql2019",
  "databaseName": "YemenDrive",
  "username": "sa",
  "password": "<sent-only-when-changing>",
  "encryptConnection": true,
  "trustServerCertificate": true
}
```

الاستجابة:

```json
{
  "provider": "sqlServer",
  "server": ".\\sql2019",
  "databaseName": "YemenDrive",
  "username": "sa",
  "hasPassword": true,
  "encryptConnection": true,
  "trustServerCertificate": true,
  "lastTestSucceeded": true,
  "updatedAt": "2026-08-23T12:00:00Z"
}
```

الإعداد لا يمكن أن يعتمد على جدول داخل قاعدة البيانات المستهدفة قبل إنشاء الاتصال. يخزن كـbootstrap secret محمي بـASP.NET Core Data Protection/DPAPI أو Secret Store، ويستخدمه كل من API وAdmin من خدمة مشتركة. لا تعاد كلمة المرور ولا connection string إلى المتصفح.

تنبيه تشغيل: يستخدم التطوير المحلي instance باسم `sql2019`. حساب `sa` وكلمة المرور البسيطة للتطوير المحلي فقط، ويستخدم الإنتاج حسابًا محدود الصلاحيات وكلمة مرور قوية. يجب عدم وضع كلمة مرور قاعدة البيانات في ملفات الإعدادات المنشورة.

بعد الحفظ الناجح يجب أن ينشئ كل من API وAdmin أي `DbContext` جديد من مزود الاتصال المشترك. لا يحتفظ أي `DbContext` singleton باتصال قديم. إن كان تبديل الاتصال أثناء التشغيل غير آمن في البيئة المنشورة، تعيد الاستجابة `restartRequired: true` وتعرض اللوحة ذلك بوضوح بدل الادعاء أن كل الطلبات تحولت فورًا.

## 28. Endpoints لوحة التحكم

إضافة إلى المحاسبة وإعداد الاتصال:

- `/admin/dashboard/summary`
- `/admin/users`, `/admin/customers`, `/admin/drivers`
- `/admin/drivers/{id}/approve`, `/suspend`, `/documents`
- `/admin/rides` و`/admin/rides/{id}/timeline`
- `/admin/pricing-rules`
- `/admin/services`, `/admin/vehicle-types`
- `/admin/payments`, `/admin/refunds`
- `/admin/promotions`
- `/admin/notifications/broadcasts`
- `/admin/safety-alerts`
- `/admin/audit-logs`
- `/admin/system/health`

كل تعديل إداري يسجل: الفاعل، الوقت، المورد، القيم المتغيرة بعد حجب الأسرار، IP، correlationId والنتيجة.

## 29. أكواد العمل التي يحتاجها Flutter

لا يعرض Flutter رسائل Google أو SQL أو stack traces. يعتمد على `code` ويترجم رسالة بسيطة:

| code | الرسالة المقترحة للمستخدم |
|---|---|
| `network_error` | لا يوجد اتصال بالإنترنت. |
| `route_unavailable` | تعذر حساب مسار الرحلة حاليًا. |
| `quote_expired` | انتهت صلاحية السعر، جارٍ تحديثه. |
| `no_drivers_available` | لا يوجد سائق متاح حاليًا، حاول مجددًا. |
| `offer_no_longer_available` | لم يعد هذا العرض متاحًا. |
| `ride_state_conflict` | تغيرت حالة الرحلة، تم تحديث البيانات. |
| `insufficient_wallet_balance` | رصيد المحفظة غير كافٍ. |
| `payment_failed` | تعذر إتمام الدفع، جرّب طريقة أخرى. |
| `promotion_not_applicable` | هذا العرض لا ينطبق على الرحلة. |
| `location_permission_required` | يلزم السماح بالوصول إلى الموقع للمتابعة. |

يحفظ الخادم التفاصيل التقنية في logs مع `traceId` فقط.

## 30. أولوية التنفيذ

### المرحلة 1: الرحلة الطرفية الكاملة

1. Identity/JWT والأدوار.
2. الكتالوج والتسعير.
3. إنشاء الطلب وعروض السائق وقبول العرض.
4. حالات الرحلة وSignalR snapshots/reconnect.
5. تطبيق سائق أدنى يرسل العرض والموقع وينهي الرحلة.

### المرحلة 2: المال

1. Wallet holds/capture/release.
2. قيود مزدوجة وحسابات السائق والمنصة.
3. لقطة العمولة والتسويات.
4. مزود دفع tokenized وwebhooks وrefunds.
5. العروض والإحالات.

### المرحلة 3: الأمان والتشغيل

1. إشعارات push والمحادثة.
2. مشاركة الرحلة وSOS وجهات الطوارئ.
3. التسجيل الصوتي المشفر وObject Storage.
4. التقارير وAudit Log والمراقبة والنسخ الاحتياطي.
5. اختبارات عقد وتكامل وحمل واختبارات انتقال الحالة والقيود المالية.
