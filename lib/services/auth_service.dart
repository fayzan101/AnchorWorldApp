import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../network/api_client.dart';
import '../screens/chat_screen.dart';
import '../screens/chats_list_screen.dart';
import 'profile_controller.dart';
import 'notification_service.dart';
import 'iap_service.dart';

class AuthService {
  // Singleton instance so the in-memory cache persists across the app session.
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  final ApiClient _client = apiClient;
  Map<String, dynamic>? _cachedProfile;
  // Cache for individual user profiles fetched via getUserById
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, DateTime> _userCacheAt = {};
  static const Duration _userCacheTtl = Duration(minutes: 10);

  /// Clear in-memory profile + user lookups (does not clear tokens).
  void clearSessionCaches() {
    _cachedProfile = null;
    _userCache.clear();
    _userCacheAt.clear();
  }

  /// Drop one user profile so the next fetch is fresh.
  void invalidateUser(String id) {
    _userCache.remove(id);
    _userCacheAt.remove(id);
  }

  /// Returns a copy of the cached user profile for [id] if present and fresh.
  Map<String, dynamic>? getCachedUser(String id) {
    final at = _userCacheAt[id];
    if (at == null || !_userCache.containsKey(id)) return null;
    if (DateTime.now().difference(at) > _userCacheTtl) {
      invalidateUser(id);
      return null;
    }
    return Map<String, dynamic>.from(_userCache[id]!);
  }

  /// Returns true if a user profile for [id] is currently cached in memory.
  bool isUserCached(String id) => getCachedUser(id) != null;

  /// Returns the cached profile map if present for this app session, or null.
  Map<String, dynamic>? getCachedProfile() => _cachedProfile == null ? null : Map<String, dynamic>.from(_cachedProfile!);

  /// Patch cached `points_balance` after spend/earn so home badge updates without a full refresh.
  void updateCachedPointsBalance(int balance) {
    if (_cachedProfile == null) {
      _cachedProfile = {'points_balance': balance};
      return;
    }
    _cachedProfile = Map<String, dynamic>.from(_cachedProfile!)
      ..['points_balance'] = balance;
  }

