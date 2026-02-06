# App Store Connect Rollout Checklist

Updated: 2026-02-06

## 1. Recommended Order
1. Create IAP products and region availability in App Store Connect.
2. Verify purchase, restore, and gating behavior in TestFlight.
3. Add minimum English localization for monetization-related UI.
4. Release globally (Japan free, non-Japan paid model).

Note:
- English support should not be the "very last after release".
- It is fine to do App Store Connect setup first, but complete minimum English before global production rollout.

## 2. App Store Connect Setup Checklist
- Confirm Paid Apps Agreement is accepted (Business section).
- Create a subscription group (example: `Lifelog Premium`).
- Create products:
  - `com.inazumimakoto.lifelog.premium.monthly` (auto-renewable, 1 month)
  - `com.inazumimakoto.lifelog.premium.yearly` (auto-renewable, 1 year)
  - `com.inazumimakoto.lifelog.premium.lifetime` (non-consumable)
- Fill required metadata for each product (display name, description, localization).
- Set availability:
  - JP storefront: unavailable for all paid products.
  - Non-JP storefronts: available.
- Set starting prices (see section 3).
- Submit IAPs for review with app binary.
- Create Sandbox Testers for subscription purchase testing.

## 3. Initial Pricing Proposal (JPY Base)
- Recommended launch pricing:
  - Monthly: `¥200`
  - Yearly: `¥1,800`
  - Lifetime: `¥5,000`

Why this is recommended:
- `¥200 -> ¥1,800` gives a clear yearly incentive.
- Lifetime at `¥3,000` is likely too cheap and may cannibalize subscription revenue.
  - At `¥3,000`, users recover lifetime cost in ~`16.7` months compared with yearly.
  - A safer target is `2.5` to `3.0` years of yearly plan value.
- `¥5,000` keeps lifetime attractive but not dominant (~`2.8` years of yearly).

Adjustment rule after launch:
- If lifetime share is too high, raise lifetime first (e.g. `¥6,000`+).
- If paid conversion is weak, test lower monthly first before lowering lifetime.
- Suggested review timing:
  - Day 14: check trial-to-paid and monthly/yearly mix.
  - Day 30: check lifetime purchase share and churn trend.

## 4. QA Checklist (Japan-based testing)
- Debug build:
  - Settings > Developer section > set storefront to `US`.
  - Verify free limits and locked features in non-premium state.
  - Toggle force premium ON and verify unlock behavior.
- Sandbox purchase test:
  - Use a Sandbox Tester and run real purchase/restore flows.
  - Confirm entitlement state updates correctly after purchase/restore.
- Regression:
  - Switch storefront back to `AUTO`.
  - Confirm JP storefront remains fully unlocked and free.

## 5. Minimum English Scope Before Global Release
- Paywall screen title/feature list/buttons.
- Premium lock messages (habit/countdown/map/letters/diary photos/diary location).
- Purchase error and restore messages.
- App Store product metadata (name/description/promotional text).

## 6. Apple Official References
- Manage app availability by country/region:
  - https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store
- Set IAP availability by country/region:
  - https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-availability-for-in-app-purchases/
- Set subscription availability by country/region:
  - https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription
- Manage subscription pricing:
  - https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
