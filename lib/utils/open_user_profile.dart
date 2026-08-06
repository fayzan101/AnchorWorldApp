import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../network/api_client.dart' show ApiException;
import '../screens/profile_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'custom_snackbar.dart';

/// Opens the current user's profile in view mode (pencil → edit).
Future<void> openOwnProfile(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
  try {
    final userMap = await AuthService().getProfile();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          profile: Profile.fromJson(userMap),
          isOwnProfile: true,
          hideFollowButton: true,
          onFollow: (_) {},
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    // Fallback to edit screen if profile fetch fails
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen(userId: 'me')),
    );
  }
}

/// Maps API relationship / connection fields to Connect UI state.
({bool connected, bool requested}) _connectionUiState(Map<String, dynamic> userMap, {bool isAlreadyConnected = false}) {
  final raw = (userMap['relationship_status'] ??
          userMap['connection_status'] ??
          userMap['connectionStatus'] ??
          '')
      .toString()
      .toLowerCase()
      .trim();

  final connected = isAlreadyConnected ||
      raw == 'friends' ||
      raw == 'connected' ||
      raw == 'accepted';

  // Backend GET /users/:id uses connection_status: none | pending | following | connected
  // following = outgoing request; pending = incoming request. Search uses pending_sent / connected.
  final requested = connected ||
      raw == 'request_sent' ||
      raw == 'pending_sent' ||
      raw == 'following' ||
      raw == 'pending' ||
      raw == 'pending_received';

  return (connected: connected, requested: requested);
}

/// Opens another member's profile so the user can send a connection request.
Future<void> openUserProfile(
  BuildContext context, {
  required String userId,
  String? fallbackName,
  bool isAlreadyConnected = false,
}) async {
  final id = userId.trim();
  if (id.isEmpty) {
    customSnackBar('Info', 'Profile unavailable', type: SnackType.info);
    return;
  }

  final me = AuthService().getCachedProfile();
  final myId = me?['id']?.toString();
  if (myId != null && myId == id) {
    await openOwnProfile(context);
    return;
  }

  final cached = AuthService().getCachedUser(id);
  if (cached != null) {
    // Fall through to a forced fetch below so feed/request/profile taps all
    // show the same complete profile details instead of stale partial cache.
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );

  try {
    final userMap = await AuthService().getUserById(id, forceRefresh: true);
    final ui = _connectionUiState(userMap, isAlreadyConnected: isAlreadyConnected);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          profile: Profile.fromJson(userMap),
          requested: ui.requested,
          hideFollowButton: ui.connected,
          onFollow: (_) {},
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    customSnackBar(
      'Error',
      e is ApiException ? (e.message ?? 'Could not open profile') : e.toString(),
      type: SnackType.error,
    );
  }
}
