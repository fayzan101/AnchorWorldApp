import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/socket_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_caches.dart';
import '../utils/custom_snackbar.dart';
import 'blocked_users_screen.dart';
import 'friends_screen.dart';
import 'points_wallet_screen.dart';
import 'referral_screen.dart';
import 'requests_screen.dart';
import 'video_call_history_screen.dart';

/// Settings / secondary destinations — Instagram-style menu.
/// Primary tabs (Feed, Circles, Create, Messages, Profile) stay in the bottom nav.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _name = 'You';
  String _avatarUrl = '';

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  void _loadMe() {
    final cached = AuthService().getCachedProfile();
    if (cached == null) return;
    final name = (cached['full_name'] ?? cached['name'] ?? cached['first_name'] ?? 'You').toString();
    final pic = (cached['profile_picture'] ?? cached['profile_picture_url'] ?? cached['imageUrl'] ?? '').toString();
    setState(() {
      _name = name.isEmpty ? 'You' : name;
      _avatarUrl = _resolveUrl(pic);
    });
  }

  String _resolveUrl(String? path) {
    if (path == null || path.isEmpty || path == 'null') return '';
    final r = path.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/$filename';
    }
    return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/${r.split('/').last}';
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final refreshToken = prefs.getString('refresh_token') ?? '';
    if (authToken.isEmpty && refreshToken.isEmpty) {
      try {
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');
        await prefs.remove('remembered_email');
        await prefs.remove('remember_me');
      } catch (_) {}
      if (!context.mounted) return;
      customSnackBar('Success', 'Logged out', type: SnackType.success);
      Get.offAllNamed('/signin');
      return;
    }

    final doLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 16),
              Text('Log out?', style: AppTextStyles.sectionTitle, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'You’ll need to sign in again to access your circles and messages.',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.mutedBorder),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Stay', style: AppTextStyles.ui(weight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Log out', style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (doLogout != true) return;

    try {
      try {
        await fcmService.unregisterToken();
      } catch (_) {}
      final auth = AuthService();
      final rt = prefs.getString('refresh_token') ?? '';
      if (rt.isNotEmpty) {
        await auth.logout(rt);
      }
      customSnackBar('Success', 'Logged out', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e is Exception ? e.toString().replaceAll('ApiException: ', '') : 'Logout failed',
        type: SnackType.error,
      );
    } finally {
      try {
        await SocketService().disconnect();
      } catch (_) {}
      AppCaches.clearAll();
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      await prefs.remove('remembered_email');
      await prefs.remove('remember_me');
      Get.offAllNamed('/signin');
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: true,
          title: Text(
            'Settings',
            style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Profile summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.mutedBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.chipIdle,
                    backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                    child: _avatarUrl.isEmpty
                        ? Text(
                            _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                            style: AppTextStyles.ui(size: 20, weight: FontWeight.w800, color: AppColors.primary),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name, style: AppTextStyles.ui(size: 17, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Your account', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _SectionLabel('Account'),
            _MenuGroup(
              children: [
                _MenuTile(
                  icon: Icons.stars_outlined,
                  label: 'Plans & Points',
                  subtitle: 'Balance, subscriptions, earn history',
                  onTap: () => _push(context, const PointsWalletScreen()),
                ),
                _MenuTile(
                  icon: Icons.people_outline_rounded,
                  label: 'Connections',
                  subtitle: 'People you’re connected with',
                  onTap: () => _push(context, const FriendsScreen()),
                ),
                _MenuTile(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Connection requests',
                  subtitle: 'Incoming and sent requests',
                  onTap: () => _push(context, const RequestsScreen(currentUserId: 'me')),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionLabel('Activity'),
            _MenuGroup(
              children: [
                _MenuTile(
                  icon: Icons.call_outlined,
                  label: 'Call history',
                  subtitle: 'Voice and video calls',
                  onTap: () => _push(context, const VideoCallHistoryScreen()),
                ),
                _MenuTile(
                  icon: Icons.card_giftcard_outlined,
                  label: 'Invite & earn',
                  subtitle: 'Share your referral code',
                  onTap: () => _push(context, const ReferralScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionLabel('Privacy & safety'),
            _MenuGroup(
              children: [
                _MenuTile(
                  icon: Icons.block_outlined,
                  label: 'Blocked users',
                  subtitle: 'Manage who you’ve blocked',
                  onTap: () => _push(context, const BlockedUsersScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MenuGroup(
              children: [
                _MenuTile(
                  icon: Icons.logout_rounded,
                  label: 'Log out',
                  destructive: true,
                  onTap: () => _logout(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.ui(size: 11, weight: FontWeight.w800, color: AppColors.body),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<Widget> children;
  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: 56, color: AppColors.mutedBorder),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: destructive ? AppColors.chipIdle : AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: destructive ? AppColors.body : AppColors.primary,
        ),
      ),
      title: Text(
        label,
        style: AppTextStyles.ui(
          size: 15,
          weight: FontWeight.w700,
          color: destructive ? AppColors.body : AppColors.ink,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: AppTextStyles.ui(size: 12, color: AppColors.body)),
      trailing: destructive
          ? null
          : const Icon(Icons.chevron_right_rounded, color: AppColors.body, size: 22),
      onTap: onTap,
    );
  }
}
