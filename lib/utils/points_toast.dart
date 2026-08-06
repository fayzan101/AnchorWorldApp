import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_caches.dart';
import '../utils/custom_snackbar.dart';

/// Broadcasts points balance changes so Home (and others) update without a manual refresh.
class PointsBalanceBus {
  PointsBalanceBus._();

  /// Latest known balance (null = unknown / reload from API).
  static final ValueNotifier<int?> balance = ValueNotifier<int?>(null);

  /// Bumps whenever points may have changed (spend, earn, purchase).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Call after spend/earn. Prefer passing [newBalance] when the API returns it.
  static void notifyChanged({int? newBalance}) {
    if (newBalance != null) {
      AuthService().updateCachedPointsBalance(newBalance);
      balance.value = newBalance;
    }
    AppCaches.invalidateWallet();
    revision.value = revision.value + 1;
  }
}

class PointsBadge extends StatelessWidget {
  final int? balance;
  final VoidCallback? onTap;

  const PointsBadge({super.key, this.balance, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.white.withOpacity(0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: AppColors.accentGold, size: 18),
                const SizedBox(width: 5),
                Text(
                  balance != null ? '$balance' : 'Pts',
                  style: AppTextStyles.ui(size: 13, color: AppColors.white, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showPointsToast(int awarded, {String? reason}) {
  if (awarded <= 0) return;
  final msg = reason != null && reason.isNotEmpty
      ? '+$awarded Anchor Points — $reason'
      : '+$awarded Anchor Points';
  customSnackBar('Success', msg, type: SnackType.success);
}