  /// Attempts to log in and returns the response data map on success.
  /// Throws [ApiException] on failure.
  /// Attempts login. If [persist] is false, the access token is set in-memory
  /// only and not saved to SharedPreferences (useful when "Remember me" is unchecked).
  Future<Map<String, dynamic>> login(String email, String password, {bool persist = true}) async {
    final body = {
      'email': email.trim(),
      'password': password,
    };

    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post(ApiConfig.login, data: jsonEncode(body), options: options);

    // If the API returned a non-success status code, normalize to ApiException
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    // Expecting JSON body with token in data or similar. Adjust as your API returns.
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Optionally extract token. Support several common key names used by APIs.
      Map<String, dynamic>? inner = (data[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) : null;
      String? token;
      if (inner != null) {
        token = inner['access_token'] ?? inner['accessToken'] ?? inner['token'] ?? inner['accessToken'];
      }
      token ??= data['access_token'] ?? data['accessToken'] ?? data['token'];

      if (token is String && token.isNotEmpty) {
        if (persist) {
          await _client.setAuthToken(token);
          // After setting the auth token, retry any pending FCM token that
          // may have been cached when the device obtained an FCM token
          // prior to the user authenticating.
          try {
            await notificationService.retryPendingToken();
          } catch (_) {}
        } else {
          // keep token only in memory for current run
          apiClient.setAuthTokenInMemory(token);
          // Retry any pending FCM token even when the session is not persisted
          // (e.g. "Remember me" unchecked). The in-memory auth header will
          // allow posting the pending token to succeed for this run.
          try {
            await notificationService.retryPendingToken();
          } catch (_) {}
        }

        try {
          final uid = (inner?['user'] is Map)
              ? (inner!['user']['id'] ?? '').toString()
              : (inner?['id'] ?? data['user']?['id'] ?? '').toString();
          if (uid.isNotEmpty) {
            await iapService.logIn(uid);
          }
        } catch (_) {}
      }

      // Save refresh token if provided
      String? refreshToken;
      if (inner != null) {
        refreshToken = inner['refresh_token'] ?? inner['refreshToken'];
      }
      refreshToken ??= data['refresh_token'] ?? data['refreshToken'];
      if (refreshToken is String && refreshToken.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (persist) {
          await prefs.setString('refresh_token', refreshToken);
        } else {
          // If we are not persisting the session, don't save refresh token
          // to shared prefs so the app won't auto-login on restart.
          await prefs.remove('refresh_token');
        }
      }

      return data;
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Normalize picture URL returned by server.
  ///
  /// Examples:
  /// - '/api/profile/picture/<file>.jpg' -> '<base>/uploads/<file>.jpg'
  /// - 'https://...' -> unchanged
  String _normalizePictureUrl(String raw) {
    if (raw.isEmpty) return raw;
    // If already absolute, return as-is
    // If it's an absolute URL but points to the API picture proxy, convert it to the public uploads path
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      try {
        final uri = Uri.parse(raw);
        final path = uri.path;
        if (path.contains('/api/profile/picture/') || path.contains('/profile/picture/')) {
          var newPath = path.replaceFirst('/api/profile/picture/', '/uploads/');
          newPath = newPath.replaceFirst('/profile/picture/', '/uploads/');
          final newUri = uri.replace(path: newPath);
          return newUri.toString();
        }
        return raw;
      } catch (_) {
        return raw;
      }
    }

    // Convert server path '/api/profile/picture/<file>' to '/uploads/<file>'
    String path = raw;
    final marker = '/api/profile/picture/';
    if (path.startsWith(marker)) {
      final file = path.substring(marker.length);
      // ApiConfig.baseUrl currently ends with '/api', drop that to avoid duplication
      var base = ApiConfig.baseUrl;
      if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
      return '${base}/uploads/$file';
    }

    // If path starts with '/profile/picture/' or '/uploads/' normalize accordingly
    if (path.startsWith('/profile/picture/')) {
      final file = path.substring('/profile/picture/'.length);
      var base = ApiConfig.baseUrl;
      if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
      return '${base}/uploads/$file';
    }

    if (path.startsWith('/uploads/')) {
      var base = ApiConfig.baseUrl;
      if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
      return '${base}${path}';
    }

    // Fallback: join with base host
    var base = ApiConfig.baseUrl;
    if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
    // Ensure leading slash
    if (!path.startsWith('/')) path = '/$path';
    return '${base}$path';
  }

  /// Refreshes access token using a refresh token. Saves new token on success.
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final body = {'refresh_token': refreshToken};
    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post(ApiConfig.refreshToken, data: jsonEncode(body), options: options);

    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      Map<String, dynamic>? inner = (data[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) : null;
      String? token;
      if (inner != null) {
        token = inner['access_token'] ?? inner['accessToken'] ?? inner['token'];
      }
      token ??= data['access_token'] ?? data['accessToken'] ?? data['token'];

      if (token is String && token.isNotEmpty) {
        await _client.setAuthToken(token);
        // After establishing authentication (registration often signs in the user),
        // attempt to post any pending FCM token.
        try {
          await notificationService.retryPendingToken();
        } catch (_) {}
      }

      return data;
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Calls logout endpoint with refresh token.
  Future<void> logout(String refreshToken) async {
    final body = {'refresh_token': refreshToken};
    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post('/auth/logout', data: jsonEncode(body), options: options);
    final status = resp.statusCode ?? 0;
    if (status == ApiConfig.success || status == ApiConfig.created) {
      // Clear stored tokens
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      // Clear session + screen caches (tokens already removed above)
      try {
        // Local clear first so callers of AppCaches.clearAuth are idempotent
        clearSessionCaches();
      } catch (_) {}
      try {
        profileController.clearCache();
      } catch (_) {}
      try {
        // Avoid importing AppCaches here (circular with screens); clear chat owners directly.
        ChatScreen.clearAllCache();
        ChatsListScreen.clearCache();
      } catch (_) {}
      return;
    }

    final bodyData = resp.data;
    String message = resp.statusMessage ?? 'Logout failed';
    if (bodyData is Map<String, dynamic>) {
      if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
        message = bodyData[ApiConfig.messageKey];
      }
    }
    throw ApiException(message, status);
  }

  /// Registers a new user. On success saves tokens (if returned) and returns response.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    required String dateOfBirth,
    required String gender,
    String? referralCode,
  }) async {
    final body = {
      'email': email.trim(),
      'password': password,
      'full_name': fullName,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      if (referralCode != null && referralCode.trim().isNotEmpty)
        'referral_code': referralCode.trim().toUpperCase(),
    };
    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post(ApiConfig.register, data: jsonEncode(body), options: options);

    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      Map<String, dynamic>? inner = (data[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) : null;
      String? token;
      if (inner != null) {
        token = inner['access_token'] ?? inner['accessToken'] ?? inner['token'];
      }
      token ??= data['access_token'] ?? data['accessToken'] ?? data['token'];

      if (token is String && token.isNotEmpty) {
        await _client.setAuthToken(token);
        // When refresh succeeds, ensure any pending FCM token is posted
        // using the newly-updated auth header.
        try {
          await notificationService.retryPendingToken();
        } catch (_) {}
      }

      // Save refresh token if provided
      String? refreshToken;
      if (inner != null) {
        refreshToken = inner['refresh_token'] ?? inner['refreshToken'];
      }
      refreshToken ??= data['refresh_token'] ?? data['refreshToken'];
      if (refreshToken is String && refreshToken.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('refresh_token', refreshToken);
      }

      return data;
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Verifies signup email with the 6-digit code. Saves tokens on success.
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final body = {
      'email': email.trim(),
      'code': code.trim(),
    };
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.post(ApiConfig.verifyEmail, data: jsonEncode(body), options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Verification failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      Map<String, dynamic>? inner =
          (data[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) : null;
      String? token;
      if (inner != null) {
        token = inner['access_token'] ?? inner['accessToken'] ?? inner['token'];
      }
      token ??= data['access_token'] ?? data['accessToken'] ?? data['token'];
      if (token is String && token.isNotEmpty) {
        await _client.setAuthToken(token);
        try {
          await notificationService.retryPendingToken();
        } catch (_) {}
      }
      String? refreshToken;
      if (inner != null) {
        refreshToken = inner['refresh_token'] ?? inner['refreshToken'];
      }
      refreshToken ??= data['refresh_token'] ?? data['refreshToken'];
      if (refreshToken is String && refreshToken.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('refresh_token', refreshToken);
      }
      return data;
    }
    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Resends the signup verification code to [email].
  Future<Map<String, dynamic>> resendVerification({required String email}) async {
    final body = {'email': email.trim()};
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.post(ApiConfig.resendVerification, data: jsonEncode(body), options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 202) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
        }
      }
      throw ApiException(message, status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Sends a forgot-password request to the API with the given email.
  /// Returns the API response map on success or throws [ApiException].
  /// Accepts status codes: 200 (OK), 201 (Created), 202 (Accepted)
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final body = {'email': email.trim()};
    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post(ApiConfig.forgotPassword, data: jsonEncode(body), options: options);

    final status = resp.statusCode ?? 0;
    // Accept 200, 201, and 202 as success status codes
    if (status != ApiConfig.success && status != ApiConfig.created && status != 202) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Resets the user's password using the reset token and new password.
  /// Sends a POST request to /auth/reset-password with token and new password.
  /// Returns the API response map on success or throws [ApiException] on failure.
  /// Accepts status codes: 200 (OK), 201 (Created)
  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final trimmedToken = token.trim();
    // Send the token and password under multiple common field names so we
    // are compatible with various backend implementations/validators.
    final body = {
      'reset_token': trimmedToken,
      'token': trimmedToken,
      'new_password': newPassword,
      'password': newPassword,
    };
    final options = Options(headers: ApiConfig.jsonHeaders);

    final resp = await _client.post(ApiConfig.resetPassword, data: jsonEncode(body), options: options);

    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Retrieves the current user's profile using the authorization header.
  /// Retrieves the current user's profile using the authorization header.
  ///
  /// If [forceRefresh] is false (default) and a profile has already been
  /// fetched during this app session, the cached profile will be returned
  /// instead of making another network request. Pass `forceRefresh: true`
  /// to always fetch a fresh copy from the server.
  Future<Map<String, dynamic>> getProfile({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedProfile != null) return _cachedProfile!;
    // Use the client's Dio instance to perform a GET. ApiClient currently has post;
    // we can use a small wrapper by calling the Dio instance via a new method.
    final resp = await _client.get(ApiConfig.profile);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Normalize nested `data` wrapper if present
      Map<String, dynamic> profileData;
      if (data.containsKey(ApiConfig.dataKey) && data[ApiConfig.dataKey] is Map<String, dynamic>) {
        profileData = Map<String, dynamic>.from(data[ApiConfig.dataKey]);
      } else {
        profileData = Map<String, dynamic>.from(data);
      }
      // Normalize profile picture URL if present. Accept alternate keys
      // such as 'profile_image' or 'profileImage' and store a normalized
      // absolute URL under 'profile_picture' so UI code can rely on it.
      String? rawPic;
      if (profileData.containsKey('profile_picture') && profileData['profile_picture'] != null) rawPic = profileData['profile_picture'].toString();
      if (rawPic == null && profileData.containsKey('profile_image') && profileData['profile_image'] != null) rawPic = profileData['profile_image'].toString();
      if (rawPic == null && profileData.containsKey('profileImage') && profileData['profileImage'] != null) rawPic = profileData['profileImage'].toString();
      if (rawPic == null && profileData.containsKey('imageUrl') && profileData['imageUrl'] != null) rawPic = profileData['imageUrl'].toString();
      if (rawPic != null) {
        final normalizedPic = _normalizePictureUrl(rawPic);
        profileData['profile_picture'] = normalizedPic;
        profileData['profile_image'] = rawPic;
      }

      _cachedProfile = profileData;
      return _cachedProfile!;
    }
    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Updates the current user's profile on the server. The [body] should
  /// contain keys the server expects (e.g. full_name, bio, location, date_of_birth, gender).
  /// On success the cached profile is updated and returned.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    // Make a copy of the body so we can normalize fields without mutating caller data
    final sendBody = Map<String, dynamic>.from(body);
    // Remove fields that are no longer collected in the onboarding wizard
    // to avoid sending stale/empty values to the profile API.
    // Keep `bio` — Edit profile still collects and saves it.
    const removedKeys = ['kids'];
    for (final k in removedKeys) {
      if (sendBody.containsKey(k)) sendBody.remove(k);
    }
    // Ensure interests are sent as a comma-separated string (server expects CSV in many endpoints)
    if (sendBody.containsKey('interests') && sendBody['interests'] != null) {
      final raw = sendBody['interests'];
      if (raw is List) {
        final parts = <String>[];
        for (final e in raw) {
          if (e == null) continue;
          if (e is String) {
            final s = e.trim();
            if (s.isNotEmpty) parts.add(s);
            continue;
          }
          if (e is Map) {
            // pick a sensible label field if present
            final candidates = ['name', 'title', 'interest', 'label', 'value'];
            String? found;
            for (final k in candidates) {
              if (e.containsKey(k) && e[k] != null) {
                found = e[k].toString().trim();
                if (found.isNotEmpty) break;
              }
            }
            if (found == null) {
              for (final v in e.values) {
                if (v != null) {
                  final s = v.toString().trim();
                  if (s.isNotEmpty) {
                    found = s;
                    break;
                  }
                }
              }
            }
            if (found != null && found.isNotEmpty) parts.add(found);
            continue;
          }
          final s = e.toString().trim();
          if (s.isNotEmpty) parts.add(s);
        }
        sendBody['interests'] = parts.join(', ');
      } else if (raw is String) {
        // already a string; trim and keep
        sendBody['interests'] = raw.trim();
      } else {
        // fallback to string conversion
        sendBody['interests'] = raw.toString();
      }
    }
    // Convert height strings to integer inches when present.
    // Accept formats like: "5 ft 9 in", "5 ft", "5'9\"", "69 in", "170 cm", "5.9"
    if (sendBody.containsKey('height') && sendBody['height'] != null) {
      try {
        final raw = sendBody['height'];
        int? inches;
        if (raw is num) {
          inches = raw.toInt();
        } else {
          final s = raw.toString().trim().toLowerCase();

          // centimeters e.g. '170 cm'
          final cmMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*cm\b').firstMatch(s);
          if (cmMatch != null) {
            final cmVal = double.tryParse(cmMatch.group(1) ?? '0') ?? 0;
            inches = (cmVal / 2.54).round();
          } else {
            // feet and inches e.g. "5 ft 9 in", "5'9\"", "5 ft", "5'"
            // Handle apostrophe-style (5'9) first, then 'ft'/'feet' style
            final aposMatch = RegExp(r"^(\d+)'\s*(\d+)?").firstMatch(s);
            final ftInMatch = RegExp(r'^(\d+)\s*(?:ft|feet)\s*(\d+)?\s*(?:in|inches)?').firstMatch(s);
            if (aposMatch != null) {
              final f = int.tryParse(aposMatch.group(1) ?? '0') ?? 0;
              final rem = int.tryParse(aposMatch.group(2) ?? '0') ?? 0;
              inches = f * 12 + rem;
            } else if (ftInMatch != null) {
              final f = int.tryParse(ftInMatch.group(1) ?? '0') ?? 0;
              final rem = int.tryParse(ftInMatch.group(2) ?? '0') ?? 0;
              inches = f * 12 + rem;
            } else {
              // inches only e.g. '69 in'
              final inMatch = RegExp(r'^(\d+)\s*(?:in|inches)\b').firstMatch(s);
              if (inMatch != null) {
                inches = int.tryParse(inMatch.group(1) ?? '0') ?? 0;
              } else {
                // decimal feet e.g. '5.9' where .9 might mean 9 inches or decimal feet
                final decMatch = RegExp(r'^(\d+)\.(\d+) ?').firstMatch(s);
                if (decMatch != null) {
                  final f = int.tryParse(decMatch.group(1) ?? '0') ?? 0;
                  final frac = decMatch.group(2) ?? '';
                  // If fractional part is 1-2 digits and <13 treat as inches
                  final fracVal = int.tryParse(frac.length <= 2 ? frac : frac.substring(0, 2)) ?? -1;
                  if (fracVal >= 0 && fracVal < 13) {
                    inches = f * 12 + fracVal;
                  } else {
                    final asDouble = double.tryParse(s);
                    if (asDouble != null) inches = (asDouble * 12).round();
                  }
                } else {
                  // pure number: could be inches or feet
                  final n = int.tryParse(s);
                  if (n != null) {
                    if (n >= 36) {
                      // treat as inches
                      inches = n;
                    } else if (n >= 4 && n <= 8) {
                      // treat as feet
                      inches = n * 12;
                    }
                  }
                }
              }
            }
          }
        }

        if (inches != null) {
          // Send height as a string (server expects stringified value)
          sendBody['height'] = inches.toString();
        }
      } catch (_) {
        // If parsing fails, leave the original value untouched
      }
    }

    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.put(ApiConfig.profile, data: jsonEncode(sendBody), options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Normalize nested `data` wrapper if present
      Map<String, dynamic> profileData;
      if (data.containsKey(ApiConfig.dataKey) && data[ApiConfig.dataKey] is Map<String, dynamic>) {
        profileData = Map<String, dynamic>.from(data[ApiConfig.dataKey]);
      } else {
        profileData = Map<String, dynamic>.from(data);
      }
      // Merge with existing cached profile to avoid losing fields if API returns a partial object
      if (_cachedProfile != null) {
        _cachedProfile = Map<String, dynamic>.from(_cachedProfile!)..addAll(profileData);
      } else {
        _cachedProfile = profileData;
      }
      return _cachedProfile!;
    }
    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Uploads a profile picture using multipart/form-data with key `profile_picture`.
  /// Accepts a [File] and returns the API response map on success.
  Future<Map<String, dynamic>> uploadProfilePicture(File file) async {
    try {
      final mf = await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last);
      final form = FormData.fromMap({'profile_picture': mf});
      final options = Options(headers: ApiConfig.defaultHeaders);

  // Upload via the authenticated profile picture endpoint so the server
  // can process and return the normalized profile object. Use the
  // relative API path (prefixed by ApiConfig.baseUrl by ApiClient).
  final resp = await _client.post('${ApiConfig.profile}/picture', data: form, options: options);
      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Request failed';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        // Normalize nested `data` wrapper if present. Be defensive: some
        // endpoints return unrelated objects inside `data` (for example
        // { success: true, data: { conversations: [...] } }) which are not
        // the user profile. Prefer using the nested data only when it
        // resembles a profile (contains id or profile picture keys); if not,
        // fall back to the top-level object.
        Map<String, dynamic> profileData;
        if (data.containsKey(ApiConfig.dataKey) && data[ApiConfig.dataKey] is Map<String, dynamic>) {
          final inner = Map<String, dynamic>.from(data[ApiConfig.dataKey]);
          final looksLikeProfile = inner.containsKey('id') || inner.containsKey('profile_picture') || inner.containsKey('profile_image') || inner.containsKey('profileImage') || inner.containsKey('imageUrl') || inner.containsKey('avatar');
          if (looksLikeProfile) {
            profileData = inner;
          } else {
            profileData = Map<String, dynamic>.from(data);
          }
        } else {
          profileData = Map<String, dynamic>.from(data);
        }

        // Merge into cache instead of replacing to avoid wiping other fields
        if (_cachedProfile != null) {
          _cachedProfile = Map<String, dynamic>.from(_cachedProfile!)..addAll(profileData);
        } else {
          _cachedProfile = profileData;
        }

        // Normalize picture fields in the merged cache. Accept alternate keys
        // like 'profile_image' and 'profileImage' and ensure 'profile_picture'
        // contains the normalized absolute URL used by the UI.
        if (_cachedProfile != null) {
          String? rawPic;
          if (_cachedProfile!.containsKey('profile_picture') && _cachedProfile!['profile_picture'] != null) rawPic = _cachedProfile!['profile_picture'].toString();
          if (rawPic == null && _cachedProfile!.containsKey('profile_image') && _cachedProfile!['profile_image'] != null) rawPic = _cachedProfile!['profile_image'].toString();
          if (rawPic == null && _cachedProfile!.containsKey('profileImage') && _cachedProfile!['profileImage'] != null) rawPic = _cachedProfile!['profileImage'].toString();
          if (rawPic == null && _cachedProfile!.containsKey('imageUrl') && _cachedProfile!['imageUrl'] != null) rawPic = _cachedProfile!['imageUrl'].toString();
          if (rawPic != null) {
            _cachedProfile!['profile_picture'] = _normalizePictureUrl(rawPic);
            _cachedProfile!['profile_image'] = rawPic;
          }
        }

        return _cachedProfile!;
      }
      throw ApiException('Invalid response from server', resp.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString());
    }
  }

  /// Fetches a list of user profiles for the browse screen.
  ///
  /// Uses GET with optional query parameters in [query]. Normalizes response
  /// shapes: top-level List, or Map with `data` being a List, or `data.items`.
  /// Returns a List of profile maps on success.
  Future<List<Map<String, dynamic>>> fetchUsers([Map<String, dynamic>? query]) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    // Use GET and pass query params if provided
    final resp = await _client.get(ApiConfig.users, queryParameters: query, options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }
    final data = resp.data;

    // Helper to convert dynamic list items to Map<String, dynamic>
    List<Map<String, dynamic>> toMapList(List list) {
      return list.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }

    // 1) top-level list
    if (data is List) {
      final res = toMapList(data);
      for (final it in res) {
        if (it.containsKey('profile_picture') && it['profile_picture'] != null) {
          it['profile_picture'] = _normalizePictureUrl(it['profile_picture'].toString());
        }
      }
      return res;
    }

    // 2) object with data: { items: [...], pagination: {...} }
    if (data is Map<String, dynamic>) {
      final d = data[ApiConfig.dataKey];
      if (d is List) {
        final res = toMapList(d);
        for (final it in res) {
          if (it.containsKey('profile_picture') && it['profile_picture'] != null) {
            it['profile_picture'] = _normalizePictureUrl(it['profile_picture'].toString());
          }
        }
        return res;
      }
      if (d is Map<String, dynamic> && d.containsKey('items') && d['items'] is List) {
        final res = toMapList(d['items'] as List);
        for (final it in res) {
          if (it.containsKey('profile_picture') && it['profile_picture'] != null) {
            it['profile_picture'] = _normalizePictureUrl(it['profile_picture'].toString());
          }
        }
        return res;
      }
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Fetches users and returns both items and pagination metadata when
  /// available. Returns a Map with keys:
  /// - 'items': List<Map<String,dynamic>>
  /// - 'pagination': Map<String,dynamic>? (may be null)
  Future<Map<String, dynamic>> fetchUsersPaginated([Map<String, dynamic>? query]) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.get(ApiConfig.users, queryParameters: query, options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;

    List<Map<String, dynamic>> items = [];
    Map<String, dynamic>? pagination;

    List<Map<String, dynamic>> toMapList(List list) {
      return list.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }

    if (data is List) {
      items = toMapList(data);
    } else if (data is Map<String, dynamic>) {
      // data: [...] or data: { items: [...], pagination: {...} }
      final d = data[ApiConfig.dataKey];
      if (d is List) {
        items = toMapList(d);
      } else if (d is Map<String, dynamic>) {
        if (d.containsKey('items') && d['items'] is List) items = toMapList(d['items'] as List);
        if (d.containsKey('pagination') && d['pagination'] is Map<String, dynamic>) pagination = Map<String, dynamic>.from(d['pagination']);
      }
      // also support top-level pagination
      if (pagination == null && data.containsKey('pagination') && data['pagination'] is Map<String, dynamic>) {
        pagination = Map<String, dynamic>.from(data['pagination']);
      }
    }

    for (final it in items) {
      if (it.containsKey('profile_picture') && it['profile_picture'] != null) {
        it['profile_picture'] = _normalizePictureUrl(it['profile_picture'].toString());
      }
    }

    return {
      'items': items,
      'pagination': pagination,
    };
  }

  /// Fetch a single user by id using GET /users/{id}.
  /// Returns a normalized profile map on success.
  Future<Map<String, dynamic>> getUserById(String id, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = getCachedUser(id);
      if (cached != null) return cached;
    }
    final resp = await _client.get('${ApiConfig.users}/$id');
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      Map<String, dynamic> profileData;
      if (data.containsKey(ApiConfig.dataKey) && data[ApiConfig.dataKey] is Map<String, dynamic>) {
        profileData = Map<String, dynamic>.from(data[ApiConfig.dataKey]);
      } else {
        profileData = Map<String, dynamic>.from(data);
      }

      if (profileData.containsKey('profile_picture') && profileData['profile_picture'] != null) {
        profileData['profile_picture'] = _normalizePictureUrl(profileData['profile_picture'].toString());
      }
      _userCache[id] = Map<String, dynamic>.from(profileData);
      _userCacheAt[id] = DateTime.now();
      return Map<String, dynamic>.from(profileData);
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }

  /// Fetch partner qualities from /partner-qualities endpoint
  /// Returns the response which should contain a list of qualities with id and name
  Future<dynamic> getPartnerQualities() async {
    final resp = await _client.get('/partner-qualities');
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Support both { data: [...] } and { qualities: [...] } responses
      if (data.containsKey(ApiConfig.dataKey)) {
        return data[ApiConfig.dataKey];
      } else if (data.containsKey('qualities')) {
        return data['qualities'];
      } else {
        return data;
      }
    }

    return data;
  }

  /// Fetch relationship goals from /relationship-goals endpoint
  /// Returns the response which should contain a list of goals with id and name
  Future<dynamic> getRelationshipGoals() async {
    final resp = await _client.get('/relationship-goals');
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Support both { data: [...] } and { goals: [...] } responses
      if (data.containsKey(ApiConfig.dataKey)) {
        return data[ApiConfig.dataKey];
      } else if (data.containsKey('goals')) {
        return data['goals'];
      } else {
        return data;
      }
    }

    return data;
  }

  /// Fetch hobbies from /hobbies endpoint
  /// Returns the response which should contain a list of hobbies with id and name
  Future<dynamic> getHobbies() async {
    final resp = await _client.get('/hobbies');
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      // Support both { data: [...] } and { hobbies: [...] } responses
      if (data.containsKey(ApiConfig.dataKey)) {
        return data[ApiConfig.dataKey];
      } else if (data.containsKey('hobbies')) {
        return data['hobbies'];
      } else {
        return data;
      }
    }

    return data;
  }

  /// Report a user using PUT /users/{id}
  /// Sends report data to the server to flag inappropriate user behavior
  Future<Map<String, dynamic>> reportUser(String userId, {String? reason, String? description}) async {
    final body = {
      'reported': true,
      if (reason != null && reason.isNotEmpty) 'report_reason': reason,
      if (description != null && description.isNotEmpty) 'report_description': description,
    };

    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.put('${ApiConfig.users}/$userId', data: jsonEncode(body), options: options);

    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to report user';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) message = err;
          else if (err is Map && err.values.isNotEmpty) message = err.values.first.toString();
        }
      }
      throw ApiException(message, status);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) {
      Map<String, dynamic>? result = (data[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) : null;
      result ??= Map<String, dynamic>.from(data);
      return result;
    }

    throw ApiException('Invalid response from server', resp.statusCode);
  }
}

