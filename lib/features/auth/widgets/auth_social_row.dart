import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or'.tr),
          ),
          const Expanded(child: Divider()),
        ],
      );
}

class AuthSocialRow extends StatelessWidget {
  const AuthSocialRow({required this.onProviderPressed, super.key});

  final ValueChanged<String> onProviderPressed;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _SocialButton(
            label: 'G',
            color: const Color(0xFFDB4437),
            onPressed: () => onProviderPressed('Google'),
          ),
          const SizedBox(width: 14),
          _SocialButton(
            label: 'f',
            color: const Color(0xFF1877F2),
            onPressed: () => onProviderPressed('Facebook'),
          ),
          const SizedBox(width: 14),
          _SocialButton(
            icon: Icons.apple,
            color: Theme.of(context).colorScheme.onSurface,
            onPressed: () => onProviderPressed('Apple'),
          ),
        ],
      );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.color,
    required this.onPressed,
    this.label,
    this.icon,
  });

  final String? label;
  final IconData? icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 50,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: icon != null
              ? Icon(icon, color: color)
              : Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
        ),
      );
}
