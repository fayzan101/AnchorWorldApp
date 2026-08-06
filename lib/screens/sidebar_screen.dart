import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/socket_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/app_caches.dart';
import '../utils/open_user_profile.dart';
import 'friends_screen.dart';
import 'requests_screen.dart';
import 'blocked_users_screen.dart';
import 'referral_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Deprecated: prefer [MenuScreen] full-page navigation instead of a drawer.
class SidebarDrawer extends StatelessWidget {
  const SidebarDrawer({Key? key}) : super(key: key);

  Future<void> _openProfile(BuildContext context) async {
    Navigator.of(context).pop();
    await openOwnProfile(context);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openProfile(context),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<Map<String, dynamic>>(
                    future: AuthService().getProfile(),
                    builder: (ctx, snapshot) {
                      String displayName = 'You';
                      String? picUrl;
                      if (snapshot.hasData) {
                        final data = snapshot.data!;
                        displayName = (data['full_name'] ?? data['name'] ?? data['first_name'] ?? data['email'] ?? 'You').toString();
                        picUrl = (data['profile_picture'] ?? data['profile_picture_url'] ?? data['picture'] ?? data['avatar'])?.toString();
                      }
                      final avatar = (picUrl != null && picUrl.isNotEmpty)
                          ? CircleAvatar(radius: 36, backgroundColor: Colors.white, backgroundImage: NetworkImage(picUrl))
                          : const CircleAvatar(radius: 36, backgroundColor: Colors.white, child: Icon(Icons.person, color: AppColors.primary, size: 36));

                      return Column(
                        children: [
                          avatar,
                          const SizedBox(height: 10),
                          Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.person, color: AppColors.primary),
                          title: Text('Profile', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                          onTap: () => _openProfile(context),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.people, color: AppColors.primary),
                          title: Text('Connections', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
                          },
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
                          title: Text('Invite & earn', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()));
                          },
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.primary),
                          title: Text('Connection requests', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RequestsScreen(currentUserId: 'me')),
                            );
                          },
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.block, color: AppColors.primary),
                          title: Text('Blocked users', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                            );
                          },
                        ),
                        const Divider(color: AppColors.mutedBorder, height: 1),
                        const SizedBox(height: 6),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          leading: const Icon(Icons.logout, color: AppColors.body),
                          title: Text('Logout', style: AppTextStyles.ui(size: 16, weight: FontWeight.w600)),
                          onTap: () async {
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
                              Navigator.of(context).pop();
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
                            if (doLogout == true) {
                              Navigator.of(context).pop();
                              final prefs = await SharedPreferences.getInstance();
                              final refreshToken = prefs.getString('refresh_token') ?? '';
                              try {
                                try {
                                  await fcmService.unregisterToken();
                                } catch (_) {}

                                final auth = AuthService();
                                if (refreshToken.isNotEmpty) {
                                  await auth.logout(refreshToken);
                                } else {
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
                          },
                        ),
                      ],
                    ),
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
class SidebarScreen extends StatelessWidget {
  const SidebarScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
              ),
            ),
            title: const Text('Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),
        drawer: const SidebarDrawer(),
      );
}
