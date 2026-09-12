import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../models/auth_models.dart';
import '../../routes/auth_routes.dart';
import '../../widgets/auth_illustration.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AppScaffold(
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: <Widget>[
                      const Spacer(),
                      AuthIllustration(
                        artwork: OnboardingArtwork.cityRide,
                        height: (constraints.maxHeight * .40)
                            .clamp(170, 330)
                            .toDouble(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'welcome_title'.tr,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'welcome_subtitle'.tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const Spacer(flex: 2),
                      AppButton(
                        label: 'create_account'.tr,
                        onPressed: () => Get.toNamed<void>(AuthRoutes.signUp),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'sign_in'.tr,
                        variant: AppButtonVariant.outline,
                        onPressed: () => Get.toNamed<void>(AuthRoutes.signIn),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
