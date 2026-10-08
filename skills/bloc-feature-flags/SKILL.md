---
name: bloc-feature-flags
description: 'Use when adding, reading, renaming or removing a remote feature flag in a Flutter/flutter_bloc app; gating a feature or merging it dark behind a launch gate; wiring a kill switch; choosing flag defaults; setting up an A/B test or variant; deciding when flags refresh; or reviewing flag code. Vendor-agnostic: Firebase Remote Config, PostHog, LaunchDarkly, Statsig or an in-house endpoint behind one port.'
---

# Bloc feature flags

## Why

A remote flag is a production switch that a console edit can flip for every user at once. The code around it decides what happens when the vendor is unreachable, when someone deletes the flag, when a value has the wrong type, or when a new key ships without a default. Get those wrong and a kill switch that was meant to keep a broken payment method closed silently reopens it. The rules below make every one of those cases fall back to a value you chose on purpose.

## Files

| File | Role |
| --- | --- |
| `lib/core/flags/flag_keys.dart` (`assets/flag_keys.dart`) | `FlagKeys`: every key as a constant, plus `FlagKeys.all` |
| `lib/core/flags/flag_defaults.dart` (`assets/flag_defaults.dart`) | `flagDefaults`: the safe in-app value for every key |
| `lib/core/flags/feature_flags.dart` (`assets/feature_flags.dart`) | `FlagsSourcePort` (vendor adapter) and `FeatureFlags` (snapshot + typed reads) |
| `test/core/flags/flag_defaults_test.dart` (`assets/flag_defaults_test.dart`) | fails on a key without a default, bad naming, wrong default shape, broken fallback |

## Rules

1. One registry. Every key is a constant on `FlagKeys` with a dartdoc stating kind, purpose, value shape and default. No key strings at call sites. Why: renames and removals become compile errors, and the dartdoc is the inventory.
2. **One safe default per key in `flagDefaults`.** Launch gates `false`, kill switches `true`, lists `''`, JSON inert, variants `'control'`. Why: the default is what users get before the first fetch, offline, and whenever the vendor omits the key. It must be the value that cannot hurt anyone, not the value you hope to ship.
3. Desired values live in the vendor console, never in the defaults. Why: baking "on" into the app means you cannot turn it off for users on old builds.
4. Read through `FeatureFlags`, never the vendor SDK. Why: the vendor sits behind `FlagsSourcePort`, so tests use a fake and switching vendors touches one adapter.
5. Gate at the entry point. Check the flag where the feature starts (route guard or redirect, the section builder on the home screen, the cubit method that starts the flow), not inside a shared widget. Why: a shared widget gated deep down shows up half-enabled on some other screen.
6. Decide permanent or temporary at creation. Temporary flags (launch gates, experiments) name their removal ticket in the dartdoc. Why: a launch gate that outlives its launch is dead code with a remote trigger.
7. **Kill switches are turned off with a 0% rollout (or a targeting rule serving `false`), never by deactivating or deleting the flag.** Why: a deactivated or deleted flag disappears from the vendor response, the app falls back to the default, and the default of a kill switch is `true`. The feature you meant to stop comes back.
8. Never assume an instant flip. Flags refresh on cold start, after login, on resume and on a foreground poll. Why: users on a screen keep the old value until the next refresh; plan rollouts and incident responses around minutes, not seconds.

## Naming grammar

`snake_case`, `<feature>_<what>`:

| Kind | Pattern | Default | Example |
| --- | --- | --- | --- |
| Launch gate (temporary) | `<feature>_enabled` | `false` | `new_checkout_enabled` |
| Kill switch (permanent) | `<feature>_enabled` | `true` | `card_payments_enabled` |
| List | `hidden_<things>` / `<feature>_allowlist` | `''` (no effect) | `hidden_payment_methods` |
| JSON config | `<feature>` | inert JSON string | `app_update` |
| Experiment | `<feature>_variant` | `'control'` | `onboarding_variant` |

Booleans always end in `_enabled`; never `is_`, `enable_` or `_flag`. Lists are comma-separated strings. JSON configs document their shape in the dartdoc. The test enforces the mechanical parts.

## Reading flags

`FeatureFlags` holds the last fetched snapshot and answers synchronously, so a build method or a cubit can read it without awaiting:

```dart
final flags = sl<FeatureFlags>();

flags.getBool(FlagKeys.newCheckoutEnabled);            // bool
flags.getList(FlagKeys.hiddenPaymentMethods);          // List<String>
flags.getJson(FlagKeys.appUpdate)['min_build'];        // Map<String, Object?>
flags.getVariant(FlagKeys.onboardingVariant, const {'short_copy'}); // or 'control'
```

