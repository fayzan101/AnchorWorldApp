import 'package:anchor_heart/models/premium_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Basic + Premium plan fields', () {
    final status = PremiumStatus.fromJson({
      'plan': 'basic',
      'is_basic': true,
      'is_premium': false,
      'can_voice': true,
      'can_video': false,
      'has_unlimited_chat': true,
      'chat_slots_used': 0,
      'chat_slots_max': null,
      'chat_unlock_cost': 20,
      'points_balance': 100,
      'basic_price_usd': 4.99,
      'recommended_basic_product_id': 'basic_monthly',
      'base_price_usd': 9.99,
      'discount_percent': 0,
      'discount_label': 'Starter',
      'discounted_price_usd': 9.99,
      'savings_usd': 0,
      'recommended_product_id': 'premium_monthly',
      'tiers': [],
      'benefits': ['Voice intros'],
    });

    expect(status.plan, 'basic');
    expect(status.isBasic, isTrue);
    expect(status.canVoice, isTrue);
    expect(status.canVideo, isFalse);
    expect(status.hasUnlimitedChat, isTrue);
    expect(status.recommendedBasicProductId, 'basic_monthly');
    expect(status.chatUnlockCost, 20);
  });
}
