import 'package:flutter/material.dart';

import '../models/chat_access.dart';
import '../services/message_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/points_toast.dart';
import '../network/api_client.dart' show ApiException;
import '../screens/points_wallet_screen.dart';

Future<ChatAccess?> showChatUnlockSheet({
  required BuildContext context,
  required String peerId,
  required String peerName,
  ChatAccess? initial,
}) async {
  ChatAccess? access = initial;
  var unlocking = false;
  var loadStarted = false;

  return showModalBottomSheet<ChatAccess>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> load() async {
            try {
              final a = await MessageService().getChatAccess(peerId);
              if (!ctx.mounted) return;
              if (a.canMessage || a.unlocked || a.hasUnlimitedChat) {
                Navigator.pop(ctx, a);
                return;
              }
              setModal(() => access = a);
            } catch (e) {
              customSnackBar(
                'Error',
                e is ApiException ? (e.message ?? 'Could not load access') : e.toString(),
                type: SnackType.error,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }

          if (access != null &&
              (access!.canMessage || access!.unlocked || access!.hasUnlimitedChat)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.pop(ctx, access);
            });
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }

          if (access == null) {
            if (!loadStarted) {
              loadStarted = true;
              load();
            }
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }

          final a = access!;
          final slots = a.chatSlotsMax == null
              ? 'Unlimited'
              : '${a.chatSlotsUsed}/${a.chatSlotsMax} slots used';

          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              28 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
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
                const Icon(Icons.lock_outline_rounded, size: 40, color: AppColors.primary),
                const SizedBox(height: 12),
                Text(
                  'Unlock chat with $peerName',
                  style: AppTextStyles.ui(size: 18, weight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Spend ${a.chatUnlockCost} points once to unlock messaging with $peerName. '
                  'Only you spend points — after unlock, both of you can chat freely. '
                  'Free plan: max 2 unlocks. Basic unlocks unlimited chat + voice.',
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  'Your balance: ${a.myPointsBalance} pts · $slots',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (a.canUnlock)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: unlocking
                          ? null
                          : () async {
                              setModal(() => unlocking = true);
                              try {
                                final updated = await MessageService().unlockChat(peerId);
                                PointsBalanceBus.notifyChanged(
                                  newBalance: updated.myPointsBalance,
                                );
                                if (ctx.mounted) Navigator.pop(ctx, updated);
                              } catch (e) {
                                customSnackBar(
                                  'Error',
                                  e is ApiException
                                      ? (e.message ?? 'Could not unlock')
                                      : e.toString(),
                                  type: SnackType.error,
                                );
                                setModal(() => unlocking = false);
                              }
                            },
                      child: unlocking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Spend ${a.chatUnlockCost} points',
                              style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.white),
                            ),
                    ),
                  )
                else
                  Text(
                    a.reason == 'slot_limit'
                        ? 'You’ve used both free chat slots. Upgrade to Basic for unlimited chat.'
                        : a.reason == 'insufficient_points'
                            ? 'You need ${a.chatUnlockCost} points to unlock this chat. '
                                'Your balance is ${a.myPointsBalance} pts. '
                                'Earn more points, upgrade, or wait for $peerName to unlock the chat for both of you.'
                            : a.blocked
                                ? 'You can’t unlock chat because of a block between you.'
                                : 'Chat is locked on the free plan.',
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PointsWalletScreen()),
                    );
                  },
                  child: Text(
                    'View Basic / Premium plans',
                    style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
