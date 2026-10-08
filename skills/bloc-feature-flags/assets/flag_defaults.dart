// Target: lib/core/flags/flag_defaults.dart
import 'package:app/core/flags/flag_keys.dart';

/// In-app value for every key, used until the first fetch lands and whenever
/// the vendor omits a key (flag deleted, deactivated, network down).
///
/// Always the SAFE value: launch gates off, kill switches on, lists empty,
/// JSON inert, variants `control`. The desired value is set in the vendor
/// console, never baked in here.
const Map<String, Object> flagDefaults = {
  FlagKeys.newCheckoutEnabled: false,
  FlagKeys.cardPaymentsEnabled: true,
  FlagKeys.hiddenPaymentMethods: '',
  FlagKeys.appUpdate: '{"min_build":0,"store_url":""}',
  FlagKeys.onboardingVariant: 'control',
};
