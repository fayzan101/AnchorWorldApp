import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class ResetLinkSentScreen extends StatelessWidget {
  final String? message;
  const ResetLinkSentScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      title: 'Check email',
      onBack: () => Navigator.of(context).pushReplacementNamed('/signin'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.accentMint.withOpacity(0.2),
                  AppColors.primary.withOpacity(0.12),
                ],
              ),
            ),
            child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 40),
          ),
          const SizedBox(height: 24),
          Text('Check your email', style: AppTextStyles.screenTitle, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            message ?? 'A password reset link has been sent to your email address.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AuthCard(
            child: PrimaryButton(
              label: 'Back to sign in',
              onPressed: () => Navigator.of(context).pushReplacementNamed('/signin'),
            ),
          ),
        ],
      ),
    );
  }
}
