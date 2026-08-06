import '../screens/circles_screen.dart';
import '../screens/feed_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/points_wallet_screen.dart';
import '../screens/requests_screen.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/premium_service.dart';
import '../services/profile_controller.dart';
import 'chat_caches.dart';

/// Central invalidation for in-memory app caches (screens + services).
class AppCaches {
  AppCaches._();

  static void clearAuth() {
    AuthService().clearSessionCaches();
  }

  static void clearProfileController() {
    try {
      profileController.clearCache();
    } catch (_) {}
  }

  static void clearRequests() {
    RequestsScreen.clearCache();
  }

  static void clearFeed() {
    FeedScreen.clearCache();
  }

  static void clearCircles() {
    CirclesScreen.clearCache();
  }

  static void clearFriends() {
    FriendsScreen.clearCache();
  }

  static void clearNotifications() {
    NotificationsScreen.clearCache();
  }

  static void clearWallet() {
    PointsWalletScreen.clearCache();
    PremiumService.clearCache();
  }

  static void clearMessagesLegacy() {
    MessageService.clearInMemory();
  }

  static void clearChat() {
    ChatCaches.clearAll();
  }

  /// After creating a post — refresh feed next open.
  static void invalidateAfterPost() {
    clearFeed();
  }

  /// After join/leave circle.
  static void invalidateAfterCircleChange() {
    clearCircles();
    clearFeed();
  }

  /// After follow accept / connection change.
  static void invalidateAfterConnectionChange() {
    clearFriends();
    clearRequests();
    clearFeed();
  }

  /// After points / premium purchase.
  static void invalidateWallet() {
    clearWallet();
  }

  /// After editing own profile (name, photo, bio, topics).
  static void invalidateAfterProfileUpdate() {
    clearProfileController();
    clearAuth();
    // Feed / friends cards may show stale name or avatar from prior fetches.
    clearFeed();
    clearFriends();
  }

  /// Call on logout / account switch.
  static void clearAll() {
    clearAuth();
    clearProfileController();
    clearRequests();
    clearFeed();
    clearCircles();
    clearFriends();
    clearNotifications();
    clearWallet();
    clearMessagesLegacy();
    clearChat();
  }
}
