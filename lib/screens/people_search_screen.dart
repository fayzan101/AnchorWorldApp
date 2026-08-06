import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/profile.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/people_search_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/interest_tags_chips.dart';
import 'profile_detail_screen.dart';

class PeopleSearchScreen extends StatefulWidget {
  final String? initialQuery;

  const PeopleSearchScreen({super.key, this.initialQuery});

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  final Set<String> _connecting = {};
  final Set<String> _requested = {};

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialQuery ?? '').trim();
    if (initial.isNotEmpty) {
      _ctrl.text = initial;
      _query = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(initial));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _results = [];
        _error = null;
        _loading = false;
      }
    });
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await peopleSearchService.searchPeople(query: q);
      final me = AuthService().getCachedProfile()?['id']?.toString();
      final filtered = items.where((u) => (u['id']?.toString() ?? '') != me).toList();
      if (!mounted) return;
      setState(() {
        _results = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? (e.message ?? 'Search failed') : e.toString();
        _results = [];
      });
    }
  }

  String _statusOf(Map<String, dynamic> user) {
    final id = user['id']?.toString() ?? '';
    if (_requested.contains(id)) return 'pending_sent';
    return (user['relationship_status'] ?? user['connection_status'] ?? 'none').toString();
  }

  Future<void> _connect(Map<String, dynamic> user) async {
    final id = user['id']?.toString() ?? '';
    if (id.isEmpty || _connecting.contains(id)) return;
    final status = _statusOf(user);
    if (status == 'connected' || status == 'friends' || status == 'pending_sent' || status == 'request_sent') {
      return;
    }

    setState(() => _connecting.add(id));
    try {
      await followService.follow(id);
      if (!mounted) return;
      setState(() {
        _requested.add(id);
        user['relationship_status'] = 'pending_sent';
      });
      customSnackBar('Sent', 'Connection request sent', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e.toString().replaceFirst('Exception: ', ''),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _connecting.remove(id));
    }
  }

  Future<void> _openProfile(Map<String, dynamic> user) async {
    final id = user['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final status = _statusOf(user);
    final requested = status == 'pending_sent' ||
        status == 'request_sent' ||
        status == 'connected' ||
        status == 'friends';
    final hide = status == 'connected' || status == 'friends';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          profile: Profile.fromJson(user),
          requested: requested,
          hideFollowButton: hide,
          onFollow: (pid) {
            setState(() {
              _requested.add(pid);
              user['relationship_status'] = 'pending_sent';
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Find people', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (v) {
                final q = v.trim();
                if (q.length >= 2) _search(q);
              },
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.body),
                        onPressed: () {
                          _ctrl.clear();
                          _onQueryChanged('');
                          _focus.requestFocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.mutedBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.mutedBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_query.trim().length < 2 && !_loading) {
      return EmptyState(
        title: 'Search the community',
        subtitle: 'Find members by name and send a connection request.',
        primaryLabel: 'Type a name',
        onPrimary: () => _focus.requestFocus(),
        icon: Icons.person_search_rounded,
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null) {
      return EmptyState(
        title: 'Search failed',
        subtitle: _error!,
        primaryLabel: 'Try again',
        onPrimary: () => _search(_query),
        icon: Icons.wifi_off_rounded,
      );
    }

    if (_results.isEmpty) {
      return EmptyState(
        title: 'No people found',
        subtitle: 'Try a different name spelling.',
        primaryLabel: 'Clear',
        onPrimary: () {
          _ctrl.clear();
          _onQueryChanged('');
          _focus.requestFocus();
        },
        icon: Icons.person_off_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final user = _results[i];
        return _PersonTile(
          user: user,
          status: _statusOf(user),
          connecting: _connecting.contains(user['id']?.toString()),
          onOpen: () => _openProfile(user),
          onConnect: () => _connect(user),
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final String status;
  final bool connecting;
  final VoidCallback onOpen;
  final VoidCallback onConnect;

  const _PersonTile({
    required this.user,
    required this.status,
    required this.connecting,
    required this.onOpen,
    required this.onConnect,
  });

  String _avatarUrl(String raw) {
    if (raw.isEmpty || raw == 'null') return '';
    final r = raw.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    final base = ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '');
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '$base/$filename';
    }
    return '$base/${r.split('/').last}';
  }

  @override
  Widget build(BuildContext context) {
    final name = (user['full_name'] ?? user['name'] ?? 'Member').toString();
    final bio = (user['bio'] ?? '').toString().trim();
    final city = (user['city'] ?? '').toString().trim();
    final age = user['age'];
    final avatar = _avatarUrl((user['profile_picture'] ?? user['imageUrl'] ?? '').toString());
    final interests = <String>[];
    final rawInterests = user['interests'];
    if (rawInterests is List) {
      for (final e in rawInterests) {
        final s = e.toString().trim();
        if (s.isNotEmpty) interests.add(s);
      }
    }

    final connected = status == 'connected' || status == 'friends';
    final pending = status == 'pending_sent' || status == 'request_sent';
    final received = status == 'pending_received' || status == 'request_received';

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.mutedBorder),
            boxShadow: AppColors.cardShadow,
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: CircleAvatar(
                  backgroundColor: AppColors.chipIdle,
                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  child: avatar.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: AppTextStyles.ui(size: 22, weight: FontWeight.w800, color: AppColors.primary),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.ui(size: 16, weight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.body, size: 20),
                      ],
                    ),
                    if ((age is num && age > 0) || city.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (age is num && age > 0) '${age.toInt()}',
                          if (city.isNotEmpty) city,
                        ].join(' · '),
                        style: AppTextStyles.caption,
                      ),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.ui(size: 13, color: AppColors.body, height: 1.35),
                      ),
                    ],
                    if (interests.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InterestTagsDisplay(labels: interests, maxVisible: 3),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ConnectChip(
                        connected: connected,
                        pending: pending,
                        received: received,
                        loading: connecting,
                        onPressed: connected || pending ? null : onConnect,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectChip extends StatelessWidget {
  final bool connected;
  final bool pending;
  final bool received;
  final bool loading;
  final VoidCallback? onPressed;

  const _ConnectChip({
    required this.connected,
    required this.pending,
    required this.received,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    IconData icon;

    if (connected) {
      label = 'Connected';
      bg = AppColors.accentMint.withOpacity(0.12);
      fg = AppColors.accentMint;
      icon = Icons.check_circle_rounded;
    } else if (pending) {
      label = 'Request sent';
      bg = AppColors.chipIdle;
      fg = AppColors.body;
      icon = Icons.hourglass_top_rounded;
    } else if (received) {
      label = 'Respond in Requests';
      bg = AppColors.accentGold.withOpacity(0.15);
      fg = AppColors.primaryDeep;
      icon = Icons.mark_email_unread_outlined;
    } else {
      label = 'Connect';
      bg = AppColors.primary;
      fg = AppColors.white;
      icon = Icons.person_add_alt_1_rounded;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: loading
              ? SizedBox(
                  width: 72,
                  height: 18,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(label, style: AppTextStyles.ui(size: 13, weight: FontWeight.w800, color: fg)),
                  ],
                ),
        ),
      ),
    );
  }
}
