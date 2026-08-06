import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../network/api_client.dart' show ApiException;
import '../utils/custom_snackbar.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _passwordObscured = true;
  bool _acceptedTerms = false;
  bool _confirmPasswordObscured = true;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _professionController = TextEditingController();
  final _dobController = TextEditingController();
  final _referralController = TextEditingController();
  /// When true, invite came from a deep link and must not be edited.
  bool _referralFromLink = false;
  String? _photoUrl;
  File? _photoFile;
  String? _gender;
  DateTime? _dateOfBirth;
  bool _isLoading = false;
  int _step = 0;
  int _previousStep = 0;
  String? _emailError;
  int? _showValidationStep;
  bool _fixingObscuredSelection = false;
  late final TapGestureRecognizer _privacyTap;
  late final TapGestureRecognizer _termsTap;

  InputDecoration _inputDecoration({String? label, String? hint, IconData? prefix}) {
    return authFieldDecoration(
      label: label ?? '',
      hint: hint,
      prefix: prefix,
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
    if (v == null || v.isEmpty) return 'Please enter your password';
    if (v.length < 8) return 'Password must be at least 8 characters';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(v);
    final hasLower = RegExp(r'[a-z]').hasMatch(v);
    final hasDigit = RegExp(r'\d').hasMatch(v);
    if (!hasUpper || !hasLower || !hasDigit) return 'Password must contain uppercase, lowercase, and a number';
    return null;
  }

  Future<void> _submit() async {
    if (!_validateAllBeforeSubmit()) return;
    setState(() => _isLoading = true);
    try {
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
      final dob = _dateOfBirth != null ? '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}' : '';
      final auth = AuthService();
      final resp = await auth.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: fullName,
        dateOfBirth: dob,
        gender: _gender ?? 'male',
        referralCode: _referralController.text.trim().isEmpty
            ? null
            : _referralController.text.trim(),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_referral_code');
      } catch (_) {}
      if (_photoFile != null) {
        try {
          await _uploadPhoto();
        } catch (_) {
        }
      }

      setState(() => _isLoading = false);
      if (!mounted) return;

      bool needsVerify = true;
      if (resp is Map) {
        final data = resp['data'];
        if (data is Map && data['email_verification_required'] == false) {
          needsVerify = false;
        } else if (resp['email_verification_required'] == false) {
          needsVerify = false;
        }
      }
      if (needsVerify) {
        Navigator.of(context).pushReplacementNamed(
          '/verify-email',
          arguments: {
            'email': _emailController.text.trim(),
            'fromSignup': true,
          },
        );
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (e is ApiException) {
        if (e.statusCode == 409) {
          setState(() => _emailError = 'Email already registered');
          _formKey.currentState?.validate();
          customSnackBar('Error', 'Email already registered');
          return;
        }
        final message = e.message ?? 'Registration failed';
        customSnackBar('Error', message);
        return;
      }

      final message = e is Exception ? e.toString().replaceAll('ApiException: ', '') : 'Registration failed';
      customSnackBar('Error', message);
    }
  }

  Future<void> _uploadPhoto() async {
    if (_photoFile == null) return;
    try {
      final resp = await AuthService().uploadProfilePicture(_photoFile!);
      if (!mounted) return;
      Map<String, dynamic> profileData = {};
      if (resp.containsKey(ApiConfig.dataKey) && resp[ApiConfig.dataKey] is Map<String, dynamic>) {
        profileData = Map<String, dynamic>.from(resp[ApiConfig.dataKey]);
      } else if (resp.isNotEmpty) {
        profileData = Map<String, dynamic>.from(resp);
      }
      String? image = (profileData['profile_picture'] ?? profileData['imageUrl'] ?? profileData['image_url'] ?? profileData['avatar'])?.toString();
      if (image != null && image.isNotEmpty) {
        final img = image.trim();
        if (img.startsWith('http')) {
          setState(() {
            _photoUrl = img;
            _photoFile = null;
          });
        }
      }
      customSnackBar('Success', 'Profile picture uploaded');
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceAll('ApiException: ', '') : 'Failed to upload photo';
      customSnackBar('Error', msg);
    }
  }

  @override
  void initState() {
    super.initState();
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openPolicyUrl(ApiConfig.privacyPolicyUrl);
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _openPolicyUrl(ApiConfig.termsOfServiceUrl);
    _emailController.addListener(() {
      if (_emailError != null) setState(() => _emailError = null);
    });
    _passwordController.addListener(
      () => _guardObscuredSelection(_passwordController, () => _passwordObscured),
    );
    _confirmPasswordController.addListener(
      () => _guardObscuredSelection(_confirmPasswordController, () => _confirmPasswordObscured),
    );
    SharedPreferences.getInstance().then((prefs) {
      final pending = prefs.getString('pending_referral_code');
      if (pending != null && pending.isNotEmpty && mounted) {
        setState(() {
          _referralController.text = pending;
          _referralFromLink = true;
        });
      }
    });
  }

  Future<void> _openPolicyUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      customSnackBar('Error', 'Could not open link');
    }
  }

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _professionController.dispose();
    _confirmPasswordController.dispose();
    _dobController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  int get _totalSteps => 5; // names, dob, gender, email, password

  Widget _buildStepContentForIndex(int index) {
    switch (index) {
      case 0:
        return Column(
          key: const ValueKey('names'),
          children: [
            TextFormField(
              controller: _firstNameController,
              style: const TextStyle(color: Colors.black87, fontSize: 18),
              decoration: _inputDecoration(label: 'First name', hint: 'Enter first name'),
              validator: (v) {
                if (_showValidationStep != 0) return null;
                if (v == null || v.trim().isEmpty) return 'Please enter first name';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              style: const TextStyle(color: Colors.black87, fontSize: 18),
              decoration: _inputDecoration(label: 'Last name', hint: 'Enter last name'),
              validator: (v) {
                if (_showValidationStep != 0) return null;
                if (v == null || v.trim().isEmpty) return 'Please enter last name';
                return null;
              },
            ),
          ],
        );
      case 1:
        return GestureDetector(
          key: const ValueKey('dob'),
          onTap: () async {
            final now = DateTime.now();
            final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(now.year - 25),
              firstDate: DateTime(1900),
              lastDate: eighteenYearsAgo,
            );
            if (picked != null) {
              setState(() {
                _dateOfBirth = picked;
                _dobController.text = '${picked.day}/${picked.month}/${picked.year}';
              });
            }
          },
            child: AbsorbPointer(
            child: TextFormField(
              controller: _dobController,
              style: const TextStyle(color: Colors.black87, fontSize: 18),
              decoration: _inputDecoration(label: 'Date of birth', hint: 'Select date', prefix: Icons.cake),
              validator: (_) {
                if (_showValidationStep != 1) return null;
                if (_dateOfBirth == null) return 'Please select date of birth';
                return null;
              },
            ),
          ),
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            DropdownButtonFormField2<String>(
              key: const ValueKey('gender'),
              value: _gender,
              isExpanded: true,
              decoration: _inputDecoration(label: 'Gender', hint: 'Select gender', prefix: Icons.wc),
              hint: Text('Select gender', style: TextStyle(color: AppColors.primary)),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
              ),
              style: AppTextStyles.ui(size: 16),
              items: [
                DropdownMenuItem(value: 'male', child: Text('Male', style: AppTextStyles.ui())),
                DropdownMenuItem(value: 'female', child: Text('Female', style: AppTextStyles.ui())),
                DropdownMenuItem(value: 'other', child: Text('Other', style: AppTextStyles.ui())),
              ],
              onChanged: (v) => setState(() => _gender = v),
              validator: (v) {
                if (_showValidationStep != 2) return null;
                if (v == null || v.trim().isEmpty) return 'Please select gender';
                return null;
              },
            ),
            const SizedBox(height: 40),
          ],
        );
      case 3:
        return TextFormField(
          key: const ValueKey('email'),
          controller: _emailController,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDecoration(label: 'Email', prefix: Icons.email_outlined),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (_showValidationStep != 3) return null;
            return _validateEmail(v);
          },
        );
      case 4:
        return SingleChildScrollView(
          key: const ValueKey('password'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _passwordController,
                obscureText: _passwordObscured,
                enableSuggestions: false,
                autocorrect: false,
                enableInteractiveSelection: true,
                style: const TextStyle(color: Colors.black87),
                decoration: _inputDecoration(label: 'Password', prefix: Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_passwordObscured ? Icons.visibility_off : Icons.visibility, color: AppColors.primary),
                    onPressed: () => setState(() => _passwordObscured = !_passwordObscured),
                  ),
                ),
                onTap: () => _collapseObscuredSelection(_passwordController),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                validator: (v) {
                  if (_showValidationStep != 4) return null;
                  return _validatePassword(v);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _confirmPasswordObscured,
                enableSuggestions: false,
                autocorrect: false,
                enableInteractiveSelection: true,
                style: const TextStyle(color: Colors.black87),
                decoration: _inputDecoration(label: 'Confirm password', prefix: Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_confirmPasswordObscured ? Icons.visibility_off : Icons.visibility, color: AppColors.primary),
                    onPressed: () => setState(() => _confirmPasswordObscured = !_confirmPasswordObscured),
                  ),
                ),
                onTap: () => _collapseObscuredSelection(_confirmPasswordController),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                validator: (v) {
                  if (_showValidationStep != 4) return null;
                  if (v == null || v.isEmpty) return 'Please confirm your password';
                  if (v != _passwordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _referralController,
                readOnly: _referralFromLink,
                enableInteractiveSelection: !_referralFromLink,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                decoration: _inputDecoration(
                  label: _referralFromLink ? 'Invite code (from link)' : 'Invite code (optional)',
                  hint: 'Friend’s referral code',
                  prefix: Icons.card_giftcard_outlined,
                ).copyWith(
                  suffixIcon: _referralFromLink
                      ? const Icon(Icons.lock_outline_rounded, color: AppColors.body, size: 20)
                      : null,
                  helperText: _referralFromLink
                      ? 'Applied from your invite link — this can’t be changed.'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                value: _acceptedTerms,
                onChanged: (val) {
                  setState(() => _acceptedTerms = val ?? false);
                },
                activeColor: AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text.rich(
                  TextSpan(
                    style: AppTextStyles.ui(size: 13),
                    children: [
                      const TextSpan(text: 'I accept the '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: AppTextStyles.ui(
                          size: 13,
                          color: AppColors.primary,
                          weight: FontWeight.w700,
                        ).copyWith(decoration: TextDecoration.underline),
                        recognizer: _privacyTap,
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: AppTextStyles.ui(
                          size: 13,
                          color: AppColors.primary,
                          weight: FontWeight.w700,
                        ).copyWith(decoration: TextDecoration.underline),
                        recognizer: _termsTap,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  

  bool _validateAllBeforeSubmit() {
    if (_firstNameController.text.trim().isEmpty || _lastNameController.text.trim().isEmpty) {
  setState(() { _previousStep = _step; _step = 0; _showValidationStep = 0; });
      _formKey.currentState?.validate();
      customSnackBar('Error', 'Enter first and last name');
      return false;
    }
    if (_dateOfBirth == null) {
  setState(() { _previousStep = _step; _step = 1; _showValidationStep = 1; });
      _formKey.currentState?.validate();
      customSnackBar('Error', 'Please select your date of birth');
      return false;
    }
    if (_gender == null) {
  setState(() { _previousStep = _step; _step = 2; _showValidationStep = 2; });
      _formKey.currentState?.validate();
      customSnackBar('Error', 'Please select gender');
      return false;
    }
    final emailErr = _validateEmail(_emailController.text);
    if (emailErr != null) {
  setState(() { _previousStep = _step; _step = 3; _showValidationStep = 3; });
      _formKey.currentState?.validate();
      customSnackBar('Error', emailErr);
      return false;
    }
    final passErr = _validatePassword(_passwordController.text);
    if (passErr != null) {
  setState(() { _previousStep = _step; _step = 4; _showValidationStep = 4; });
      _formKey.currentState?.validate();
      customSnackBar('Error', passErr);
      return false;
    }
    if (_confirmPasswordController.text != _passwordController.text) {
      setState(() { _previousStep = _step; _step = 4; _showValidationStep = 4; });
      _formKey.currentState?.validate();
      customSnackBar('Error', 'Passwords do not match');
      return false;
    }
    return true;
  }

  /// obscureText often expands a tap into a range ending at the last char.
  /// Collapse to the earlier edge (tap position) so the caret lands correctly.
  void _guardObscuredSelection(TextEditingController controller, bool Function() isObscured) {
    if (_fixingObscuredSelection || !isObscured()) return;
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final textLen = controller.text.length;
    final offset = math.min(sel.baseOffset, sel.extentOffset).clamp(0, textLen);
    _fixingObscuredSelection = true;
    controller.selection = TextSelection.collapsed(offset: offset);
    _fixingObscuredSelection = false;
  }

  void _collapseObscuredSelection(TextEditingController controller) {
    void collapse() {
      final sel = controller.selection;
      if (!sel.isValid || sel.isCollapsed) return;
      final textLen = controller.text.length;
      final offset = math.min(sel.baseOffset, sel.extentOffset).clamp(0, textLen);
      _fixingObscuredSelection = true;
      controller.selection = TextSelection.collapsed(offset: offset);
      _fixingObscuredSelection = false;
    }

    // Framework applies selection after onTap; collapse across two frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      collapse();
      WidgetsBinding.instance.addPostFrameCallback((_) => collapse());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrandAppBar: true,
      title: 'Join Anchor World',
      onBack: () => Navigator.of(context).pushReplacementNamed('/signin'),
      child: Column(
        children: [
          Text(
            'Create your account',
            style: AppTextStyles.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'A few details to join the community',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          AuthCard(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: AppColors.surface,
                            backgroundImage: _photoFile != null
                                ? FileImage(_photoFile!)
                                : (_photoUrl != null ? NetworkImage(_photoUrl!) as ImageProvider : null),
                            child: (_photoFile == null && _photoUrl == null)
                                ? const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 36)
                                : null,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final choice = await showModalBottomSheet<String?>(
                              context: context,
                              backgroundColor: AppColors.card,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (ctx) => SafeArea(
                                child: Wrap(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                                      title: Text('Choose from gallery', style: AppTextStyles.ui()),
                                      onTap: () => Navigator.of(ctx).pop('gallery'),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
                                      title: Text('Take a photo', style: AppTextStyles.ui()),
                                      onTap: () => Navigator.of(ctx).pop('camera'),
                                    ),
                                    if (_photoFile != null || _photoUrl != null)
                                      ListTile(
                                        leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                                        title: Text('Remove photo', style: AppTextStyles.ui()),
                                        onTap: () => Navigator.of(ctx).pop('remove'),
                                      ),
                                  ],
                                ),
                              ),
                            );

                            if (choice == 'gallery' || choice == 'camera') {
                              final picker = ImagePicker();
                              final XFile? picked = await picker.pickImage(
                                source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
                                imageQuality: 75,
                              );
                              if (picked != null) setState(() => _photoFile = File(picked.path));
                            } else if (choice == 'remove') {
                              setState(() {
                                _photoUrl = null;
                                _photoFile = null;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.white, width: 2),
                            ),
                            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalSteps, (i) {
                      final active = i == _step;
                      final completed = i < _step;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 9,
                        height: 9,
                        decoration: BoxDecoration(
                          gradient: (active || completed) ? AppColors.brandGradient : null,
                          color: (!active && !completed) ? AppColors.mutedBorder : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 280,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 340),
                      transitionBuilder: (child, anim) {
                        final double dir = (_step >= _previousStep) ? 1.0 : -1.0;
                        int? keyVal;
                        if (child.key is ValueKey<int>) keyVal = (child.key as ValueKey<int>).value;
                        final bool incoming = keyVal == _step;
                        final tween = incoming
                            ? Tween<Offset>(begin: Offset(dir * 0.6, 0), end: Offset.zero)
                            : Tween<Offset>(begin: Offset.zero, end: Offset(-dir * 0.6, 0));
                        return SlideTransition(
                          position: anim.drive(tween),
                          child: FadeTransition(opacity: anim, child: child),
                        );
                      },
                      child: Padding(
                        key: ValueKey<int>(_step),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: double.infinity,
                            child: _buildStepContentForIndex(_step),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: SecondaryButton(
                            label: 'Back',
                            onPressed: () => setState(() {
                              _previousStep = _step;
                              _step = (_step - 1).clamp(0, _totalSteps - 1);
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: PrimaryButton(
                          label: _step < _totalSteps - 1 ? 'Next' : 'Create',
                          loading: _isLoading && _step == _totalSteps - 1,
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() => _showValidationStep = _step);
                                  final ok = _formKey.currentState?.validate() ?? false;
                                  if (!ok) return;
                                  if (_step < _totalSteps - 1) {
                                    setState(() {
                                      _previousStep = _step;
                                      _step = (_step + 1).clamp(0, _totalSteps - 1);
                                      _showValidationStep = null;
                                    });
                                    return;
                                  }
                                  if (!_acceptedTerms) {
                                    customSnackBar(
                                      'Error',
                                      'You must accept the Privacy Policy and Terms of Service to create an account',
                                    );
                                    return;
                                  }
                                  if (_validateAllBeforeSubmit()) _submit();
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
