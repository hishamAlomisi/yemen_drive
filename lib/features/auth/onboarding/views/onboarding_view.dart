import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../models/auth_models.dart';
import '../../widgets/auth_illustration.dart';
import '../controllers/onboarding_controller.dart';

class OnboardingScreen extends GetView<OnboardingController> {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AppScaffold(
          body: Column(
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: controller.finish,
                  child: Text('skip'.tr),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller.pageController,
                  onPageChanged: controller.changePage,
                  itemCount: OnboardingController.slides.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _OnboardingSlideView(
                    slide: OnboardingController.slides[index],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Obx(
                () => Row(
                  children: <Widget>[
                    Row(
                      children: List<Widget>.generate(
                        OnboardingController.slides.length,
                        (int index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: controller.currentPage.value == index ? 28 : 9,
                          height: 9,
                          margin: const EdgeInsetsDirectional.only(end: 7),
                          decoration: BoxDecoration(
                            color: controller.currentPage.value == index
                                ? AppColors.primary
                                : Theme.of(
                                    context,
                                  )
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: controller.next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.square(58),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: Icon(
                        controller.isLastPage
                            ? Icons.check_rounded
                            : Icons.arrow_back_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      );
}

class _OnboardingSlideView extends StatelessWidget {
  const _OnboardingSlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AuthIllustration(
                  artwork: slide.artwork,
                  height:
                      (constraints.maxHeight * .52).clamp(120, 310).toDouble(),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  slide.titleKey.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Text(
                    slide.subtitleKey.tr,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .62),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
