import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../models/point_transaction.dart';
import '../models/premium_status.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/iap_service.dart';
import '../services/point_service.dart';
import '../services/premium_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/empty_state.dart';

class PointsWalletScreen extends StatefulWidget {
  /// When true (home tab), skip local AppBar — parent shell already has one.
  final bool embedded;

  const PointsWalletScreen({super.key, this.embedded = false});

  static void clearCache() {
    _PointsWalletScreenState._balanceCache = null;
    _PointsWalletScreenState._premiumCache = null;
    _PointsWalletScreenState._txCache = null;
    _PointsWalletScreenState._cacheAt = null;
  }

  @override
  State<PointsWalletScreen> createState() => _PointsWalletScreenState();
}

class _PointsWalletScreenState extends State<PointsWalletScreen> {
  final _pointService = PointService();
  final _premiumApi = PremiumService();

  PointsBalance? _balance;
  PremiumStatus? _premium;
  List<PointTransaction> _tx = [];
  bool _loading = true;
  bool _subscribing = false;
  String? _error;
  String? _storePrice;

  bool _howExpanded = false;
  bool _historyExpanded = false;

  static PointsBalance? _balanceCache;
  static PremiumStatus? _premiumCache;
  static List<PointTransaction>? _txCache;
  static DateTime? _cacheAt;
  static const _ttl = Duration(minutes: 3);

  bool get _cacheFresh =>
      _cacheAt != null && DateTime.now().difference(_cacheAt!) < _ttl;

