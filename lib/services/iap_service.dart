import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat IAP wrapper. Keys via --dart-define:
/// REVENUECAT_IOS_KEY / REVENUECAT_ANDROID_KEY
class IapService {
  static final IapService _instance = IapService._();
  factory IapService() => _instance;
  IapService._();

  bool _configured = false;

  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY', defaultValue: '');
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY', defaultValue: '');

  bool get isConfigured {
    if (kIsWeb) return false;
    if (Platform.isIOS) return _iosKey.isNotEmpty;
    if (Platform.isAndroid) return _androidKey.isNotEmpty;
    return false;
  }

  Future<void> configure() async {
    if (_configured || !isConfigured) return;
    final apiKey = Platform.isIOS ? _iosKey : _androidKey;
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  Future<void> logIn(String userId) async {
    if (userId.isEmpty) return;
    await configure();
    if (!_configured) return;
    await Purchases.logIn(userId);
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  Future<Offerings?> getOfferings() async {
    await configure();
    if (!_configured) return null;
    return Purchases.getOfferings();
  }

  /// Find package by store product id (e.g. premium_monthly_10).
  Future<Package?> findPackageForProductId(String productId) async {
    final offerings = await getOfferings();
    final current = offerings?.current;
    if (current == null) return null;

    for (final p in current.availablePackages) {
      if (p.storeProduct.identifier == productId || p.identifier == productId) {
        return p;
      }
    }
    // Fallback: first monthly package
    return current.monthly ?? (current.availablePackages.isNotEmpty ? current.availablePackages.first : null);
  }

  Future<CustomerInfo> purchasePackage(Package package) async {
    await configure();
    // purchases_flutter 8.x: purchasePackage returns CustomerInfo
    return Purchases.purchasePackage(package);
  }

  Future<CustomerInfo> restorePurchases() async {
    await configure();
    return Purchases.restorePurchases();
  }

  Future<bool> hasPremiumEntitlement({String entitlementId = 'premium'}) async {
    await configure();
    if (!_configured) return false;
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(entitlementId);
  }

  String? priceStringForPackage(Package? package) {
    return package?.storeProduct.priceString;
  }
}

final iapService = IapService();
