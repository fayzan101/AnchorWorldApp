import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/socket_service.dart';
import '../config/api_config.dart';
import '../network/api_client.dart' show ApiException;
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
    // Do not auto-login here — Splash handles session restore.
    // Welcome → Sign in should always show the form (remember me only prefills email).
    _emailController.addListener(() {
      if (_emailError != null) setState(() => _emailError = null);
    });
    _passwordController.addListener(() {
      if (_passwordError != null) setState(() => _passwordError = null);
    });
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('remembered_email') ?? '';
    final remember = prefs.getBool('remember_me') ?? false;
    setState(() {
      if (_emailController.text.isEmpty) _emailController.text = email;
      _rememberMe = remember;
    });
  }

  Future<void> _navigateAfterAuth(AuthService auth) async {
    var needsOnboarding = false;
    try {
      final profile = await auth.getProfile(forceRefresh: true);
      final onboardingAt = profile['onboarding_completed_at'];
      final profileCompleted = profile['profile_completed'] == true;
      final hasOnboarding = onboardingAt != null && onboardingAt.toString().isNotEmpty;
      needsOnboarding = !hasOnboarding && !profileCompleted;
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      needsOnboarding ? '/onboarding' : '/home',
      (_) => false,
    );
  }

  String? _validateEmail(String? v) {
    if (_emailError != null) return _emailError;
    if (v == null || v.trim().isEmpty) return 'Please enter your email';
    final emailReg = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}");
    if (!emailReg.hasMatch(v.trim())) return 'Please enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (_passwordError != null) return _passwordError;
    if (v == null || v.isEmpty) return 'Please enter your password';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _submit() async {
    final form = _formKey.currentState!;
    setState(() {
      _emailError = null;
      _passwordError = null;
    });
    if (!form.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = AuthService();
      final resp = await auth.login(
        _emailController.text.trim(),
        _passwordController.text,
        persist: _rememberMe,
      );
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailController.text.trim());
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('remembered_email');
        await prefs.setBool('remember_me', false);
      }

      setState(() => _isLoading = false);
      if (resp.isNotEmpty) {
        String msg = '';
        if (resp.containsKey(ApiConfig.messageKey) && resp[ApiConfig.messageKey] is String) {
          msg = resp[ApiConfig.messageKey];
        }
        if (msg.isNotEmpty) customSnackBar('Success', msg);
        try {
          await notificationService.toggleNotifications(true);
        } catch (_) {}
        try {
          await SocketService().connect();
        } catch (_) {}

        var needsOnboarding = false;
        try {
          final profile = await auth.getProfile(forceRefresh: true);
          final onboardingAt = profile['onboarding_completed_at'];
          final profileCompleted = profile['profile_completed'] == true;
          final hasOnboarding = onboardingAt != null && onboardingAt.toString().isNotEmpty;
          needsOnboarding = !hasOnboarding && !profileCompleted;
        } catch (_) {}

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
      needsOnboarding ? '/onboarding' : '/home',
      (_) => false,
    );
      } else {
        customSnackBar('Error', 'Login failed: empty response');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (e is ApiException) {
        final code = e.statusCode;
        final message = (e.message ?? '').toString();
        final lower = message.toLowerCase();
        final notVerified = code == 403 ||
            lower.contains('email_not_verified') ||
            lower.contains('verify your email') ||
            lower.contains('not verified');
        if (notVerified) {
          customSnackBar(
            'Verify email',
            'Enter the code we sent to your inbox',
            type: SnackType.info,
          );
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            '/verify-email',
            arguments: {
              'email': _emailController.text.trim(),
              'fromSignup': false,
            },
          );
          return;
        }
        if (code == 401 ||
            lower.contains('unauthor') ||
            lower.contains('invalid') ||
            lower.contains('credential') ||
            lower.contains('password')) {
          setState(() {
            _emailError = 'Invalid email or password';
            _passwordError = 'Invalid email or password';
          });
          _formKey.currentState?.validate();
          customSnackBar('Error', 'Invalid email or password');
        } else {
          String display = message;
          if (message.contains('"error"')) {
            final m = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message);
            if (m != null) display = m.group(1)!;
          }
          customSnackBar('Error', display.isNotEmpty ? display : 'An error occurred');
        }
      } else {
        final msg = e is Exception ? e.toString() : 'Unknown error';
        customSnackBar('Error', msg.replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      onBack: () => Navigator.of(context).pushReplacementNamed('/welcome'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AuthHeader(
            title: 'Welcome back',
            subtitle: 'Sign in to your community',
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
                    textInputAction: TextInputAction.next,
                    style: AppTextStyles.ui(size: 16),
                    decoration: authFieldDecoration(
                      label: 'Email',
                      prefix: Icons.mail_outline_rounded,
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                    style: AppTextStyles.ui(size: 16),
                    decoration: authFieldDecoration(
                      label: 'Password',
                      prefix: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.primary,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          activeColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Remember me', style: AppTextStyles.ui(size: 13, weight: FontWeight.w500)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                        child: Text(
                          'Forgot password?',
                          style: AppTextStyles.ui(size: 13, color: AppColors.primary, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: 'Sign in',
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTextStyles.ui(size: 14, color: AppColors.body),
              children: [
                const TextSpan(text: "Don't have an account? "),
                TextSpan(
                  text: 'Create account',
                  style: AppTextStyles.ui(size: 14, color: AppColors.primary, weight: FontWeight.w700),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => Navigator.of(context).pushNamed('/signup'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
