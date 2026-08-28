import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import 'pressable.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = AppGradients.brand,
    this.expand = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Pressable(
      onTap: onPressed,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          width: expand ? double.infinity : null,
          padding: padding,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.onBrand, size: fontSize + 3),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: AppColors.onBrand,
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
