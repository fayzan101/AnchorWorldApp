class PremiumTier {
  final int minPoints;
  final int discountPercent;
  final String label;
  final double priceUsd;
  final String productId;
  final bool unlocked;
  final bool current;

  const PremiumTier({
    required this.minPoints,
    required this.discountPercent,
    required this.label,
    required this.priceUsd,
    required this.productId,
    required this.unlocked,
    required this.current,
  });

  factory PremiumTier.fromJson(Map<String, dynamic> j) {
    return PremiumTier(
      minPoints: int.tryParse('${j['min_points'] ?? 0}') ?? 0,
      discountPercent: int.tryParse('${j['discount_percent'] ?? 0}') ?? 0,
      label: (j['label'] ?? '').toString(),
      priceUsd: double.tryParse('${j['price_usd'] ?? 0}') ?? 0,
      productId: (j['product_id'] ?? 'premium_monthly').toString(),
      unlocked: j['unlocked'] == true,
      current: j['current'] == true,
    );
  }
}

class PremiumStatus {
  final String plan;
  final bool isBasic;
  final bool isPremium;
  final DateTime? premiumUntil;
  final DateTime? basicUntil;
  final bool canVoice;
  final bool canVideo;
  final bool hasUnlimitedChat;
  final int chatSlotsUsed;
  final int? chatSlotsMax;
  final int chatUnlockCost;
  final int pointsBalance;
  final double basicPriceUsd;
  final String recommendedBasicProductId;
  final double basePriceUsd;
  final int discountPercent;
  final String discountLabel;
  final double discountedPriceUsd;
  final double savingsUsd;
  final String recommendedProductId;
  final List<PremiumTier> tiers;
  final int? nextTierPointsNeeded;
  final String? nextTierLabel;
  final List<String> benefits;

  const PremiumStatus({
    required this.plan,
    required this.isBasic,
    required this.isPremium,
    this.premiumUntil,
    this.basicUntil,
    required this.canVoice,
    required this.canVideo,
    required this.hasUnlimitedChat,
    required this.chatSlotsUsed,
    this.chatSlotsMax,
    required this.chatUnlockCost,
    required this.pointsBalance,
    required this.basicPriceUsd,
    required this.recommendedBasicProductId,
    required this.basePriceUsd,
    required this.discountPercent,
    required this.discountLabel,
    required this.discountedPriceUsd,
    required this.savingsUsd,
    required this.recommendedProductId,
    required this.tiers,
    this.nextTierPointsNeeded,
    this.nextTierLabel,
    required this.benefits,
  });

  factory PremiumStatus.fromJson(Map<String, dynamic> j) {
    final tiers = <PremiumTier>[];
    final rawTiers = j['tiers'];
    if (rawTiers is List) {
      for (final e in rawTiers) {
        if (e is Map) tiers.add(PremiumTier.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final benefits = <String>[];
    final rawBenefits = j['benefits'];
    if (rawBenefits is List) {
      for (final e in rawBenefits) {
        final s = e.toString().trim();
        if (s.isNotEmpty) benefits.add(s);
      }
    }
    DateTime? until;
    final rawUntil = j['premium_until'];
    if (rawUntil is String && rawUntil.isNotEmpty) {
      until = DateTime.tryParse(rawUntil)?.toLocal();
    }
    DateTime? basicUntil;
    final rawBasicUntil = j['basic_until'];
    if (rawBasicUntil is String && rawBasicUntil.isNotEmpty) {
      basicUntil = DateTime.tryParse(rawBasicUntil)?.toLocal();
    }
    final next = j['next_tier'] is Map ? Map<String, dynamic>.from(j['next_tier'] as Map) : null;
    PremiumTier? currentTier;
    for (final t in tiers) {
      if (t.current) {
        currentTier = t;
        break;
      }
    }
    final isPremium = j['is_premium'] == true;
    final isBasic = j['is_basic'] == true || isPremium;
    final plan = (j['plan'] ?? (isPremium ? 'premium' : isBasic ? 'basic' : 'free')).toString();
    final slotsMaxRaw = j['chat_slots_max'];
    return PremiumStatus(
      plan: plan,
      isBasic: isBasic,
      isPremium: isPremium,
      premiumUntil: until,
      basicUntil: basicUntil,
      canVoice: j['can_voice'] == true || isBasic,
      canVideo: j['can_video'] == true || isPremium,
      hasUnlimitedChat: j['has_unlimited_chat'] == true || isBasic,
      chatSlotsUsed: int.tryParse('${j['chat_slots_used'] ?? 0}') ?? 0,
      chatSlotsMax: slotsMaxRaw == null ? null : int.tryParse('$slotsMaxRaw'),
      chatUnlockCost: int.tryParse('${j['chat_unlock_cost'] ?? 50}') ?? 50,
      pointsBalance: int.tryParse('${j['points_balance'] ?? 0}') ?? 0,
      basicPriceUsd: double.tryParse('${j['basic_price_usd'] ?? 4.99}') ?? 4.99,
      recommendedBasicProductId:
          (j['recommended_basic_product_id'] ?? 'basic_monthly').toString(),
      basePriceUsd: double.tryParse('${j['base_price_usd'] ?? 9.99}') ?? 9.99,
      discountPercent: int.tryParse('${j['discount_percent'] ?? 0}') ?? 0,
      discountLabel: (j['discount_label'] ?? 'Starter').toString(),
      discountedPriceUsd: double.tryParse('${j['discounted_price_usd'] ?? 9.99}') ?? 9.99,
      savingsUsd: double.tryParse('${j['savings_usd'] ?? 0}') ?? 0,
      recommendedProductId: (j['recommended_product_id'] ?? currentTier?.productId ?? 'premium_monthly').toString(),
      tiers: tiers,
      nextTierPointsNeeded: next == null ? null : int.tryParse('${next['points_needed'] ?? 0}'),
      nextTierLabel: next?['label']?.toString(),
      benefits: benefits.isEmpty
          ? const [
              'Unlock chat with points or upgrade',
              'Basic: unlimited chat + voice',
              'Premium: adds video calls',
            ]
          : benefits,
    );
  }

  String get priceLabel => '\$${discountedPriceUsd.toStringAsFixed(2)}/mo';
  String get basicPriceLabel => '\$${basicPriceUsd.toStringAsFixed(2)}/mo';
}
