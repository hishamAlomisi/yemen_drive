import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// One animation per loading region; the surrounding page stays interactive.
/// Skeletonizer paints ordinary widgets without placeholder text being read
/// aloud or placeholder controls receiving taps.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    final base = Color.alphaBlend(
        scheme.onSurface.withValues(alpha: .10), scheme.surface);
    final highlight = Color.alphaBlend(
        scheme.onSurface.withValues(alpha: .18), scheme.surface);
    return Semantics(
      label: Localizations.localeOf(context).languageCode == 'ar'
          ? 'جارٍ تحميل المحتوى'
          : 'Loading content',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: Skeletonizer(
              enableSwitchAnimation: false,
              effect: MediaQuery.disableAnimationsOf(context)
                  ? SolidColorEffect(color: base)
                  : ShimmerEffect(
                      baseColor: base,
                      highlightColor: highlight,
                      duration: const Duration(milliseconds: 1600),
                    ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({this.count = 3, super.key});
  final int count;

  @override
  Widget build(BuildContext context) => AppSkeleton(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              count,
              (index) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined, size: 40),
                          title: Text('تفاصيل المحتوى المطلوب'),
                          subtitle: Text('المعلومات والتفاصيل الإضافية'),
                        ),
                      ),
                    ),
                  )),
        ),
      );
}

/// Matches the bounded service/vehicle rows instead of collapsing to a thin bar.
class AppSkeletonStrip extends StatelessWidget {
  const AppSkeletonStrip({this.height = 114, super.key});
  final double height;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
    return SizedBox(
      height: height * scale,
      child: AppSkeleton(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, __) => SizedBox(
            width: 110 * scale,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: const [
                    Expanded(
                        child: Center(
                            child: Icon(Icons.directions_car, size: 48))),
                    SizedBox(height: 5),
                    Text('تفاصيل الخدمة', maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
