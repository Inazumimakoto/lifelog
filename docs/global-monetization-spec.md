# Global Monetization Spec

Updated: 2026-02-06

## 1. Goal
- Keep Japan free.
- Offer paid plans outside Japan.
- Use a low-friction freemium model to reduce early churn.

## 2. Scope
- iOS app: `lifelog`
- In-app gating only. No ad SDK integration.
- Existing JP users remain fully free.

## 3. Monetization Model
- Region rule:
  - Japan storefront (`JP`): all features unlocked (free).
  - Non-Japan storefront: free tier + premium unlock.
- Premium products:
  - Auto-renewable subscription (at least one plan).
  - Lifetime unlock (non-consumable).

## 4. Free vs Premium (Non-Japan)
- Free:
  - Habit registration: up to 3 active habits.
  - Countdown registration: up to 1 item.
  - Diary photo upload: up to 3 photos per day.
  - Schedule calendar, diary, tasks, AI export, health: available.
- Premium:
  - Habit grass/heatmap displays.
  - Review calendar map view.
  - Letter to the Future.
  - Letter to Loved One (shared letters).
  - Diary photo upload: up to 10 photos per day.
  - Unlimited habits/countdowns.

## 5. UX Policy
- Do not hard-block all app usage for non-paying users.
- Show paywall only when users hit a gated action.
- Keep core daily utility flows (calendar/task/diary) always usable.
- Do not add ads.

## 6. Technical Design
- Add `MonetizationService` (StoreKit-based):
  - Detect storefront country.
  - Resolve entitlement state from current transactions.
  - Load purchasable products.
  - Handle purchase and restore.
  - Provide feature flags/limits used by UI.
- Add `PremiumPaywallView`:
  - Product list
  - Purchase action
  - Restore action
- Apply feature gates at entry points:
  - Habits/Countdown add actions
  - Review map tab
  - Letter feature screens
  - Habit heatmap sections

## 7. App Store Connect Setup
- Create products:
  - Subscription SKU(s)
  - Lifetime unlock SKU
- Set availability:
  - Non-JP regions: products available
  - JP: products unavailable (Japan remains free)
- Keep app availability global (or staged rollout by country as needed).

## 8. Data/Behavior Rules
- If user exceeds free cap after losing premium:
  - Existing items remain visible/editable.
  - Creation of new items is blocked until count is within free cap or premium restored.
- Storefront source of truth:
  - Apple storefront country, not GPS location.

## 9. Non-Goals (Current Phase)
- No web paywall.
- No ads or ad-removal SKU.
- No AI quota-based monetization.

## 10. Open Items
- Final product IDs for StoreKit.
- Exact subscription lineup (monthly/yearly).
- Price points by region.
