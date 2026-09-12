import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class RideProcessStepper extends StatelessWidget {
  const RideProcessStepper({
    required this.currentStep,
    this.steps = defaultSteps,
    this.compact = false,
    super.key,
  });

  final int currentStep;
  final List<RideProcessStep> steps;
  final bool compact;

  static const List<RideProcessStep> defaultSteps = <RideProcessStep>[
    RideProcessStep('الخدمة', Icons.apps_rounded),
    RideProcessStep('المسار', Icons.alt_route_rounded),
    RideProcessStep('التأكيد', Icons.check_circle_outline_rounded),
    RideProcessStep('التفاوض', Icons.handshake_outlined),
    RideProcessStep('الرحلة', Icons.local_taxi_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = theme.colorScheme.primary;
    final snackSurface = theme.snackBarTheme.backgroundColor ??
        theme.colorScheme.inverseSurface.withValues(alpha: .92);
    final surface = compact
        ? snackSurface.withValues(alpha: .58)
        : snackSurface.withValues(alpha: .88);
    final onSurface = theme.snackBarTheme.contentTextStyle?.color ??
        theme.colorScheme.onInverseSurface;
    final inactive = onSurface.withValues(alpha: .42);
    final radius = BorderRadius.circular(compact ? 11 : 14);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 12,
        compact ? 4 : 10,
        compact ? 6 : 12,
        compact ? 3 : 8,
      ),
      child: Directionality(
        textDirection: Directionality.of(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final nodeAreaHeight = compact ? 26.0 : 34.0;
            final cellWidth = constraints.maxWidth / steps.length;
            return Stack(
              children: <Widget>[
                Positioned(
                  top: nodeAreaHeight / 2 - 1,
                  left: cellWidth / 2,
                  right: cellWidth / 2,
                  child: Row(
                    children: List<Widget>.generate(
                      steps.length - 1,
                      (index) => Expanded(
                        child: Container(
                          height: 2,
                          color: index < currentStep ? active : inactive,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List<Widget>.generate(steps.length, (index) {
                    final step = steps[index];
                    final completed = index < currentStep;
                    final selected = index == currentStep;
                    final color = completed || selected ? active : inactive;
                    return Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            height: nodeAreaHeight,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: selected
                                    ? (compact ? 26 : 34)
                                    : (compact ? 20 : 27),
                                height: selected
                                    ? (compact ? 26 : 34)
                                    : (compact ? 20 : 27),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? active
                                      : theme.colorScheme.surface
                                          .withValues(alpha: .96),
                                  border: Border.all(
                                    color: color,
                                    width: selected ? 2 : 1,
                                  ),
                                  boxShadow: selected
                                      ? <BoxShadow>[
                                          BoxShadow(
                                            color:
                                                active.withValues(alpha: .28),
                                            blurRadius: 9,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  completed ? Icons.check_rounded : step.icon,
                                  size: selected
                                      ? (compact ? 14 : 19)
                                      : (compact ? 11 : 15),
                                  color: selected
                                      ? theme.colorScheme.onPrimary
                                      : color,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 2 : 4),
                          Text(
                            step.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: compact ? 7.5 : 10,
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: compact ? 12 : 8,
          sigmaY: compact ? 12 : 8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: onSurface.withValues(alpha: compact ? .16 : .20),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: compact ? .12 : .20),
                blurRadius: compact ? 8 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: surface,
            elevation: compact ? 1 : 6,
            borderRadius: radius,
            child: content,
          ),
        ),
      ),
    );
  }
}

class RideProcessStep {
  const RideProcessStep(this.label, this.icon);

  final String label;
  final IconData icon;
}
