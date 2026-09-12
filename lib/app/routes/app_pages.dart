import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../features/account/account_routes.dart';
import '../../features/auth/routes/auth_routes.dart';
import '../../features/ride/ride_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

abstract final class AppRoutes {
  static const String gallery = '/debug/gallery';
  static const String legacyLogin = '/login';
}

abstract final class AppPages {
  static List<GetPage<dynamic>> get pages => appPages;
}

List<GetPage<dynamic>> get appPages => <GetPage<dynamic>>[
      ...authPages,
      ...ridePages,
      ...accountPages,
      GetPage<dynamic>(
        name: AppRoutes.gallery,
        page: FeatureGalleryPage.new,
        transition: Transition.fadeIn,
      ),
      GetPage<dynamic>(
        name: AppRoutes.legacyLogin,
        page: () => const _LegacyRouteRedirect(target: AuthRoutes.signIn),
        transition: Transition.noTransition,
      ),
    ];

class _LegacyRouteRedirect extends StatefulWidget {
  const _LegacyRouteRedirect({required this.target});

  final String target;

  @override
  State<_LegacyRouteRedirect> createState() => _LegacyRouteRedirectState();
}

class _LegacyRouteRedirectState extends State<_LegacyRouteRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Get.offAllNamed<void>(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
}

class FeatureGalleryPage extends StatelessWidget {
  const FeatureGalleryPage({super.key});