Per key, a read returns the remote value if it is present and the right type, otherwise the default. A failed fetch keeps the previous snapshot. A bool delivered as the string `'true'` is accepted, since some vendors only send strings.

Wire the vendor once:

```dart
final class RemoteFlagsSource implements FlagsSourcePort {
  RemoteFlagsSource(this._api);
  final ApiClient _api;

  @override
  Future<Map<String, Object?>> fetch(Iterable<String> keys) async {
    final res = await _api.get('/flags', query: {'keys': keys.join(',')});
    return (res.data! as Map).cast<String, Object?>();
  }
}

sl.registerSingleton(FeatureFlags(RemoteFlagsSource(sl()), onError: reportFlagError));
```

## Gating at the entry point

A cubit that starts a flow:

```dart
class CheckoutEntryCubit extends Cubit<CheckoutEntry> {
  CheckoutEntryCubit(this._flags) : super(const CheckoutEntry.legacy());
  final FeatureFlags _flags;

  void open() => emit(_flags.getBool(FlagKeys.newCheckoutEnabled)
      ? const CheckoutEntry.redesigned()
      : const CheckoutEntry.legacy());
}
```

With go_router, a `redirect` on the feature's route works the same way: read the flag, send users to the old route or a "not available" page when it is off. Do not hide a button and leave the route open; deep links and notifications reach routes directly.

Screens that should react to a flip while open listen to `FeatureFlags` (it is a `ChangeNotifier`) in the cubit that owns the decision, and remove the listener in `close()`.

## Refresh moments

```dart
class _AppState extends State<App> {
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final flags = sl<FeatureFlags>();
    flags.reload(); // cold start
    _lifecycle = AppLifecycleListener(onResume: flags.reload);
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => flags.reload());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }
  // build() omitted
}
```

Also call `reload()` after login (and after logout), because targeting usually depends on the user identity. Overlapping calls share one fetch. Stop the poll while the app is in the background if your vendor bills per request.

Anything that must be decided before the first frame (a forced update, a maintenance block) either runs on the defaults until the snapshot arrives and re-checks on every change, or waits for `reload()` with a short timeout. Never block startup on the vendor indefinitely.

## A/B tests

Experiments reuse the same keys and the same safe-default rule:

- Two arms: a plain `<feature>_enabled` bool, where `false` is control.
- Three or more arms: a `<feature>_variant` string read with `getVariant(key, knownArms)`. Unknown values, typos and retired arms are `control`, so a console mistake never shows an untested screen.
- Log exposure (the arm a user actually saw) at the point the UI renders that arm, through the analytics port, so analysis does not count users who never reached the screen.
- An experiment flag is temporary: when it ends, ship the winner as plain code and delete the key, its default and the vendor flag.

## Adding a flag

1. Add the constant to `FlagKeys` with its dartdoc, and to `FlagKeys.all`.
2. Add the safe default to `flagDefaults`.
3. Create the flag in the vendor console in every environment, with a description.
4. Gate at the entry point; add a test for both values of the gate.
5. If temporary, link the removal ticket in the dartdoc.

Removing one is the reverse, in this order: ship the build without the read, wait until old builds are a negligible share, then delete it in the console.

## Gotchas

- **Deactivating a kill switch to "turn it off".** It reopens the feature (rule 7). The test `a kill switch missing from the vendor reopens` documents exactly this.
- **A key in `FlagKeys` but not in `FlagKeys.all`** is never fetched and always reads its default. The registry test parses the source to catch it.
- **Default set to the desired value "just for launch".** Old builds keep that value forever; you lose the ability to turn the feature off for them.
- **Per-environment drift.** Staging and production consoles diverge. Keep one list of keys (this registry) and check each environment against it, by script if your vendor has an API.
- **Reading flags in `build()` of a shared widget.** The same widget renders differently on screens the flag owner never looked at.
- **Assuming the poll runs in the background.** Mobile OSes suspend timers; resume is the refresh that matters.

## Review checklist

- [ ] New key is a `FlagKeys` constant with a dartdoc (kind, purpose, shape, default) and is in `FlagKeys.all`.
- [ ] `flagDefaults` has the safe value: gate `false`, kill switch `true`, list `''`, inert JSON, variant `'control'`.
- [ ] No vendor SDK calls or key strings outside the adapter and the registry.
- [ ] The gate sits at the entry point (route redirect, section builder, flow-starting cubit), and the route is closed too, not only the button.
- [ ] Temporary flags name a removal ticket.
- [ ] Kill switch runbook says 0% rollout, never deactivate or delete.
- [ ] Code does not assume a flip lands instantly; refresh happens on cold start, login, resume and a foreground poll.
- [ ] Variants default to `control` for unknown values; exposure is logged where the arm renders.
- [ ] `flag_defaults_test.dart` passes.
