import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum SnackType { success, error, warning, info, processing }

String _formatServerMessage(String? rawMsg) {
  if (rawMsg == null || rawMsg.isEmpty) return 'An error occurred';

  try {
    String cleanMsg = rawMsg.trim();
    if (cleanMsg.isEmpty) return 'An error occurred';
    cleanMsg = cleanMsg
        .replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^ApiException:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^DioError\s*\[.*?\]:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^DioException\s*\[.*?\]:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^HttpException:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^ClientException:\s*', caseSensitive: false), '');

    if (cleanMsg.trim().startsWith('{') || cleanMsg.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(cleanMsg);
        if (decoded is Map) {
          final msgKeys = [
            'message',
            'msg',
            'error',
            'detail',
            'details',
            'description',
            'errorMessage',
            'error_description',
          ];
          for (final key in msgKeys) {
            if (decoded.containsKey(key)) {
              final value = decoded[key];
              if (value is String && value.trim().isNotEmpty) {
                cleanMsg = value.trim();
                break;
              }
            }
          }
        } else if (decoded is List && decoded.isNotEmpty) {
          final firstItem = decoded.first;
          if (firstItem is String) {
            cleanMsg = firstItem.trim();
          } else if (firstItem is Map && firstItem.containsKey('message')) {
            cleanMsg = firstItem['message'].toString().trim();
          }
        }
      } catch (_) {}
    }

    cleanMsg = cleanMsg.replaceAll(RegExp(r'<[^>]*>'), '');
    cleanMsg = cleanMsg.trim().replaceAll(RegExp(r'\s+'), ' ');

    final lowerMsg = cleanMsg.toLowerCase();
    // Avoid matching product phrases like "connection request sent".
    final looksLikeNetworkFailure = lowerMsg.contains('socketexception') ||
        lowerMsg.contains('network is unreachable') ||
        lowerMsg.contains('network error') ||
        lowerMsg.contains('host lookup') ||
        lowerMsg.contains('failed host lookup') ||
        lowerMsg.contains('connection refused') ||
        lowerMsg.contains('connection reset') ||
        lowerMsg.contains('connection timed out') ||
        lowerMsg.contains('connection closed') ||
        lowerMsg.contains('failed to connect') ||
        lowerMsg.contains('no internet') ||
        lowerMsg.contains('software caused connection abort') ||
        (lowerMsg.contains('socket') &&
            (lowerMsg.contains('error') || lowerMsg.contains('exception') || lowerMsg.contains('failed')));
    if (looksLikeNetworkFailure) {
      if (lowerMsg.contains('timeout') || lowerMsg.contains('timed out')) {
        return 'Connection timed out. Please check your internet and try again.';
      }
      return 'Network error. Please check your internet connection.';
    }
    if (lowerMsg.contains('500') ||
        lowerMsg.contains('502') ||
        lowerMsg.contains('503') ||
        lowerMsg.contains('internal server')) {
      return 'Server error. Please try again later.';
    }
    if (lowerMsg.contains('401') || lowerMsg.contains('unauthorized')) {
      return 'Authentication failed. Please sign in again.';
    }
    if (lowerMsg.contains('403') || lowerMsg.contains('forbidden')) {
      return "Access denied. You don't have permission to perform this action.";
    }
    if (lowerMsg.contains('404') || lowerMsg.contains('not found')) {
      return 'Requested resource not found.';
    }

    if (cleanMsg.isEmpty || cleanMsg.length < 3) return 'An error occurred';
    cleanMsg = cleanMsg[0].toUpperCase() + cleanMsg.substring(1);
    if (!cleanMsg.endsWith('.') && !cleanMsg.endsWith('!') && !cleanMsg.endsWith('?')) {
      cleanMsg += '.';
    }
    return cleanMsg;
  } catch (_) {
    return 'An error occurred';
  }
}

SnackType resolveSnackType(String titleTxt, String msg) {
  final t = titleTxt.toLowerCase().trim();
  final m = msg.toLowerCase();

  if (t == 'processing') return SnackType.processing;
  if (t == 'success' ||
      t == 'welcome!' ||
      t == 'welcome' ||
      t.contains('joined') ||
      t.contains('posted')) {
    return SnackType.success;
  }
  if (t == 'error' || t == 'failed' || t.contains('fail')) return SnackType.error;
  if (t == 'warning' || t == 'out of stock') return SnackType.warning;
  if (t == 'info' || t == 'almost there' || t == 'city needed' || t == 'join circles') {
    return SnackType.info;
  }

  if (m.contains('success') || m.startsWith('+') && m.contains('point')) {
    return SnackType.success;
  }
  if (m.contains('error') || m.contains('fail') || m.contains('invalid')) {
    return SnackType.error;
  }
  return SnackType.info;
}

