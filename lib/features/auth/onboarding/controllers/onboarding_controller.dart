import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../../ride/ride_routes.dart';
import '../../models/auth_models.dart';

class OnboardingController extends GetxController {
  OnboardingController({required int initialPage, GetStorage? storage})
      : currentPage = initialPage.obs,
        pageController = PageController(initialPage: initialPage),
        _storage = storage ?? GetStorage();

  static const List<OnboardingSlide> slides = <OnboardingSlide>[
    OnboardingSlide(
      titleKey: 'onboarding_1_title',
      subtitleKey: 'onboarding_1_subtitle',
      artwork: OnboardingArtwork.cityRide,
    ),
    OnboardingSlide(
      titleKey: 'onboarding_2_title',
      subtitleKey: 'onboarding_2_subtitle',
      artwork: OnboardingArtwork.fastPickup,
    ),
    OnboardingSlide(
      titleKey: 'onboarding_3_title',
      subtitleKey: 'onboarding_3_subtitle',
      artwork: OnboardingArtwork.liveTracking,
    ),
  ];

  final RxInt currentPage;
  final PageController pageController;
  final GetStorage _storage;

  bool get isLastPage => currentPage.value == slides.length - 1;

  void changePage(int index) => currentPage.value = index;

  Future<void> next() async {
    if (isLastPage) {
      await finish();
      return;
    }
    await pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> finish() async {
    await _storage.write('has_seen_onboarding', true);
    Get.offAllNamed<void>(RideRoutes.homeTransport);
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
