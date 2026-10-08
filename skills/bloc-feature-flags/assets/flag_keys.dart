// Target: lib/core/flags/flag_keys.dart

/// Every remote flag key the app reads. Never inline a key string elsewhere.
///
/// Each dartdoc states: kind (permanent / temporary + removal ticket), what it
/// controls, the value shape and the default. The default itself lives in
/// `flagDefaults`; a test fails if any key here lacks one.
abstract final class FlagKeys {
  /// Temporary launch gate (remove: TICKET-123). New checkout flow.
  /// bool, default false.
  static const newCheckoutEnabled = 'new_checkout_enabled';

  /// Permanent kill switch. Card payments as a payment method.
  /// bool, default true. Turn off with a 0% rollout, never by deleting.
  static const cardPaymentsEnabled = 'card_payments_enabled';

  /// Permanent list. Comma-separated payment method ids to hide, e.g.
  /// `bank_transfer,wallet`. String, default '' (hides nothing).
  static const hiddenPaymentMethods = 'hidden_payment_methods';

  /// Permanent JSON config. `{"min_build": int, "store_url": String}`;
  /// builds below min_build are asked to update. Default inert: min_build 0.
  static const appUpdate = 'app_update';

  /// Temporary experiment (remove: TICKET-456). Onboarding copy variant:
  /// `control` | `short_copy`. Any other value is treated as `control`.
  static const onboardingVariant = 'onboarding_variant';

  /// The registry `FeatureFlags` fetches. Add every new key here too.
  static const all = <String>[
    newCheckoutEnabled,
    cardPaymentsEnabled,
    hiddenPaymentMethods,
    appUpdate,
    onboardingVariant,
  ];
}