  static const List<_GallerySection> _sections = <_GallerySection>[
    _GallerySection(
      title: 'المصادقة والبدء',
      icon: Icons.login_rounded,
      items: <_GalleryItem>[
        _GalleryItem('شاشة البداية', AuthRoutes.splash),
        _GalleryItem('التعريف 1', AuthRoutes.onboardingOne),
        _GalleryItem('التعريف 2', AuthRoutes.onboardingTwo),
        _GalleryItem('التعريف 3', AuthRoutes.onboardingThree),
        _GalleryItem('إذن الموقع', AuthRoutes.enableLocation),
        _GalleryItem('الترحيب', AuthRoutes.welcome),
        _GalleryItem('إنشاء حساب', AuthRoutes.signUp),
        _GalleryItem('رمز التسجيل', AuthRoutes.verifySignUpOtp),
        _GalleryItem('رمز التسجيل - معاينة', AuthRoutes.verifySignUpOtpFilled),
        _GalleryItem('إنشاء كلمة المرور', AuthRoutes.setPassword),
        _GalleryItem('إكمال الملف', AuthRoutes.completeProfile),
        _GalleryItem('تسجيل الدخول', AuthRoutes.signIn),
        _GalleryItem('بيانات الاستعادة', AuthRoutes.recoveryIdentity),
        _GalleryItem('طريقة الاستعادة', AuthRoutes.forgotPasswordMethod),
        _GalleryItem('رمز الاستعادة', AuthRoutes.verifyResetOtp),
        _GalleryItem('رمز الاستعادة - معاينة', AuthRoutes.verifyResetOtpFilled),
        _GalleryItem('كلمة مرور جديدة', AuthRoutes.setNewPassword),
      ],
    ),
    _GallerySection(
      title: 'الحجز والرحلة',
      icon: Icons.local_taxi_rounded,
      items: <_GalleryItem>[
        _GalleryItem('الرئيسية - نقل', RideRoutes.homeTransport),
        _GalleryItem('الرئيسية - توصيل', RideRoutes.homeDelivery),
        _GalleryItem('الإشعارات', RideRoutes.notifications),
        _GalleryItem('اختيار الموقع', RideRoutes.locationPicker),
        _GalleryItem('البحث عن موقع', RideRoutes.locationSearch),
        _GalleryItem('بيانات عنوان الوجهة', RideRoutes.locationAddress),
        _GalleryItem('تأكيد الموقع', RideRoutes.locationConfirm),
        _GalleryItem('وسيلة النقل', RideRoutes.transportSelection),
        _GalleryItem('المركبات القريبة', RideRoutes.vehicleCatalog),
        _GalleryItem('قائمة المركبات', RideRoutes.vehicleList),
        _GalleryItem('تفاصيل المركبة', RideRoutes.vehicleDetails),
        _GalleryItem('طلب رحلة', RideRoutes.rideRequest),
        _GalleryItem('إلغاء الطلب', RideRoutes.rideCancel),
        _GalleryItem('شكر الإلغاء', RideRoutes.requestThanks),
        _GalleryItem('موقع السائق', RideRoutes.driverLocation),
        _GalleryItem('المحادثة', RideRoutes.chat),
        _GalleryItem('الاتصال', RideRoutes.call),
        _GalleryItem('مكالمة جارية', RideRoutes.activeCall),
        _GalleryItem('الدفع', RideRoutes.payment),
        _GalleryItem('رحلة جارية', RideRoutes.activeRide),
        _GalleryItem('التقييم', RideRoutes.review),
        _GalleryItem('شكر الرحلة', RideRoutes.rideThanks),
      ],
    ),
    _GallerySection(
      title: 'الحساب والخدمات',
      icon: Icons.person_rounded,
      items: <_GalleryItem>[
        _GalleryItem('المفضلة', AccountRoutes.favourites),
        _GalleryItem('المحفظة', AccountRoutes.wallet),
        _GalleryItem('إضافة مبلغ', AccountRoutes.addAmount),
        _GalleryItem('حساب بنكي', AccountRoutes.bank),
        _GalleryItem('نجاح المحفظة', AccountRoutes.walletSuccess),
        _GalleryItem('العروض', AccountRoutes.offers),
        _GalleryItem('تفاصيل العرض', AccountRoutes.offerDetails),
        _GalleryItem('الملف الشخصي', AccountRoutes.profile),
        _GalleryItem('القائمة الجانبية', AccountRoutes.menu),
        _GalleryItem('رحلات قادمة', AccountRoutes.historyUpcoming),
        _GalleryItem('رحلات مكتملة', AccountRoutes.historyCompleted),
        _GalleryItem('رحلات ملغاة', AccountRoutes.historyCancelled),
        _GalleryItem('شكوى', AccountRoutes.complaint),
        _GalleryItem('نجاح الشكوى', AccountRoutes.complaintSuccess),
        _GalleryItem('الإحالة', AccountRoutes.referral),
        _GalleryItem('عن التطبيق', AccountRoutes.about),
        _GalleryItem('الإعدادات', AccountRoutes.settings),
        _GalleryItem('تغيير كلمة المرور', AccountRoutes.changePassword),
        _GalleryItem('اللغة', AccountRoutes.language),
        _GalleryItem('الخصوصية', AccountRoutes.privacy),
        _GalleryItem('التواصل', AccountRoutes.contact),
        _GalleryItem('حذف الحساب', AccountRoutes.deleteAccount),
        _GalleryItem('المساعدة', AccountRoutes.help),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('معرض شاشات يمن درايف'),
            actions: <Widget>[
              IconButton(
                onPressed: () =>
                    Get.offAllNamed<void>(RideRoutes.homeTransport),
                tooltip: 'الرئيسية',
                icon: const Icon(Icons.home_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _sections.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) =>
                      _GallerySectionCard(section: _sections[index]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _GallerySectionCard extends StatelessWidget {
  const _GallerySectionCard({required this.section});

  final _GallerySection section;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: .18),
            foregroundColor: AppColors.primaryDark,
            child: Icon(section.icon),
          ),
          title: Text(
            section.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text('${section.items.length} شاشة'),
          children: section.items
              .map(
                (item) => ListTile(
                  title: Text(item.label),
                  subtitle: Text(
                    item.route,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.end,
                  ),
                  trailing:
                      const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  onTap: () => Get.toNamed<void>(item.route),
                ),
              )
              .toList(growable: false),
        ),
      );
}

class _GallerySection {
  const _GallerySection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_GalleryItem> items;
}

class _GalleryItem {
  const _GalleryItem(this.label, this.route);

  final String label;
  final String route;
}
