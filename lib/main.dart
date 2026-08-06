import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/splash_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/community_onboarding_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/socket_service.dart';
import 'services/deep_link_service.dart';
import 'theme/app_theme.dart';
import 'utils/call_invite_handler.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
  }
  if (Platform.isAndroid) {
    final sdkInt = (await _getAndroidSdkInt());
    if (sdkInt != null && sdkInt >= 33) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  runApp(const MyApp());
}
Future<int?> _getAndroidSdkInt() async {
  try {
    final methodChannel = const MethodChannel('com.anchor.dating/device_info');
    final sdkInt = await methodChannel.invokeMethod<int>('getSdkInt');
    return sdkInt;
  } catch (_) {
    return null;
  }
}
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final deepLinkService = DeepLinkService();
    deepLinkService.initDeepLinkListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      deepLinkService.handleInitialLink();
      SocketService().ensureConnection();
      CallInviteHandler.instance.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallInviteHandler.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    try {
      if (state == AppLifecycleState.resumed) {
        SocketService().connect();
        CallInviteHandler.instance.start();
      } else if (state == AppLifecycleState.detached) {
        // Keep socket while paused so incoming call events still arrive.
        SocketService().disconnect();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      navigatorKey: navigatorKey,
      title: 'Anchor World',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
      initialRoute: '/',
      routes: {
        '/': (ctx) => const SplashScreen(),
        '/welcome': (ctx) => const WelcomeScreen(),
        '/signin': (ctx) => const SignInScreen(),
        '/signup': (ctx) => const SignUpScreen(),
        '/forgot': (ctx) => const ForgotPasswordScreen(),
        '/reset-password': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>?;
          final token = args?['token'] as String? ?? '';
          return ResetPasswordScreen(resetToken: token);
        },
        '/home': (ctx) => const HomeScreen(),
        '/notifications': (ctx) => const NotificationsScreen(),
        '/onboarding': (ctx) => const CommunityOnboardingScreen(),
        '/verify-email': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>?;
          final email = args?['email'] as String? ?? '';
          final fromSignup = args?['fromSignup'] as bool? ?? true;
          return VerifyEmailScreen(email: email, fromSignup: fromSignup);
        },
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>?;
          final peerId = args?['id'] as String? ?? '';
          final peerName = args?['name'] as String? ?? '';
          return MaterialPageRoute(builder: (_) => ChatScreen(currentUserId: 'me', peerId: peerId, peerName: peerName));
        }
        return null;
      },
    );
  }
}
