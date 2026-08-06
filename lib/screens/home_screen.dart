import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chats_list_screen.dart';
import 'circles_screen.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';
import 'own_profile_tab.dart';
import 'points_wallet_screen.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/points_toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _unreadMessagesCount = 0;
  int _unreadNotificationsCount = 0;
  int? _pointsBalance;
  StreamSubscription<void>? _notifSub;
  bool _appliedRouteArgs = false;
  int _profileRefreshTick = 0;

  static const _titles = ['Feed', 'Circles', 'Create', 'Messages', 'Profile'];

  void _onPointsBalanceBus() {
    final hinted = PointsBalanceBus.balance.value;
    if (hinted != null && mounted) {
      setState(() => _pointsBalance = hinted);
    }
    _loadPointsBalance(forceRefresh: hinted == null);
  }

  void _openMenu() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

  void _openPointsWallet() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PointsWalletScreen()),
    ).then((_) => _loadPointsBalance());
  }

  void _applyOpenTabArgs(dynamic args) {
    if (args is! Map) return;
    final tab = args['openTab']?.toString();
    if (tab == 'chat' || tab == 'messages') {
      _currentIndex = 3;
    } else if (tab == 'circles') {
      _currentIndex = 1;
    } else if (tab == 'points') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPointsWallet();
      });
    } else if (tab == 'create') {
      _currentIndex = 2;
    } else if (tab == 'profile') {
      _currentIndex = 4;
    } else if (tab == 'feed') {
      _currentIndex = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PointsBalanceBus.revision.addListener(_onPointsBalanceBus);
    try {
      _applyOpenTabArgs(Get.arguments);
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingScreen = prefs.getString('pending_open_screen');
        if (pendingScreen == 'notifications') {
          try {
            await prefs.remove('pending_open_screen');
          } catch (_) {}
          if (mounted) {
            Navigator.of(context).pushNamed('/notifications');
          }
          return;
        }
        final pending = prefs.getString('pending_open_tab');
        if (pending == 'chat') {
          final chatId = prefs.getString('pending_chat_id') ?? '';
          final chatName = prefs.getString('pending_chat_name') ?? 'Chat';
          try {
            await prefs.remove('pending_open_tab');
            await prefs.remove('pending_chat_id');
            await prefs.remove('pending_chat_name');
          } catch (_) {}
          if (chatId.isNotEmpty && mounted) {
            setState(() => _currentIndex = 3);
            Navigator.of(context).pushNamed(
              '/chat',
              arguments: {'id': chatId, 'name': chatName},
            );
          } else if (mounted) {
            setState(() => _currentIndex = 3);
          }
        } else if (pending == 'circles' && mounted) {
          try {
            await prefs.remove('pending_open_tab');
          } catch (_) {}
          setState(() => _currentIndex = 1);
        } else if (pending == 'points' && mounted) {
          try {
            await prefs.remove('pending_open_tab');
          } catch (_) {}
          _openPointsWallet();
        } else if (pending == 'profile' && mounted) {
          try {
            await prefs.remove('pending_open_tab');
          } catch (_) {}
          setState(() => _currentIndex = 4);
        }
      } catch (_) {}
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount();
      _loadUnreadNotifications();
      _loadPointsBalance();
      try {
        _notifSub = fcmService.onNotificationArrived.listen((_) {
          _loadUnreadCount();
          _loadUnreadNotifications();
        });
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedRouteArgs) return;
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    if (routeArgs is Map && routeArgs['openTab'] != null) {
      _appliedRouteArgs = true;
      final prev = _currentIndex;
      _applyOpenTabArgs(routeArgs);
      if (prev != _currentIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      PointsBalanceBus.revision.removeListener(_onPointsBalanceBus);
    } catch (_) {}
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    try {
      _notifSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await MessageService().getTotalUnreadCount();
      if (mounted) setState(() => _unreadMessagesCount = count);
    } catch (_) {}
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final count = await notificationService.getUnreadCount();
      if (mounted) setState(() => _unreadNotificationsCount = count);
    } catch (_) {}
  }

  Future<void> _loadPointsBalance({bool forceRefresh = false}) async {
    try {
      final cached = AuthService().getCachedProfile();
      if (cached != null && !forceRefresh) {
        final bal = cached['points_balance'];
        final parsed = bal is int ? bal : int.tryParse('${bal ?? ''}');
        if (parsed != null && mounted) {
          setState(() => _pointsBalance = parsed);
        }
      }
      final profile = await AuthService().getProfile(forceRefresh: forceRefresh);
      final bal = profile['points_balance'];
      final parsed = bal is int ? bal : int.tryParse('${bal ?? 0}') ?? 0;
      if (mounted) setState(() => _pointsBalance = parsed);
    } catch (_) {}
  }

  int _createCirclesTick = 0;

  void _goTo(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 2) _createCirclesTick++;
      if (index == 4) _profileRefreshTick++;
    });
    if (index == 3) _loadUnreadCount();
    if (index == 0) _loadPointsBalance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUnreadCount();
      _loadUnreadNotifications();
      _loadPointsBalance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      FeedScreen(
        onOpenCircles: () => _goTo(1),
        onCreatePost: () => _goTo(2),
        onOpenPoints: _openPointsWallet,
      ),
      const CirclesScreen(embedded: true),
      CreatePostScreen(
        onPosted: () => _goTo(0),
        onClose: () => _goTo(0),
        circlesRefreshToken: _createCirclesTick,
      ),
      ChatsListScreen(
        currentUserId: 'me',
        embedded: true,
        onReturnFromChat: () {
          _loadUnreadCount();
          _loadPointsBalance();
        },
      ),
      OwnProfileTab(
        refreshToken: _profileRefreshTick,
        onOpenMenu: _openMenu,
        onPointsChanged: _loadPointsBalance,
      ),
    ];

    // Create manages its own chrome. Profile / Circles / Feed use the shell bar.
    final hideAppBar = _currentIndex == 2;
    final isFeed = _currentIndex == 0;
    final isCircles = _currentIndex == 1;
    final isProfile = _currentIndex == 4;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) _goTo(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        extendBody: true,
        appBar: hideAppBar
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                ),
                leadingWidth: isFeed ? 108 : null,
                leading: isFeed
                    ? Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PointsBadge(
                            balance: _pointsBalance,
                            onTap: _openPointsWallet,
                          ),
                        ),
                      )
                    : isCircles || _currentIndex == 3
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            onPressed: () => _goTo(0),
                          )
                        : isProfile
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                onPressed: () => _goTo(0),
                              )
                            : null,
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Anchor World',
                      style: AppTextStyles.ui(size: 17, weight: FontWeight.w800, color: AppColors.white),
                    ),
                    Text(
                      _titles[_currentIndex],
                      style: AppTextStyles.ui(size: 12, color: AppColors.white.withOpacity(0.8)),
                    ),
                  ],
                ),
                centerTitle: true,
                actions: [
                  if (isProfile)
                    IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      onPressed: _openMenu,
                    )
                  else
                    IconButton(
                      icon: Badge(
                        isLabelVisible: _unreadNotificationsCount > 0,
                        backgroundColor: AppColors.accentGold,
                        textColor: AppColors.ink,
                        label: Text(
                          _unreadNotificationsCount > 99 ? '99+' : '$_unreadNotificationsCount',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                        child: const Icon(Icons.notifications_outlined, color: Colors.white),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                        _loadUnreadNotifications();
                      },
                    ),
                ],
              ),
        body: IndexedStack(index: _currentIndex, children: tabs),
        bottomNavigationBar: Material(
          type: MaterialType.transparency,
          child: _CommunityBottomNav(
            currentIndex: _currentIndex,
            unreadMessages: _unreadMessagesCount,
            onTap: _goTo,
          ),
        ),
      ),
    );
  }
}

