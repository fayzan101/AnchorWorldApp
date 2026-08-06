import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();

  factory DeepLinkService() => _instance;

  DeepLinkService._internal();

  StreamSubscription? _deepLinkSubscription;
  final AppLinks _appLinks = AppLinks();

  void initDeepLinkListener() {
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        unawaited(_handleDeepLink(uri));
      },
      onError: (err) {},
    );
  }

  Future<void> handleInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        await _handleDeepLink(initialUri);
      }
    } catch (e) {}
  }

  Future<void> _storeReferralCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_referral_code', cleaned);
    } catch (_) {}
  }

  Future<void> _handleDeepLink(Uri uri) async {
    try {
      // Custom scheme: anchor://invite/CODE  (host=invite, path=/CODE)
      if (uri.scheme == 'anchor' && uri.host == 'invite') {
        final code = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : (uri.queryParameters['code'] ?? uri.queryParameters['ref'] ?? '');
        if (code.isNotEmpty) {
          await _storeReferralCode(code);
          Get.offAllNamed('/signup');
        }
        return;
      }

      final inviteIdx = uri.pathSegments.indexOf('invite');
      if (inviteIdx >= 0 && inviteIdx + 1 < uri.pathSegments.length) {
        final code = uri.pathSegments[inviteIdx + 1];
        await _storeReferralCode(code);
        Get.offAllNamed('/signup');
        return;
      }
      final ref = uri.queryParameters['ref'] ?? uri.queryParameters['referral'] ?? '';
      if (ref.isNotEmpty) {
        await _storeReferralCode(ref);
        Get.offAllNamed('/signup');
        return;
      }

      String token = uri.queryParameters['token'] ??
          uri.queryParameters['reset_token'] ??
          uri.queryParameters['resetToken'] ??
          uri.queryParameters['code'] ??
          '';
      if (token.isEmpty && uri.fragment.isNotEmpty) {
        try {
          final fragParams = Uri.splitQueryString(uri.fragment);
          token = fragParams['token'] ??
              fragParams['reset_token'] ??
              fragParams['resetToken'] ??
              fragParams['code'] ??
              '';
        } catch (_) {}
      }
      if (token.isEmpty && uri.path.contains('reset-password') && uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.isNotEmpty && last != 'reset-password') {
          token = last;
        }
      }

      if (token.isEmpty) return;
      if (uri.scheme == 'anchor' && uri.host == 'reset-password') {
        Get.offAllNamed('/reset-password', arguments: {'token': token});
        return;
      }
      if (uri.scheme == 'https' && uri.path.contains('reset-password')) {
        Get.offAllNamed('/reset-password', arguments: {'token': token});
        return;
      }
    } catch (e) {}
  }

  void dispose() {
    _deepLinkSubscription?.cancel();
  }
}
