import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Notification preferences: delete all, mark all read, push on/off.
class NotificationSettingsScreen extends StatefulWidget {
  final bool pushEnabled;
  final bool hasNotifications;
  final bool hasUnread;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onDeleteAll;
  final Future<bool> Function(bool enabled) onTogglePush;

  const NotificationSettingsScreen({
    super.key,
    required this.pushEnabled,
    required this.hasNotifications,
    required this.hasUnread,
    required this.onMarkAllRead,
    required this.onDeleteAll,
    required this.onTogglePush,
  });

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late bool _pushEnabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pushEnabled = widget.pushEnabled;
  }

  Future<void> _togglePush(bool enabled) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pushEnabled = enabled;
    });
    final ok = await widget.onTogglePush(enabled);
    if (!mounted) return;
    if (!ok) setState(() => _pushEnabled = !enabled);
    setState(() => _busy = false);
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete all notifications?', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800)),
        content: Text('This cannot be undone.', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete all', style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.onDeleteAll();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Notification settings',
          style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              secondary: Icon(
                _pushEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                color: AppColors.primary,
              ),
              title: Text('Push notifications', style: AppTextStyles.ui(size: 15, weight: FontWeight.w700)),
              subtitle: Text(
                _pushEnabled ? 'Alerts are on' : 'Alerts are off',
                style: AppTextStyles.caption,
              ),
              value: _pushEnabled,
              activeColor: AppColors.primary,
              onChanged: _busy ? null : _togglePush,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                ListTile(
                  enabled: widget.hasUnread && !_busy,
                  leading: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
                  title: Text('Mark all as read', style: AppTextStyles.ui(size: 15, weight: FontWeight.w700)),
                  subtitle: Text(
                    widget.hasUnread ? 'Clear unread badges' : 'You’re all caught up',
                    style: AppTextStyles.caption,
                  ),
                  onTap: (!widget.hasUnread || _busy)
                      ? null
                      : () async {
                          await widget.onMarkAllRead();
                          if (mounted) Navigator.pop(context);
                        },
                ),
                const Divider(height: 1, color: AppColors.mutedBorder),
                ListTile(
                  enabled: widget.hasNotifications && !_busy,
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: Text('Delete all notifications', style: AppTextStyles.ui(size: 15, weight: FontWeight.w700)),
                  subtitle: Text(
                    widget.hasNotifications ? 'Remove everything from this list' : 'No notifications to delete',
                    style: AppTextStyles.caption,
                  ),
                  onTap: (!widget.hasNotifications || _busy) ? null : _confirmDeleteAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
