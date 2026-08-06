import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../network/api_client.dart' show ApiException;
import '../services/block_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/safety_dialogs.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await blockService.listBlocked();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? (e.message ?? 'Failed to load') : e.toString();
      });
    }
  }

  String _name(Map<String, dynamic> item) {
    final user = item['blocked_user'];
    if (user is Map) {
      return (user['full_name'] ?? user['name'] ?? 'Member').toString();
    }
    return 'Member';
  }

  String _userId(Map<String, dynamic> item) {
    final id = item['blocked_id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    final user = item['blocked_user'];
    if (user is Map) return (user['id'] ?? '').toString();
    return '';
  }

  String _avatar(Map<String, dynamic> item) {
    final user = item['blocked_user'];
    if (user is! Map) return '';
    final raw = (user['profile_picture'] ?? '').toString();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  Future<void> _unblock(Map<String, dynamic> item) async {
    final id = _userId(item);
    if (id.isEmpty) return;
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Unblock ${_name(item)}?',
      message: 'They’ll be able to interact with you again on Anchor World.',
      confirmLabel: 'Unblock',
    );
    if (!ok) return;
    try {
      await blockService.unblockUser(id);
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => _userId(e) == id));
      customSnackBar('Unblocked', '${_name(item)} was unblocked', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not unblock') : e.toString(),
        type: SnackType.error,
      );
    }
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
        title: Text('Blocked users', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: AppTextStyles.body),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? EmptyState(
                      title: 'No blocked users',
                      subtitle: 'People you block won’t be able to message or connect with you.',
                      primaryLabel: 'Go back',
                      onPrimary: () => Navigator.of(context).maybePop(),
                      icon: Icons.block,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          final name = _name(item);
                          final avatar = _avatar(item);
                          return Material(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.chipIdle,
                                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                child: avatar.isEmpty
                                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: AppTextStyles.ui(weight: FontWeight.w800))
                                    : null,
                              ),
                              title: Text(name, style: AppTextStyles.ui(weight: FontWeight.w700)),
                              trailing: TextButton(
                                onPressed: () => _unblock(item),
                                child: Text('Unblock', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
