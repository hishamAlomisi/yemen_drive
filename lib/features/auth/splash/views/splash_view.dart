import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/services/startup_connection_service.dart';
import '../controllers/splash_controller.dart';
import '../widgets/splash_motion.dart';
import '../widgets/splash_scenery.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SplashController>();
    return Obx(
      () => SplashArtwork(
        status: controller.connection.status.value,
        onRetry: controller.retry,
        // Bootstrap already presented the entrance while checking the API.
        animateEntrance: !controller.connection.isVerified,
      ),
    );
  }
}

/// Shared by service initialization and the splash route. The rider logo and
/// app icon are bitmaps; the scene, text, benefit icons and loading UI are Flutter.
class SplashArtwork extends StatefulWidget {
  const SplashArtwork({
    this.status = const StartupStatus(StartupPhase.initializing),
    this.onRetry,
    this.animateEntrance = true,
    super.key,
  });

  final StartupStatus status;
  final VoidCallback? onRetry;
  final bool animateEntrance;

  static const logoAsset = 'assets/images/branding/rider_splash_logo.png';
  static const appIconAsset = 'assets/images/branding/yemen_drive_logo.png';
  static const backgroundColor = Color(0xFF003C30);
  static const gold = Color(0xFFFFD46B);

  @override
  State<SplashArtwork> createState() => _SplashArtworkState();
}

