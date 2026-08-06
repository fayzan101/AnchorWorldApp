import 'package:flutter/material.dart';

import '../models/video_call.dart';
import '../network/api_client.dart' show ApiException;
import '../services/premium_service.dart';
import '../services/video_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../screens/points_wallet_screen.dart';
import '../screens/video_call_screen.dart';

/// Silent default length for the API (backend still requires 5 or 10).
const int kDefaultCallMinutes = 5;

/// Start a voice/video call with a known peer — no picker page.
Future<void> startIntroCall({
  required BuildContext context,
  required String calleeId,
  required String calleeName,
  required CallType callType,
  bool isConnected = true,
}) async {
  if (!isConnected) {
    customSnackBar(
      'Connect first',
      '${callType == CallType.voice ? 'Voice' : 'Video'} calls need a mutual connection',
      type: SnackType.info,
    );
    return;
  }
  if (calleeId.isEmpty) return;

  final isVoice = callType == CallType.voice;
  final planLabel = isVoice ? 'Basic' : 'Premium';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isVoice ? 'Voice call' : 'Video call',
        style: AppTextStyles.ui(size: 18, weight: FontWeight.w800),
      ),
      content: Text(
        'Start a ${isVoice ? 'voice' : 'video'} call with $calleeName?',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Start', style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.white)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  try {
    final status = await premiumService.getStatus();
    final allowed = isVoice ? status.canVoice : status.canVideo;
    if (!allowed) {
      if (!context.mounted) return;
      await _showPlanGate(context, isVoice: isVoice, planLabel: planLabel);
      return;
    }
  } catch (_) {
    // Fall through — server will enforce if status fails.
  }

  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    ),
  );

  try {
    final call = await VideoCallService().requestIntro(
      calleeId: calleeId,
      durationMinutes: kDefaultCallMinutes,
      callType: callType,
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // loading
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(call: call, isCaller: true),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // loading
    final msg = e is ApiException ? (e.message ?? 'Could not start call') : e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('block')) {
      customSnackBar(
        'Blocked',
        'You can’t call this user because of a block between you.',
        type: SnackType.info,
      );
    } else if (lower.contains('premium') || lower.contains('basic')) {
      await _showPlanGate(context, isVoice: isVoice, planLabel: planLabel);
    } else {
      customSnackBar('Error', msg, type: SnackType.error);
    }
  }
}

Future<void> _showPlanGate(
  BuildContext context, {
  required bool isVoice,
  required String planLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.mutedBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 18),
          Icon(
            isVoice ? Icons.mic_rounded : Icons.workspace_premium_rounded,
            size: 40,
            color: AppColors.accentGold,
          ),
          const SizedBox(height: 12),
          Text(
            '$planLabel required',
            style: AppTextStyles.ui(size: 18, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            isVoice
                ? 'Voice calls are included with Basic (and Premium).'
                : 'Video calls are included with Premium.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PointsWalletScreen()),
                );
              },
              child: Text(
                'View plans',
                style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