  @override
  void initState() {
    super.initState();
    if (_balanceCache != null && _premiumCache != null && _txCache != null) {
      _balance = _balanceCache;
      _premium = _premiumCache;
      _tx = List<PointTransaction>.from(_txCache!);
      _loading = false;
      _load(silent: _cacheFresh);
    } else {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _balance == null;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _pointService.getBalance(),
        _pointService.getTransactions(limit: 40),
        _premiumApi.getStatus(forceRefresh: !silent),
      ]);
      if (!mounted) return;
      final premium = results[2] as PremiumStatus;
      final balance = results[0] as PointsBalance;
      final tx = (results[1] as PaginatedPointTransactions).items;
      setState(() {
        _balance = balance;
        _tx = tx;
        _premium = premium;
        _loading = false;
        _error = null;
      });
      _balanceCache = balance;
      _premiumCache = premium;
      _txCache = List<PointTransaction>.from(tx);
      _cacheAt = DateTime.now();
      _prefetchStorePrice(premium.recommendedProductId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_balance == null) {
          _error = e is ApiException ? (e.message ?? 'Failed to load wallet') : e.toString();
        }
      });
    }
  }

  Future<void> _prefetchStorePrice(String productId) async {
    try {
      final profile = AuthService().getCachedProfile();
      final uid = (profile?['id'] ?? '').toString();
      if (uid.isNotEmpty) await iapService.logIn(uid);
      final pkg = await iapService.findPackageForProductId(productId);
      final price = iapService.priceStringForPackage(pkg);
      if (mounted && price != null) setState(() => _storePrice = price);
    } catch (_) {}
  }

  Future<void> _ensureIapUser() async {
    try {
      final profile = AuthService().getCachedProfile() ?? await AuthService().getProfile();
      final uid = (profile['id'] ?? '').toString();
      if (uid.isNotEmpty) await iapService.logIn(uid);
    } catch (_) {}
  }

  Future<void> _subscribe({required bool basic}) async {
    setState(() => _subscribing = true);
    try {
      await _ensureIapUser();
      final productId = basic
          ? (_premium?.recommendedBasicProductId ?? 'basic_monthly')
          : (_premium?.recommendedProductId ?? 'premium_monthly');

      if (!iapService.isConfigured) {
        customSnackBar(
          'Store not configured',
          'Add REVENUECAT_IOS_KEY / REVENUECAT_ANDROID_KEY to enable purchases.',
          type: SnackType.info,
        );
        return;
      }

      final package = await iapService.findPackageForProductId(productId);
      if (package == null) {
        throw Exception('${basic ? 'Basic' : 'Premium'} package not found in the store offering');
      }

      await iapService.purchasePackage(package);
      final status = await _premiumApi.confirmPurchase();
      if (!mounted) return;
      setState(() => _premium = status);
      _premiumCache = status;
      await _load(silent: true);
      if (!mounted) return;
      customSnackBar(
        basic ? 'Basic active' : 'Premium active',
        basic ? 'Unlimited chat + voice calls unlocked' : 'Video calls are unlocked',
        type: SnackType.success,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return;
      customSnackBar('Purchase failed', e.message ?? e.toString(), type: SnackType.error);
    } catch (e) {
      if (!mounted) return;
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not subscribe') : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  Future<void> _subscribePremium() => _subscribe(basic: false);
  Future<void> _subscribeBasic() => _subscribe(basic: true);

  Future<void> _restore() async {
    setState(() => _subscribing = true);
    try {
      await _ensureIapUser();
      if (!iapService.isConfigured) {
        customSnackBar('Store not configured', 'RevenueCat keys missing', type: SnackType.info);
        return;
      }
      await iapService.restorePurchases();
      final status = await _premiumApi.confirmPurchase();
      if (!mounted) return;
      setState(() => _premium = status);
      _premiumCache = status;
      await _load(silent: true);
      if (!mounted) return;
      customSnackBar(
        status.isPremium || status.isBasic ? 'Restored' : 'No active subscription',
        status.isPremium
            ? 'Premium is active on this account'
            : status.isBasic
                ? 'Basic is active on this account'
                : 'No Basic or Premium entitlement found',
        type: status.isPremium || status.isBasic ? SnackType.success : SnackType.info,
      );
    } catch (e) {
      if (!mounted) return;
      customSnackBar(
        'Restore failed',
        e is ApiException ? (e.message ?? e.toString()) : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  bool get _isPushedRoute => !widget.embedded;

  String? _daysLeftLabel(DateTime? until) {
    if (until == null) return null;
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return null;
    final days = diff.inDays;
    if (days <= 0) {
      final hours = diff.inHours;
      if (hours <= 0) return 'Expires soon';
      return '$hours hour${hours == 1 ? '' : 's'} left';
    }
    return '$days day${days == 1 ? '' : 's'} left';
  }

  String? _expiryDateLabel(DateTime? until) {
    if (until == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Renews ${months[until.month - 1]} ${until.day}, ${until.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isPushed = _isPushedRoute;
    // Embedded tab: avoid huge navClearance blank gap above FAB; keep modest pad.
    final bottomPad = isPushed
        ? 28.0 + MediaQuery.paddingOf(context).bottom
        : 24.0 + MediaQuery.paddingOf(context).bottom;

    Widget body;
    if (_loading && _balance == null) {
      body = const Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (_error != null && _balance == null) {
      body = EmptyState(
        title: 'Couldn’t load points',
        subtitle: _error!,
        primaryLabel: 'Try again',
        onPrimary: _load,
        icon: Icons.stars_outlined,
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, isPushed ? 8 : 12, 20, bottomPad),
          children: _buildContent(isPushed: isPushed),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: isPushed
              ? AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                  flexibleSpace: Container(
                    decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                  ),
                  iconTheme: const IconThemeData(color: Colors.white),
                  title: Text(
                    'Plans & points',
                    style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
                  ),
                  centerTitle: true,
                )
          : null,
      body: body,
    );
  }

  List<Widget> _buildContent({required bool isPushed}) {
    final bal = _balance?.balance ?? _premium?.pointsBalance ?? 0;
    final premium = _premium;
    final isPremium = premium?.isPremium == true;
    final isBasic = premium?.isBasic == true;
    final discount = premium?.discountPercent ?? 0;
    final price = premium?.discountedPriceUsd ?? 9.99;
    final base = premium?.basePriceUsd ?? 9.99;
    final unlockCost = premium?.chatUnlockCost ?? 50;
    final slotsUsed = premium?.chatSlotsUsed ?? 0;
    final slotsMax = premium?.chatSlotsMax;

    final basicDays = _daysLeftLabel(premium?.basicUntil);
    final premiumDays = _daysLeftLabel(premium?.premiumUntil);
    final activeUntil = isPremium ? premium?.premiumUntil : (isBasic ? premium?.basicUntil : null);
    final activeDays = isPremium ? premiumDays : (isBasic && !isPremium ? basicDays : null);
    final activeExpiry = _expiryDateLabel(activeUntil);
    final hasActivePlan = isPremium || isBasic;
    final activePlanName = isPremium ? 'Premium' : (isBasic ? 'Basic' : null);
    final basicSubtitle = (isBasic && !isPremium && basicDays != null)
        ? 'Unlimited chat + voice calls · $basicDays'
        : 'Unlimited chat + voice calls';
    final premiumSubtitle = isPremium
        ? (premiumDays != null
            ? 'Voice + video calls included · $premiumDays'
            : 'Voice + video calls included')
        : 'Everything in Basic + video calls';

    return [
      if (!isPushed) ...[
        Text(
          hasActivePlan
              ? 'Your $activePlanName plan is active${activeDays != null ? ' · $activeDays' : ''}.'
              : 'Earn points for discounts · Basic & Premium unlock chat and calls',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 16),
      ] else ...[
        Text(
          hasActivePlan
              ? 'Manage your $activePlanName plan and track remaining time.'
              : 'Choose a plan or earn points for chat unlocks and Premium discounts.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 16),
      ],
      if (hasActivePlan && activePlanName != null) ...[
        _CurrentPlanCard(
          planName: activePlanName,
          until: activeUntil,
          daysLabel: activeDays,
          expiryLabel: activeExpiry,
          canVoice: premium?.canVoice == true,
          canVideo: premium?.canVideo == true,
          hasUnlimitedChat: premium?.hasUnlimitedChat == true,
          accent: isPremium ? AppColors.accentGold : AppColors.primary,
        ),
        const SizedBox(height: 16),
      ] else ...[
        _NoPlanCard(),
        const SizedBox(height: 16),
      ],
      _BalanceCard(
        balance: bal,
        discount: discount,
        discountLabel: premium?.discountLabel,
        unlockCost: unlockCost,
        slotsUsed: slotsUsed,
        slotsMax: slotsMax,
        hasUnlimitedChat: premium?.hasUnlimitedChat == true,
      ),
      const SizedBox(height: 22),
      Text('Plans', style: AppTextStyles.sectionTitle),
      const SizedBox(height: 4),
      Text(
        hasActivePlan
            ? 'Your current plan is highlighted below. Remaining time is shown on the card.'
            : 'Choose Basic or Premium. Your active plan will show remaining days here.',
        style: AppTextStyles.caption,
      ),
      const SizedBox(height: 10),
      _PlanCard(
        icon: Icons.mic_rounded,
        iconColor: AppColors.primary,
        iconBg: AppColors.primary.withOpacity(0.12),
        borderColor: isBasic && !isPremium
            ? AppColors.primary.withOpacity(0.45)
            : AppColors.mutedBorder,
        title: 'Basic',
        subtitle: basicSubtitle,
        isCurrent: isBasic && !isPremium,
        currentBadgeLabel: isBasic && !isPremium ? 'CURRENT PLAN' : null,
        benefits: const [
          'Unlimited chat with connections',
          'Voice calls',
          'No 2-chat free limit',
        ],
        footer: isBasic
            ? (isPremium
                ? _ActivePlanFooter(
                    label: 'Included with your Premium plan',
                    daysLabel: premiumDays,
                    expiryLabel: _expiryDateLabel(premium?.premiumUntil),
                    accent: AppColors.accentGold,
                  )
                : _ActivePlanFooter(
                    label: 'You are on Basic',
                    daysLabel: basicDays,
                    expiryLabel: _expiryDateLabel(premium?.basicUntil),
                    accent: AppColors.primary,
                  ))
            : _PlanPriceFooter(
                priceLabel: premium?.basicPriceLabel ?? '\$4.99/mo',
                buttonLabel: 'Get Basic',
                outlined: true,
                loading: _subscribing,
                onPressed: _subscribeBasic,
              ),
      ),
      const SizedBox(height: 12),
      _PlanCard(
        icon: Icons.workspace_premium_rounded,
        iconColor: AppColors.accentGold,
        iconBg: AppColors.accentGold.withOpacity(0.15),
        borderColor: isPremium
            ? AppColors.accentGold.withOpacity(0.55)
            : AppColors.mutedBorder,
        title: 'Premium',
        subtitle: premiumSubtitle,
        isCurrent: isPremium,
        currentBadgeLabel: isPremium ? 'CURRENT PLAN' : null,
        benefits: const [
          'Everything in Basic',
          'Video calls',
          'Points unlock subscription discounts',
        ],
        footer: isPremium
            ? _ActivePlanFooter(
                label: 'You are on Premium',
                daysLabel: premiumDays,
                expiryLabel: _expiryDateLabel(premium?.premiumUntil),
                accent: AppColors.accentGold,
              )
            : _PlanPriceFooter(
                priceLabel: _storePrice ?? '\$${price.toStringAsFixed(2)}/mo',
                struckPrice: discount > 0 ? '\$${base.toStringAsFixed(2)}' : null,
                discountBadge: discount > 0 ? '$discount% off' : null,
                hint: premium?.nextTierPointsNeeded != null &&
                        premium!.nextTierPointsNeeded! > 0
                    ? '${premium.nextTierPointsNeeded} more pts → ${premium.nextTierLabel} discount'
                    : null,
                buttonLabel: isBasic ? 'Upgrade to Premium' : 'Get Premium',
                outlined: false,
                loading: _subscribing,
                onPressed: _subscribePremium,
              ),
      ),
      const SizedBox(height: 8),
      if (hasActivePlan)
        Center(
          child: TextButton(
            onPressed: _subscribing ? null : _restore,
            child: Text(
              'Restore purchases',
              style: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ),
      if (hasActivePlan) const SizedBox(height: 12),
      Text('Premium discount tiers', style: AppTextStyles.sectionTitle),
      const SizedBox(height: 10),
      ...(premium?.tiers ?? const <PremiumTier>[]).map((t) => _TierRow(t)),
      if (premium == null || premium.tiers.isEmpty) ...[
        const _TierRow(
          PremiumTier(
            minPoints: 0,
            discountPercent: 0,
            label: 'Starter',
            priceUsd: 9.99,
            productId: 'premium_monthly',
            unlocked: true,
            current: true,
          ),
        ),
        const _TierRow(
          PremiumTier(
            minPoints: 500,
            discountPercent: 10,
            label: 'Member',
            priceUsd: 8.99,
            productId: 'premium_monthly_10',
            unlocked: false,
            current: false,
          ),
        ),
        const _TierRow(
          PremiumTier(
            minPoints: 1000,
            discountPercent: 20,
            label: 'Active',
            priceUsd: 7.99,
            productId: 'premium_monthly_20',
            unlocked: false,
            current: false,
          ),
        ),
        const _TierRow(
          PremiumTier(
            minPoints: 2000,
            discountPercent: 30,
            label: 'Champion',
            priceUsd: 6.99,
            productId: 'premium_monthly_30',
            unlocked: false,
            current: false,
          ),
        ),
      ],
      const SizedBox(height: 20),
      _CollapsibleSection(
        title: 'How it works',
        expanded: _howExpanded,
        onToggle: () => setState(() => _howExpanded = !_howExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepRow(n: '1', title: 'Earn points', body: 'Join circles, post, comment, connect'),
            _StepRow(
              n: '2',
              title: hasActivePlan ? 'Unlimited chat unlocked' : 'Unlock chat (free)',
              body: hasActivePlan
                  ? 'Your plan includes unlimited chat with connections'
                  : 'Spend $unlockCost pts per person · max 2 chats',
            ),
            _StepRow(
              n: '3',
              title: hasActivePlan ? '$activePlanName benefits' : 'Go Basic or Premium',
              body: isPremium
                  ? 'Voice + video calls included while your plan is active'
                  : isBasic
                      ? 'Voice calls included · upgrade to Premium for video'
                      : 'Unlimited chat · voice · video on Premium',
            ),
            const SizedBox(height: 12),
            Text('How to earn', style: AppTextStyles.ui(size: 14, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            const _EarnRow(label: 'Join a circle', points: '+5'),
            const _EarnRow(label: 'Create a post', points: '+5'),
            const _EarnRow(label: 'Comment on a post', points: '+1'),
            const _EarnRow(label: 'Make a connection', points: '+10'),
            const _EarnRow(label: 'Daily login', points: '+2'),
            const _EarnRow(label: 'Finish onboarding', points: '+20'),
            const _EarnRow(label: 'Successful referral', points: '+25'),
            const SizedBox(height: 8),
            Text(
              'Points are never spent on voice or video calls.',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _CollapsibleSection(
        title: 'History',
        expanded: _historyExpanded,
        onToggle: () => setState(() => _historyExpanded = !_historyExpanded),
        trailingHint: _tx.isEmpty ? null : '${_tx.length}',
        child: _tx.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Earn your first points — join a circle', style: AppTextStyles.body),
              )
            : Column(
                children: _tx.map((t) => _TxTile(tx: t)).toList(),
              ),
      ),
    ];
  }
}

class _CollapsibleSection extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final String? trailingHint;

  const _CollapsibleSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.trailingHint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTextStyles.ui(size: 16, weight: FontWeight.w800)),
                  ),
                  if (trailingHint != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.chipIdle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        trailingHint!,
                        style: AppTextStyles.ui(size: 12, weight: FontWeight.w700, color: AppColors.body),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more_rounded, color: AppColors.body),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balance;
  final int discount;
  final String? discountLabel;
  final int unlockCost;
  final int slotsUsed;
  final int? slotsMax;
  final bool hasUnlimitedChat;

  const _BalanceCard({
    required this.balance,
    required this.discount,
    required this.discountLabel,
    required this.unlockCost,
    required this.slotsUsed,
    required this.slotsMax,
    required this.hasUnlimitedChat,
  });

  @override
  Widget build(BuildContext context) {
    final chatLine = hasUnlimitedChat
        ? 'Unlimited chat with your plan'
        : 'Chat unlock: $unlockCost pts · $slotsUsed/${slotsMax ?? 2} free slots used';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your balance',
            style: AppTextStyles.ui(size: 13, color: AppColors.white.withOpacity(0.85)),
          ),
          const SizedBox(height: 4),
          Text(
            '$balance',
            style: AppTextStyles.display(40, color: AppColors.white, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            discount > 0
                ? '${discountLabel ?? 'Member'} tier · $discount% off Premium'
                : 'Earn 500+ pts for your first Premium discount',
            style: AppTextStyles.ui(size: 13, color: AppColors.white.withOpacity(0.9)),
          ),
          const SizedBox(height: 4),
          Text(
            chatLine,
            style: AppTextStyles.ui(size: 12, color: AppColors.white.withOpacity(0.78)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color borderColor;
  final String title;
  final String subtitle;
  final List<String> benefits;
  final Widget? footer;
  final bool isCurrent;
  final String? currentBadgeLabel;

  const _PlanCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.benefits,
    this.footer,
    this.isCurrent = false,
    this.currentBadgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: isCurrent ? 1.6 : 1),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: AppTextStyles.ui(size: 16, weight: FontWeight.w800)),
                        ),
                        if (currentBadgeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              currentBadgeLabel!,
                              style: AppTextStyles.ui(size: 10, weight: FontWeight.w800, color: iconColor),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accentMint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(b, style: AppTextStyles.ui(size: 13, color: AppColors.body)),
                  ),
                ],
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 6),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _NoPlanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chipIdle,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium_outlined, color: AppColors.body),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No active plan', style: AppTextStyles.ui(size: 15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  'You’re on Free. Get Basic or Premium below to unlock calls.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final String planName;
  final DateTime? until;
  final String? daysLabel;
  final String? expiryLabel;
  final bool canVoice;
  final bool canVideo;
  final bool hasUnlimitedChat;
  final Color accent;

  const _CurrentPlanCard({
    required this.planName,
    required this.accent,
    this.until,
    this.daysLabel,
    this.expiryLabel,
    this.canVoice = false,
    this.canVideo = false,
    this.hasUnlimitedChat = false,
  });

  double get _progress {
    if (until == null) return 0;
    // Assume ~30-day billing window ending at `until`.
    final start = until!.subtract(const Duration(days: 30));
    final total = until!.difference(start).inSeconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(start).inSeconds.clamp(0, total);
    return (elapsed / total).clamp(0.0, 1.0);
  }

  String get _exactRemaining {
    if (until == null) return 'Expiry date unavailable';
    final diff = until!.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    if (days > 0) return '$days day${days == 1 ? '' : 's'} · $hours hr remaining';
    if (diff.inHours > 0) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} remaining';
    final mins = diff.inMinutes.clamp(1, 59);
    return '$mins min remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.16),
            accent.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'CURRENT PLAN',
                  style: AppTextStyles.ui(size: 10, weight: FontWeight.w800, color: AppColors.white),
                ),
              ),
              const Spacer(),
              if (daysLabel != null)
                Text(daysLabel!, style: AppTextStyles.ui(size: 12, weight: FontWeight.w800, color: accent)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  planName == 'Premium' ? Icons.workspace_premium_rounded : Icons.mic_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(planName, style: AppTextStyles.ui(size: 22, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(_exactRemaining, style: AppTextStyles.ui(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
                    if (expiryLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(expiryLabel!, style: AppTextStyles.caption),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (until != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 7,
                backgroundColor: accent.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hasUnlimitedChat) _PerkChip(icon: Icons.chat_bubble_outline, label: 'Unlimited chat'),
              if (canVoice) _PerkChip(icon: Icons.mic_none_rounded, label: 'Voice calls'),
              if (canVideo) _PerkChip(icon: Icons.videocam_outlined, label: 'Video calls'),
              if (!canVideo && planName == 'Basic')
                _PerkChip(icon: Icons.lock_outline, label: 'Video locked'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerkChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PerkChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.ui(size: 11, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ActivePlanFooter extends StatelessWidget {
  final String label;
  final String? daysLabel;
  final String? expiryLabel;
  final Color accent;

  const _ActivePlanFooter({
    required this.label,
    required this.accent,
    this.daysLabel,
    this.expiryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.ui(size: 13, weight: FontWeight.w800, color: AppColors.ink),
                ),
                if (expiryLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    expiryLabel!,
                    style: AppTextStyles.ui(size: 11, weight: FontWeight.w600, color: AppColors.body),
                  ),
                ],
                if (daysLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    daysLabel!,
                    style: AppTextStyles.ui(size: 11, weight: FontWeight.w800, color: accent),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPriceFooter extends StatelessWidget {
  final String priceLabel;
  final String? struckPrice;
  final String? discountBadge;
  final String? hint;
  final String buttonLabel;
  final bool outlined;
  final bool loading;
  final VoidCallback onPressed;

  const _PlanPriceFooter({
    required this.priceLabel,
    this.struckPrice,
    this.discountBadge,
    this.hint,
    required this.buttonLabel,
    required this.outlined,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (struckPrice != null)
              Text(
                struckPrice!,
                style: AppTextStyles.ui(size: 14, color: AppColors.body).copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            Text(
              priceLabel,
              style: AppTextStyles.ui(size: 24, weight: FontWeight.w800, color: AppColors.ink),
            ),
            if (discountBadge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentMint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  discountBadge!,
                  style: AppTextStyles.ui(size: 12, weight: FontWeight.w800, color: AppColors.accentMint),
                ),
              ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint!, style: AppTextStyles.caption),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: outlined
              ? OutlinedButton(
                  onPressed: loading ? null : onPressed,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(48),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.standard,
                    alignment: Alignment.center,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary),
                        )
                      : Align(
                          alignment: Alignment.center,
                          child: Text(
                            buttonLabel,
                            style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.primary),
                          ),
                        ),
                )
              : ElevatedButton(
                  onPressed: loading ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.standard,
                    alignment: Alignment.center,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : Align(
                          alignment: Alignment.center,
                          child: Text(
                            buttonLabel,
                            style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.white),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _TierRow extends StatelessWidget {
  final PremiumTier tier;

  const _TierRow(this.tier);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tier.current ? AppColors.primary.withOpacity(0.06) : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tier.current ? AppColors.primary.withOpacity(0.25) : AppColors.mutedBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            tier.unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: tier.unlocked ? AppColors.accentMint : AppColors.body,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier.label, style: AppTextStyles.ui(weight: FontWeight.w700)),
                Text('${tier.minPoints}+ pts', style: AppTextStyles.caption),
              ],
            ),
          ),
          Text(
            tier.discountPercent == 0 ? 'Full price' : '${tier.discountPercent}% off',
            style: AppTextStyles.ui(
              weight: FontWeight.w800,
              color: tier.discountPercent > 0 ? AppColors.accentGold : AppColors.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String n;
  final String title;
  final String body;

  const _StepRow({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
            child: Text(n, style: AppTextStyles.ui(color: AppColors.white, weight: FontWeight.w800, size: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.ui(weight: FontWeight.w800)),
                Text(body, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  final String label;
  final String points;

  const _EarnRow({required this.label, required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.ui(weight: FontWeight.w600))),
          Text(points, style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.accentMint)),
        ],
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  final PointTransaction tx;

  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final positive = tx.isEarn;
    return Container(
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
            positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: positive ? AppColors.accentMint : AppColors.body,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description?.isNotEmpty == true ? tx.description! : tx.type.replaceAll('_', ' '),
                  style: AppTextStyles.ui(weight: FontWeight.w600, size: 14),
                ),
                Text(
                  '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${tx.amount}',
            style: AppTextStyles.ui(
              weight: FontWeight.w800,
              color: positive ? AppColors.accentMint : AppColors.body,
            ),
          ),
        ],
      ),
    );
  }
}