({Color bg, Color fg, IconData icon}) _styleFor(SnackType type) {
  switch (type) {
    case SnackType.success:
      return (bg: AppColors.accentMint, fg: AppColors.white, icon: Icons.check_circle_rounded);
    case SnackType.error:
      return (bg: AppColors.danger, fg: AppColors.white, icon: Icons.error_rounded);
    case SnackType.warning:
      return (bg: AppColors.accentGold, fg: AppColors.ink, icon: Icons.warning_amber_rounded);
    case SnackType.processing:
      return (bg: AppColors.ink, fg: AppColors.white, icon: Icons.hourglass_top_rounded);
    case SnackType.info:
      return (bg: AppColors.primary, fg: AppColors.white, icon: Icons.info_rounded);
  }
}

void customSnackBar(
  String titleTxt,
  String msg, {
  SnackPosition position = SnackPosition.BOTTOM,
  SnackType? type,
}) {
  msg = _formatServerMessage(msg);
  final lowerMsg = msg.toLowerCase();

  // Suppress generic network errors that are noise after a successful action
  // (e.g. a background refresh that fails while the user already got a success snack).
  // Only allow them through when the caller explicitly passes type: SnackType.error.
  if (type == null) {
    final isNetworkNoise = lowerMsg.contains('network error') ||
        lowerMsg.contains('failed to connect') ||
        (lowerMsg.contains('socket') && lowerMsg.contains('error')) ||
        lowerMsg.contains('host lookup failed') ||
        lowerMsg.contains('connection refused');
    if (isNetworkNoise) return;
  }

  final bool tooManyAuth = lowerMsg.contains('too many authentication attempts') ||
      lowerMsg.contains('too many attempts') ||
      lowerMsg.contains('too-many-requests') ||
      lowerMsg.contains('too many requests');

  if (tooManyAuth) {
    msg = 'Please try again after a few minutes.';
    titleTxt = 'Please wait';
  }

  final resolved = type ?? resolveSnackType(titleTxt, msg);
  final style = _styleFor(resolved);
  final isProcessing = resolved == SnackType.processing;

  if (Get.isRegistered<GetMaterialApp>() || Get.context != null) {
    Get.snackbar(
      '',
      '',
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      duration: Duration(seconds: isProcessing ? 8 : 3),
      backgroundColor: style.bg,
      colorText: style.fg,
      icon: isProcessing
          ? const Padding(
              padding: EdgeInsets.only(right: 4),
              child: CupertinoActivityIndicator(radius: 11, color: Colors.white),
            )
          : Icon(style.icon, color: style.fg, size: 26),
      snackPosition: position,
      snackStyle: SnackStyle.FLOATING,
      borderRadius: 16,
      boxShadows: [
        BoxShadow(
          color: style.bg.withOpacity(0.35),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      shouldIconPulse: !isProcessing,
      isDismissible: !isProcessing,
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      titleText: Text(
        titleTxt.isEmpty ? _defaultTitle(resolved) : titleTxt,
        style: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: style.fg),
      ),
      messageText: Text(
        msg,
        style: AppTextStyles.ui(size: 14, weight: FontWeight.w500, color: style.fg.withOpacity(0.95)),
      ),
      mainButton: isProcessing
          ? null
          : TextButton(
              onPressed: () => Get.back(),
              child: Text(
                'DISMISS',
                style: AppTextStyles.ui(size: 12, weight: FontWeight.w700, color: style.fg),
              ),
            ),
    );
  } else {
    final context = WidgetsBinding.instance.focusManager.primaryFocus?.context;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: TextStyle(color: style.fg)),
          backgroundColor: style.bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

String _defaultTitle(SnackType type) {
  switch (type) {
    case SnackType.success:
      return 'Success';
    case SnackType.error:
      return 'Error';
    case SnackType.warning:
      return 'Warning';
    case SnackType.processing:
      return 'Processing';
    case SnackType.info:
      return 'Info';
  }
}
