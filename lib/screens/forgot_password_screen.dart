import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';
import 'reset_link_sent_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter your email';
    final emailReg = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}");
    if (!emailReg.hasMatch(v.trim())) return 'Please enter a valid email';
    return null;
  }

  Future<void> _submit() async {
    final form = _formKey.currentState!;
    if (!form.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = AuthService();
      final resp = await auth.forgotPassword(email: _emailController.text.trim());
      setState(() => _isLoading = false);

      String msg = '';
      if (resp.containsKey('data') && resp['data'] is Map<String, dynamic>) {
        final data = resp['data'] as Map<String, dynamic>;
        if (data.containsKey('message') && data['message'] is String) {
          msg = data['message'];
        }
      }
      if (msg.isEmpty && resp.containsKey('message') && resp['message'] is String) {
        msg = resp['message'];
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (ctx) => ResetLinkSentScreen(message: msg.isNotEmpty ? msg : null),
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
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      title: 'Forgot password',
      onBack: () => Navigator.of(context).maybePop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 20),
          Text('Reset your password', style: AppTextStyles.screenTitle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Enter the email linked to your Anchor World account and we’ll send a reset link.',
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
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: AppTextStyles.ui(size: 16),
                    decoration: authFieldDecoration(
                      label: 'Email',
                      prefix: Icons.mail_outline_rounded,
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Send reset link',
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
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
