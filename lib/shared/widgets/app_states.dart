import 'package:flutter/material.dart';

import 'app_button.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({this.label = 'جارٍ التحميل...', super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 64, color: Theme.of(context).colorScheme.primary,),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null) ...<Widget>[
                const SizedBox(height: 20),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  fullWidth: false,
                ),
              ],
            ],
          ),
        ),
      );
}

class AppErrorState extends AppEmptyState {
  const AppErrorState({
    required super.title,
    required super.message,
    super.actionLabel,
    super.onAction,
    super.key,
  }) : super(icon: Icons.error_outline_rounded);
}
