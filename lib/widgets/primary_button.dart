import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shared height so Back / Continue stay visually matched in rows.
const double kAppButtonHeight = 54;

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.white),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: AppTextStyles.button,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );

    final button = AnimatedScale(
      scale: onPressed == null || loading ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        height: kAppButtonHeight,
        width: expanded ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: onPressed == null || loading ? null : AppColors.brandGradient,
            color: onPressed == null || loading ? AppColors.primary.withOpacity(0.45) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: onPressed == null || loading
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: loading ? null : onPressed,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );

    if (!expanded) return button;
    return button;
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool expanded;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: kAppButtonHeight,
      width: expanded ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, kAppButtonHeight),
          maximumSize: const Size(double.infinity, kAppButtonHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: AppTextStyles.ui(size: 16, weight: FontWeight.w700, color: AppColors.primary),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    return button;
  }
}
