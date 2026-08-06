class ApiConfig {
  static const String baseUrl = 'https://app.anchorworld.org/api';

  /// Public marketing / policy site.
  static const String marketingSite = 'https://www.anchorworld.org';
  static const String privacyPolicyUrl = '$marketingSite/privacy-policy';
  static const String termsOfServiceUrl = '$marketingSite/terms';
  static const String supportUrl = '$marketingSite/support';
  static const String accountDeletionUrl = '$marketingSite/account-deletion';
  static const String childSafetyUrl = '$marketingSite/child-safety';

  static Map<String, String> get defaultHeaders => {
        'Content-Type': 'multipart/form-data',
        'Accept': 'application/json',
      };

  static Map<String, String> get jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static const int success = 200;
  static const int created = 201;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int notFound = 404;
  static const int serverError = 500;
  static const int defaultTimeout = 30;

  static const String messageKey = 'message';
  static const String dataKey = 'data';
  static const String errorKey = 'error';

  // Auth
  static const String login = '/auth/login';
  static const String refreshToken = '/auth/refresh-token';
  static const String register = '/auth/register';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String resendVerification = '/auth/resend-verification';

  // Profile / users
  static const String profile = '/profile';
  static const String profilePicture = 'https://app.anchorworld.org/uploads';
  static const String profileLocation = '/profile/location';
  static const String users = '/users';
  static const String usersBlocked = '/users/blocked';

  // Notifications
  static const String notificationsFcmToken = '/notifications/fcm-token';
  static const String notificationsToggle = '/notifications/toggle';
  static const String notifications = '/notifications';
  static const String notificationsUnreadCount = '/notifications/unread-count';
  static const String notificationsReadAll = '/notifications/read-all';

  // Reference
  static const String hobbies = '/hobbies';

  // Community
  static const String posts = '/posts';
  static const String postsFeed = '/posts/feed';
  static const String circles = '/circles';
  static const String pointsBalance = '/points/balance';
  static const String pointsTransactions = '/points/transactions';
  static const String premiumStatus = '/premium/status';
  static const String premiumSubscribe = '/premium/subscribe';
  static const String premiumConfirm = '/premium/confirm';
  static const String referralsMe = '/referrals/me';
  static const String referralsApply = '/referrals/apply';
  static const String onboardingCommunity = '/onboarding/community';
  static const String onboardingStatus = '/onboarding/status';
  static const String followsConnections = '/follows/connections';
  static const String followsSent = '/follows/sent';
  static const String followsPending = '/follows/pending';
  static const String videoCalls = '/video-calls';
  static const String locationsCountries = '/locations/countries';
  static const String locationsCities = '/locations/cities';
}
