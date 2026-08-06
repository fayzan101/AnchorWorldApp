import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'primary_button.dart';

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData icon;

  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.icon = Icons.groups_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    AppColors.accentGold.withOpacity(0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.75)),
            ),
            const SizedBox(height: 24),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.screenTitle),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: 24),
            PrimaryButton(label: primaryLabel, onPressed: onPrimary, expanded: false),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!, style: AppTextStyles.ui(color: AppColors.body)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