class _CommunityBottomNav extends StatelessWidget {
  final int currentIndex;
  final int unreadMessages;
  final ValueChanged<int> onTap;

  const _CommunityBottomNav({
    required this.currentIndex,
    required this.unreadMessages,
    required this.onTap,
  });

  static const double _fabSize = 56;
  static const double _notchRadius = 34;
  static const double _barHeight = 64;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fabBottom = bottomInset + _barHeight - (_fabSize * 0.28);

    return SizedBox(
      height: _barHeight + _fabSize * 0.78 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: _NotchedNavPainter(
                color: AppColors.card,
                shadowColor: AppColors.ink.withOpacity(0.08),
                notchRadius: _notchRadius,
              ),
              child: SizedBox(
                height: _barHeight + bottomInset,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset, top: 6),
                  child: Row(
                    children: [
                      _NavItem(
                        icon: Icons.dynamic_feed_outlined,
                        activeIcon: Icons.home_rounded,
                        label: 'Feed',
                        selected: currentIndex == 0,
                        onTap: () => onTap(0),
                      ),
                      _NavItem(
                        icon: Icons.groups_outlined,
                        activeIcon: Icons.workspaces_rounded,
                        label: 'Circles',
                        selected: currentIndex == 1,
                        onTap: () => onTap(1),
                      ),
                      const SizedBox(width: _fabSize + 10),
                      _NavItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        activeIcon: Icons.forum_rounded,
                        label: 'Messages',
                        selected: currentIndex == 3,
                        badge: unreadMessages,
                        onTap: () => onTap(3),
                      ),
                      _NavItem(
                        icon: Icons.person_outline_rounded,
                        activeIcon: Icons.person_rounded,
                        label: 'Profile',
                        selected: currentIndex == 4,
                        onTap: () => onTap(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: fabBottom,
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Container(
                width: _fabSize,
                height: _fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.38),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: AppColors.surface, width: 3.5),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotchedNavPainter extends CustomPainter {
  final Color color;
  final Color shadowColor;
  final double notchRadius;

  _NotchedNavPainter({
    required this.color,
    required this.shadowColor,
    required this.notchRadius,
  });

  Path _barPath(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final nr = notchRadius;
    final dip = 14.0;

    return Path()
      ..moveTo(0, 0)
      ..lineTo(cx - nr - 16, 0)
      ..cubicTo(cx - nr - 4, 0, cx - nr, dip * 0.4, cx - nr + 6, dip)
      ..arcToPoint(
        Offset(cx + nr - 6, dip),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..cubicTo(cx + nr, dip * 0.4, cx + nr + 4, 0, cx + nr + 16, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _barPath(size);
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant _NotchedNavPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.shadowColor != shadowColor ||
        oldDelegate.notchRadius != notchRadius;
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.body;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  color: color,
                  size: 24,
                ),
                if (badge > 0)
                  Positioned(
                    right: -10,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.ui(
                size: 10,
                weight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
