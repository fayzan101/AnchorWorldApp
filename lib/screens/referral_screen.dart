import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../network/api_client.dart' show ApiException;
import '../services/referral_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/empty_state.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  ReferralInfo? _info;
  bool _loading = true;
  String? _error;
  final _shareButtonKey = GlobalKey();

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
      final info = await referralService.getMine();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? (e.message ?? e.toString()) : e.toString();
      });
    }
  }

  Future<void> _copy() async {
    final code = _info?.referralCode ?? '';
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    customSnackBar('Copied', 'Referral code copied', type: SnackType.success);
  }

  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    if (origin.left.isNaN || origin.top.isNaN || origin.width <= 0 || origin.height <= 0) {
      return null;
    }
    return origin;
  }

  Future<void> _share() async {
    final info = _info;
    if (info == null || info.referralCode.isEmpty) {
      customSnackBar('Error', 'No referral code yet — pull to refresh', type: SnackType.error);
      return;
    }
    final text = info.shareLink.isNotEmpty
        ? 'Join me on Anchor World! Use my invite code ${info.referralCode}\n${info.shareLink}'
        : 'Join me on Anchor World! Use my invite code ${info.referralCode}';

    try {
      final origin = _shareOrigin();
      if (origin != null) {
        await Share.share(text, subject: 'Anchor World invite', sharePositionOrigin: origin);
      } else {
        await Share.share(text, subject: 'Anchor World invite');
      }
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      customSnackBar(
        'Copied',
        'Share plugin not ready — stop the app and run again (full restart)',
        type: SnackType.info,
      );
    } catch (e) {
      try {
        await Share.share(text);
        return;
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        customSnackBar('Copied', 'Could not open share sheet — invite text copied', type: SnackType.info);
      }
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
        title: Text('Invite & earn', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null && _info == null
              ? EmptyState(
                  title: 'Couldn’t load invites',
                  subtitle: _error!,
                  primaryLabel: 'Retry',
                  onPrimary: _load,
                  icon: Icons.card_giftcard_outlined,
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      Text('Share Anchor World', style: AppTextStyles.screenTitle),
                      const SizedBox(height: 6),
                      Text(
                        'You earn ${_info?.referrerReward ?? 100} pts when a friend finishes onboarding. They get ${_info?.refereeReward ?? 50} pts too.',
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          children: [
                            Text('Your invite code', style: AppTextStyles.ui(size: 13, color: AppColors.white.withOpacity(0.85))),
                            const SizedBox(height: 8),
                            Text(
                              _info?.referralCode ?? '—',
                              style: AppTextStyles.ui(size: 32, weight: FontWeight.w800, color: AppColors.white),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _copy,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white70),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    icon: const Icon(Icons.copy_rounded, size: 18),
                                    label: const Text('Copy'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    key: _shareButtonKey,
                                    onPressed: _share,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppColors.primaryDeep,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                                    label: const Text('Share'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: _StatCard(label: 'Invited', value: '${_info?.invitedCount ?? 0}')),
                          const SizedBox(width: 10),
                          Expanded(child: _StatCard(label: 'Completed', value: '${_info?.completedCount ?? 0}')),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('How it works', style: AppTextStyles.sectionTitle),
                      const SizedBox(height: 10),
                      const _HowRow(n: '1', text: 'Share your invite code or link'),
                      const _HowRow(n: '2', text: 'Friend signs up with that code'),
                      const _HowRow(n: '3', text: 'They finish onboarding — you both earn points'),
                      const SizedBox(height: 8),
                      Text(
                        'Your invite code stays the same. Share it anytime — it won’t change when you reopen this screen.',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: 22),
                      Text('Your invites', style: AppTextStyles.sectionTitle),
                      const SizedBox(height: 10),
                      if ((_info?.invites ?? []).isEmpty)
                        Text('No invites yet — share your code to get started.', style: AppTextStyles.body)
                      else
                        ..._info!.invites.map(
                          (i) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.mutedBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  i.status == 'completed' ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                                  color: i.status == 'completed' ? AppColors.accentMint : AppColors.accentGold,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    i.refereeName?.isNotEmpty == true ? i.refereeName! : 'Friend',
                                    style: AppTextStyles.ui(weight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  i.status == 'completed' ? 'Completed' : 'Pending',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.ui(size: 24, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _HowRow extends StatelessWidget {
  final String n;
  final String text;

  const _HowRow({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
            child: Text(n, style: AppTextStyles.ui(size: 12, weight: FontWeight.w800, color: AppColors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.ui(size: 14, color: AppColors.body))),
        ],
      ),
    );
  }
}
