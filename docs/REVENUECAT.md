# RevenueCat Basic + Premium setup

Anchor World uses RevenueCat for iOS (StoreKit) and Android (Play Billing).

## Entitlements
| Id | Unlocks |
|----|---------|
| `basic` | Unlimited chat + voice intros |
| `premium` | Everything Basic has + guided video intros |

Backend treats an active `premium` entitlement as including Basic access even if `basic` is not separately granted.

## Products

### Basic
| Store product id | Notes |
|------------------|-------|
| `basic_monthly` | Attach to entitlement `basic` |

### Premium (attach all to entitlement `premium`)

| Points tier | Discount | Store product id |
|-------------|----------|------------------|
| 0–499 | 0% | `premium_monthly` |
| 500+ | 10% | `premium_monthly_10` |
| 1000+ | 20% | `premium_monthly_20` |
| 2000+ | 30% | `premium_monthly_30` |

Put Basic + Premium products in the RevenueCat offering named `default`.

Optional: also attach Premium products to the `basic` entitlement in RC so store restores are consistent; Anchor’s API still grants Basic when Premium is active.

## Flutter keys
Build with:

```
--dart-define=REVENUECAT_IOS_KEY=appl_xxx
--dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
```

## Backend env
```
REVENUECAT_API_KEY=sk_xxx
REVENUECAT_WEBHOOK_SECRET=whsec_xxx
REVENUECAT_ENTITLEMENT_ID=premium
REVENUECAT_BASIC_ENTITLEMENT_ID=basic
```

## Webhook
Point RevenueCat webhooks to:
`POST https://app.anchorworld.org/api/premium/webhook`

Authorization header / Bearer token must match `REVENUECAT_WEBHOOK_SECRET`.

## App user id
After login the app calls `Purchases.logIn(anchorUserId)` so webhooks and `POST /premium/confirm` map to the same user.

## Chat unlock (free plan)
- Both users need ≥ 20 points balance (temporary; raise later)
- Initiator spends 20 points once per pair (`POST /messages/unlock/:userId`)
- Max 2 unlocked partners while on Free
- Basic / Premium: unlimited chat (no spend)
