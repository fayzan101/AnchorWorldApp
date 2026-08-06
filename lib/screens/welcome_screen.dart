import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A080E), AppColors.primaryDeep, Color(0xFF4B134F)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.25),
                  ),
                ),
              ),
              Positioned(
                bottom: h * 0.22,
                left: -80,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentMint.withOpacity(0.07),
                  ),
                ),
              ),
              Positioned(
                top: h * 0.16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 90,
                          spreadRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 2),
                      const Center(child: AuthBrandMark(size: 120, glow: true)),
                      const SizedBox(height: 28),
                      Text(
                        'Anchor World',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heroBrand,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Join Your Community',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.display(
                          24,
                          color: AppColors.white.withOpacity(0.95),
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Post in circles, earn Anchor Points, unlock premium features, and connect with your community.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.ui(
                          size: 15,
                          color: AppColors.white.withOpacity(0.8),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          _WelcomePill(icon: Icons.forum_outlined, label: 'Circles'),
                          SizedBox(width: 8),
                          _WelcomePill(icon: Icons.auto_awesome_outlined, label: 'Points'),
                          SizedBox(width: 8),
                          _WelcomePill(icon: Icons.videocam_outlined, label: 'Intros'),
                        ],
                      ),
                      const Spacer(flex: 3),
                      PrimaryButton(
                        label: 'Create account',
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/signup'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/signin'),
                        child: Text(
                          'Already have an account? Sign in',
                          style: AppTextStyles.ui(
                            size: 15,
                            color: AppColors.white,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _WelcomePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.white.withOpacity(0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.ui(size: 12, color: AppColors.white, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