class _SplashArtworkState extends State<SplashArtwork>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _lightSweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _logoTrace = _lightSweep.drive(
    CurveTween(curve: const Interval(.06, .78)),
  );
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion || !widget.animateEntrance || widget.status.hasFailed) {
      _entrance.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _entrance.forward();
    }
    _syncLightSweep();
  }

  @override
  void didUpdateWidget(SplashArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Retrying resumes the light sweep, without replaying the entrance.
    if (widget.status.hasFailed || !widget.animateEntrance) _entrance.value = 1;
    _syncLightSweep();
  }

  void _syncLightSweep() {
    final waiting =
        widget.status.phase != StartupPhase.ready && !widget.status.hasFailed;
    if (waiting && !_reduceMotion) {
      if (!_lightSweep.isAnimating) {
        _lightSweep.value = 0;
        _lightSweep.repeat();
      }
    } else {
      // Value 1 leaves no residual outline and stops scheduling frames.
      _lightSweep.value = 1;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _lightSweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: SplashArtwork.backgroundColor,
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const RepaintBoundary(
                  child: CustomPaint(painter: SplashSceneryPainter()),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Match the reference at 390 x 693, distributing extra
                      // height between sections without stretching the logo.
                      final scale = math.min(
                        constraints.maxWidth / 390,
                        constraints.maxHeight / 693,
                      );
                      final extra = constraints.maxHeight - 693 * scale;
                      // Translate from the viewport center to the final logo center.
                      final logoCenter = 274 * scale + extra * .31;
                      final centerRise =
                          (constraints.maxHeight / 2 - logoCenter) /
                              (388 * scale);
                      return Center(
                        child: SizedBox(
                          width: 390 * scale,
                          child: Column(
                            children: [
                              SizedBox(height: 18 * scale + extra * .08),
                              SplashEntrance(
                                timeline: _entrance,
                                begin: 0,
                                end: .34,
                                rise: -.2,
                                child: _BrandSignature(scale: scale),
                              ),
                              SizedBox(height: 26 * scale + extra * .23),
                              SplashEntrance(
                                key: const ValueKey('splash-logo-entrance'),
                                timeline: _entrance,
                                begin: 0,
                                end: .68,
                                rise: centerRise,
                                scaleFrom: .12,
                                child: SizedBox(
                                  height: 388 * scale,
                                  width: 388 * scale,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      RepaintBoundary(
                                        child: Image.asset(
                                          SplashArtwork.logoAsset,
                                          key: const ValueKey(
                                            'splash-rider-logo',
                                          ),
                                          fit: BoxFit.contain,
                                          alignment: Alignment.bottomCenter,
                                          semanticLabel:
                                              'يمن درايف، رحلتك بين يديك',
                                          filterQuality: FilterQuality.medium,
                                        ),
                                      ),
                                      IgnorePointer(
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            painter: SplashTracePainter(
                                              progress: _logoTrace,
                                              shape: SplashTraceShape.logo,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 12 * scale + extra * .15),
                              SplashEntrance(
                                timeline: _entrance,
                                begin: .25,
                                end: .66,
                                child: _SplashText(
                                  'رحلتك بين يديك',
                                  height: 34 * scale,
                                  fontSize: 25 * scale,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SplashEntrance(
                                timeline: _entrance,
                                begin: .32,
                                end: .72,
                                child: _SplashText(
                                  'اطلب .. وانت في مكانك .. مع يمن درايف',
                                  height: 24 * scale,
                                  fontSize: 14.1 * scale,
                                  color: const Color(0xFFBCD0C4),
                                ),
                              ),
                              SizedBox(height: 22 * scale + extra * .16),
                              _RiderBenefits(
                                scale: scale,
                                timeline: _entrance,
                                lightSweep: _lightSweep,
                              ),
                              const Spacer(),
                              if (!widget.status.hasFailed)
                                _LoadingFooter(
                                  scale: scale,
                                  status: widget.status,
                                ),
                              SizedBox(height: 22 * scale + extra * .08),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.status.hasFailed) ...[
                  const ColoredBox(color: Color(0x66001B16)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: _ConnectionFailureCard(
                        status: widget.status,
                        onRetry: widget.onRetry,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _BrandSignature extends StatelessWidget {
  const _BrandSignature({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36 * scale,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 19 * scale),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10 * scale),
                child: Image.asset(
                  SplashArtwork.appIconAsset,
                  key: const ValueKey('splash-app-icon'),
                  width: 36 * scale,
                  height: 36 * scale,
                  cacheWidth: 128,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
              SizedBox(width: 9 * scale),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SplashText(
                    'يمن درايف',
                    height: 19 * scale,
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                  _SplashText(
                    'رحلتك بين يديك',
                    height: 13 * scale,
                    fontSize: 9 * scale,
                    color: SplashArtwork.gold.withValues(alpha: .8),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      );
}

class _SplashText extends StatelessWidget {
  const _SplashText(
    this.text, {
    required this.height,
    required this.fontSize,
    this.color = const Color(0xFFF8FAF5),
    this.fontWeight = FontWeight.w400,
  });

  final String text;
  final double height;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: fontSize,
              fontWeight: fontWeight,
              height: 1.25,
              color: color,
              shadows: const [
                Shadow(color: Color(0x55001310), blurRadius: 8),
              ],
            ),
          ),
        ),
      );
}

class _RiderBenefits extends StatelessWidget {
  const _RiderBenefits({
    required this.scale,
    required this.timeline,
    required this.lightSweep,
  });

  final double scale;
  final Animation<double> timeline;
  final Animation<double> lightSweep;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 62 * scale,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 26 * scale),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              _benefit(SplashBenefitIcon.request, 'طلب سريع', 2),
              _divider(),
              _benefit(SplashBenefitIcon.trusted, 'رحلات موثوقة', 1),
              _divider(),
              _benefit(SplashBenefitIcon.safety, 'رحلات آمنة', 0),
            ],
          ),
        ),
      );

  Widget _divider() => Container(
        width: .8 * scale,
        height: 36 * scale,
        color: const Color(0xFF335A48),
      );

  Widget _benefit(SplashBenefitIcon icon, String label, int order) => Expanded(
        child: SplashEntrance(
          timeline: timeline,
          begin: .4 + order * .07,
          end: .76 + order * .07,
          child: Semantics(
            label: label,
            child: ExcludeSemantics(
              child: Column(
                children: [
                  CustomPaint(
                    foregroundPainter: SplashTracePainter(
                      progress: lightSweep.drive(
                        CurveTween(
                          curve: Interval(.46 + order * .07, .85 + order * .07),
                        ),
                      ),
                      shape: SplashTraceShape.benefit,
                    ),
                    child: Container(
                      width: 35 * scale,
                      height: 35 * scale,
                      padding: EdgeInsets.all(7 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0x3300221C),
                        borderRadius: BorderRadius.circular(10 * scale),
                        border: Border.all(
                          color: const Color(0xFF335847),
                          width: 1.25 * scale,
                        ),
                      ),
                      child: CustomPaint(painter: SplashBenefitPainter(icon)),
                    ),
                  ),
                  SizedBox(height: 5 * scale),
                  _SplashText(
                    label,
                    height: 22 * scale,
                    fontSize: 12.5 * scale,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter({required this.scale, required this.status});

  final double scale;
  final StartupStatus status;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24 * scale,
        child: Column(
          children: [
            SizedBox(
              width: 130 * scale,
              height: 4 * scale,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4 * scale),
                child: LinearProgressIndicator(
                  // Service initialization has no known percentage.
                  value: status.phase == StartupPhase.ready
                      ? 1
                      : MediaQuery.disableAnimationsOf(context)
                          ? .48
                          : null,
                  color: SplashArtwork.gold,
                  backgroundColor: const Color(0xFF125245),
                  semanticsLabel: status.message,
                ),
              ),
            ),
            SizedBox(height: 4 * scale),
            _SplashText(
              status.message,
              height: 16 * scale,
              fontSize: 9 * scale,
              color: const Color(0xFF9FB8AB),
            ),
          ],
        ),
      );
}

class _ConnectionFailureCard extends StatelessWidget {
  const _ConnectionFailureCard({required this.status, required this.onRetry});

  final StartupStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF073F33),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF6B6840)),
              boxShadow: const [
                BoxShadow(color: Color(0x55001410), blurRadius: 24),
              ],
            ),
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 17,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: SplashArtwork.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status.advice,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 13,
                      height: 1.7,
                      color: Color(0xFFE0EBE3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: SplashArtwork.gold,
                        foregroundColor: const Color(0xFF003C30),
                        textStyle: const TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
