import 'package:flutter/material.dart';
import '../utils/custom_snackbar.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? resetToken;
  const ResetPasswordScreen({super.key, this.resetToken});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Please enter a password';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _save() async {
    final form = _formKey.currentState!;
    if (!form.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      customSnackBar('Error', 'Passwords do not match');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final auth = AuthService();
      if (widget.resetToken == null || widget.resetToken!.isEmpty) {
        customSnackBar('Error', 'Reset token not found. Please request a new password reset link.');
        setState(() => _isLoading = false);
        return;
      }

      await auth.resetPassword(
        token: widget.resetToken!,
        newPassword: _passwordController.text,
      );
      setState(() => _isLoading = false);

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentMint.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: AppColors.accentMint),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Password changed', style: AppTextStyles.sectionTitle)),
              ],
            ),
            content: Text(
              'Your password has been updated. You can sign in with your new password.',
              style: AppTextStyles.body,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushReplacementNamed('/signin');
                },
                child: Text('Sign in', style: AppTextStyles.ui(color: AppColors.primary, weight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final message = e is Exception ? e.toString().replaceAll('ApiException: ', '') : 'Request failed';
      customSnackBar('Error', message);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      title: 'New password',
      onBack: () => Navigator.of(context).pushReplacementNamed('/signin'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Create a new password', style: AppTextStyles.screenTitle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Choose a strong password you haven’t used before.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          AuthCard(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    style: AppTextStyles.ui(size: 16),
                    validator: _validatePassword,
                    decoration: authFieldDecoration(
                      label: 'New password',
                      prefix: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.primary,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    style: AppTextStyles.ui(size: 16),
                    validator: _validatePassword,
                    decoration: authFieldDecoration(
                      label: 'Confirm password',
                      prefix: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.primary,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Save password',
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
