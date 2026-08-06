import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

/// Enter the 6-digit code emailed after signup (or when signing in unverified).
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  /// When true, after verify go to onboarding; otherwise route like splash (onboarding vs home).
  final bool fromSignup;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.fromSignup = true,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _verifying = false;
  bool _resending = false;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    _startCooldown(30);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    setState(() => _resendCooldown = seconds);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (_resendCooldown <= 1) {
        setState(() => _resendCooldown = 0);
        return false;
      }
      setState(() => _resendCooldown -= 1);
      return true;
    });
  }

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _verifying = true);
    try {
      await AuthService().verifyEmail(
        email: widget.email,
        code: _codeCtrl.text.trim(),
      );
      if (!mounted) return;
      customSnackBar('Verified', 'Your email is confirmed', type: SnackType.success);
      if (widget.fromSignup) {
        Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (_) => false);
        return;
      }
      try {
        final profile = await AuthService().getProfile(forceRefresh: true);
        final onboardingAt = profile['onboarding_completed_at'];
        final profileCompleted = profile['profile_completed'] == true;
        final hasOnboarding = onboardingAt != null && onboardingAt.toString().isNotEmpty;
        final needsOnboarding = !hasOnboarding && !profileCompleted;
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          needsOnboarding ? '/onboarding' : '/home',
          (_) => false,
        );
      } catch (_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? (e.message ?? 'Verification failed')
          : e.toString().replaceAll('ApiException: ', '');
      // Prefer human error string if JSON blob was encoded.
      String display = message;
      if (message.contains('"error"')) {
        final m = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message);
        if (m != null) display = m.group(1)!;
      }
      customSnackBar('Error', display, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      await AuthService().resendVerification(email: widget.email);
      if (!mounted) return;
      customSnackBar('Sent', 'A new code was sent to your email', type: SnackType.success);
      _startCooldown(45);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? (e.message ?? 'Could not resend')
          : e.toString().replaceAll('ApiException: ', '');
      customSnackBar('Error', message, type: SnackType.error);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      title: 'Verify email',
      onBack: () => Navigator.of(context).pushReplacementNamed('/signin'),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.1),
              ),
              child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Check your inbox', style: AppTextStyles.screenTitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to\n${widget.email}',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppTextStyles.ui(size: 28, weight: FontWeight.w800, color: AppColors.ink),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: AppTextStyles.ui(size: 28, weight: FontWeight.w700, color: AppColors.body.withOpacity(0.35)),
                filled: true,
                fillColor: AppColors.chipIdle,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.mutedBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
                ),
              ),
              validator: (v) {
                final code = (v ?? '').trim();
                if (code.length != 6) return 'Enter the 6-digit code';
                return null;
              },
              onFieldSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Verify',
              loading: _verifying,
              onPressed: _verifying ? null : _verify,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: (_resendCooldown > 0 || _resending) ? null : _resend,
              child: Text(
                _resending
                    ? 'Sending…'
                    : _resendCooldown > 0
                        ? 'Resend code in ${_resendCooldown}s'
                        : 'Resend code',
                style: AppTextStyles.ui(
                  weight: FontWeight.w700,
                  color: (_resendCooldown > 0 || _resending) ? AppColors.body : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
