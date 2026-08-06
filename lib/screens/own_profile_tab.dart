import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'profile_detail_screen.dart';

/// Own-profile tab content for the Instagram-style home shell.
class OwnProfileTab extends StatefulWidget {
  final int refreshToken;
  final VoidCallback onOpenMenu;
  final VoidCallback? onPointsChanged;

  const OwnProfileTab({
    super.key,
    required this.refreshToken,
    required this.onOpenMenu,
    this.onPointsChanged,
  });

  @override
  State<OwnProfileTab> createState() => _OwnProfileTabState();
}

class _OwnProfileTabState extends State<OwnProfileTab> {
  Profile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OwnProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _profile == null;
      _error = null;
    });
    try {
      final cached = AuthService().getCachedProfile();
      if (cached != null && mounted && _profile == null) {
        setState(() {
          _profile = Profile.fromJson(cached);
          _loading = false;
        });
      }
      final data = await AuthService().getProfile();
      if (!mounted) return;
      setState(() {
        _profile = Profile.fromJson(data);
        _loading = false;
      });
      widget.onPointsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_error != null && _profile == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ProfileDetailScreen(
      key: ValueKey(_profile!.id + (_profile!.bio) + '${_profile!.postCount}'),
      profile: _profile!,
      isOwnProfile: true,
      hideFollowButton: true,
      embedded: true,
      onOpenMenu: widget.onOpenMenu,
      onFollow: (_) {},
      onProfileUpdated: _load,
    );
  }
}
