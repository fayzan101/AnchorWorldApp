import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/socket_service.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/call_invite_handler.dart';
import '../widgets/auth_scaffold.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      final authToken = prefs.getString('auth_token');

      if ((authToken == null || authToken.isEmpty) &&
          (refreshToken == null || refreshToken.isEmpty)) {
        try {
          await prefs.remove('auth_token');
          await prefs.remove('refresh_token');
          await prefs.remove('remembered_email');
          await prefs.remove('remember_me');
        } catch (_) {}
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 1100));
        Navigator.of(context).pushReplacementNamed('/welcome');
        return;
      }

      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final auth = AuthService();
          await auth.refreshToken(refreshToken);
          try {
            await fcmService.init();
            await SocketService().ensureConnection();
            CallInviteHandler.instance.start();
          } catch (_) {}
          if (!mounted) return;
          await Future.delayed(const Duration(milliseconds: 700));
          await _routeAfterAuth();
          return;
        } catch (_) {}
      }

      if (authToken != null && authToken.isNotEmpty) {
        try {
          await apiClient.setAuthToken(authToken);
        } catch (_) {}
        try {
          await fcmService.init();
          await SocketService().ensureConnection();
          CallInviteHandler.instance.start();
        } catch (_) {}
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 700));
        await _routeAfterAuth();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/welcome');
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/welcome');
    }
  }

  Future<void> _routeAfterAuth() async {
    if (!mounted) return;
    try {
      final auth = AuthService();
      final profileData = await auth.getProfile(forceRefresh: true);
      final verified = profileData['email_verified'] == true ||
          (profileData['email_verified_at'] != null &&
              profileData['email_verified_at'].toString().isNotEmpty);
      if (!verified) {
        final email = (profileData['email'] ?? '').toString();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          '/verify-email',
          arguments: {'email': email, 'fromSignup': false},
        );
        return;
      }
    } catch (_) {}
    if (await _isOnboardingIncomplete()) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    } else {
      try {
        await SocketService().connect();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Future<bool> _isOnboardingIncomplete() async {
    try {
      final auth = AuthService();
      final profileData = await auth.getProfile(forceRefresh: true);
      final onboardingAt = profileData['onboarding_completed_at'];
      final profileCompleted = profileData['profile_completed'] == true;
      final hasOnboarding = onboardingAt != null && onboardingAt.toString().isNotEmpty;
      return !hasOnboarding && !profileCompleted;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A080E), AppColors.primaryDeep, Color(0xFF4B134F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -90,
                right: -70,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.28),
                  ),
                ),
              ),
              Positioned(
                bottom: -110,
                left: -50,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentMint.withOpacity(0.08),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.38,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 80,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AuthBrandMark(size: 112, glow: true),
                        const SizedBox(height: 32),
                        Text('Anchor World', style: AppTextStyles.heroBrand),
                        const SizedBox(height: 10),
                        Text(
                          'Circles · Posts · Community',
                          style: AppTextStyles.ui(
                            size: 14,
                            color: AppColors.white.withOpacity(0.78),
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
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
