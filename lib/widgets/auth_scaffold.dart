import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shared elegant shell for auth flows — community look, not dating chrome.
class AuthScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final VoidCallback? onBack;
  final bool showBrandAppBar;
  final bool centerScroll;

  const AuthScaffold({
    super.key,
    required this.child,
    this.title,
    this.onBack,
    this.showBrandAppBar = false,
    this.centerScroll = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: showBrandAppBar
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: onBack != null
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        color: AppColors.ink,
                        onPressed: onBack,
                      )
                    : null,
                title: title != null
                    ? Text(title!, style: AppTextStyles.ui(size: 17, weight: FontWeight.w700))
                    : null,
                centerTitle: true,
                systemOverlayStyle: SystemUiOverlayStyle.dark,
                foregroundColor: AppColors.ink,
              )
            : null,
        body: SafeArea(
          // centerScroll kept for API compatibility; layout always softly centers.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minH = constraints.maxHeight - 52;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minH > 0 ? minH : 0),
                  child: Align(
                    alignment: centerScroll ? const Alignment(0, -0.2) : Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AuthBrandMark extends StatelessWidget {
  final double size;
  /// Soft outer glow for dark splash / welcome backgrounds.
  final bool glow;

  const AuthBrandMark({super.key, this.size = 72, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.22;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (glow) ...[
            BoxShadow(
              color: AppColors.accentMint.withOpacity(0.28),
              blurRadius: 36,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppColors.primary.withOpacity(0.45),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ] else
            BoxShadow(
              color: AppColors.primary.withOpacity(0.22),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: AppColors.brandGradient,
            ),
            child: Icon(Icons.anchor, color: AppColors.white, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.mutedBorder),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showMark;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.showMark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showMark) ...[
          const AuthBrandMark(),
          const SizedBox(height: 20),
          Text(
            'Anchor World',
            style: AppTextStyles.display(22, weight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
        ],
        Text(title, textAlign: TextAlign.center, style: AppTextStyles.screenTitle),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center, style: AppTextStyles.body),
      ],
    );
  }
}

InputDecoration authFieldDecoration({
  required String label,
  String? hint,
  IconData? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefix != null ? Icon(prefix, color: AppColors.primary, size: 22) : null,
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    labelStyle: AppTextStyles.ui(size: 14, color: AppColors.primary, weight: FontWeight.w600),
    hintStyle: AppTextStyles.ui(size: 14, color: AppColors.body.withOpacity(0.55)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.mutedBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.danger, width: 2),
    ),
  );
}
