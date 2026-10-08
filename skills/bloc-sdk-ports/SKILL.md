---
name: bloc-sdk-ports
description: Use when adding or wrapping a third-party SDK in a flutter_bloc app, such as analytics, crash reporting, HTTP (Dio), url_launcher, share_plus, storage, push or remote config; or when tests hit MissingPluginException, a widget calls FirebaseCrashlytics.instance or another static SDK singleton, events carry emails or tokens, startup waits on SDK init, or you need to swap or add a vendor. Covers ports, adapters, no-op and recording fakes, get_it registration and privacy redaction.
---

# SDK ports

A vendor SDK called from a cubit or widget welds the app to that vendor, drags platform channels into every test, and lets anyone send anything to a third party.
A port is a small interface the app owns, written in the app's vocabulary. One adapter file implements it with the SDK. Everything else depends on the port.

What that buys:

- Swapping or adding a vendor means writing one adapter, without touching features.
- Cubit and widget tests use a recording fake instead of platform channels, so they never see `MissingPluginException` or need `setMockMethodCallHandler`.
- The surface stays narrow. The app uses five calls of a 200-method SDK; the port has those five.
- The port decides what can leave the device, so redaction and allowlists live in one place.

Assets (copy into the app, imports use `package:app/...`):

| Asset | Path in app |
|---|---|
| `assets/analytics_port.dart` | `lib/core/analytics/analytics_port.dart` |
| `assets/noop_analytics.dart` | `lib/core/analytics/noop_analytics.dart` |
| `assets/recording_analytics.dart` | `lib/core/analytics/recording_analytics.dart` |
| `assets/fan_out_analytics.dart` | `lib/core/analytics/fan_out_analytics.dart` |
| `assets/crash_reporter_port.dart` | `lib/core/crash/crash_reporter_port.dart` |
| `assets/url_launcher_port.dart` | `lib/core/platform/url_launcher_port.dart` |
| `assets/share_port.dart` | `lib/core/platform/share_port.dart` |
| `assets/redact.dart` | `lib/core/logging/redact.dart` |
| `assets/di_registration_example.dart` | `lib/core/di/core_ports_module.dart` |

The HTTP port (`ApiClient`, `DioApiClient`) lives in `bloc-failures-and-results`, because its errors map straight into `AppFailure`.

## Rules

1. One adapter file per SDK is the only file that imports it. Why: a grep can prove it, and a vendor swap touches one file.
2. Ports speak the app's language. `track(OrderPlaced(...))`, not `logEvent(name, params)`. Why: the vendor's shape leaks otherwise, and two vendors never agree on it.
3. Analytics events are a closed, sealed vocabulary. No `track(String name, Map props)`. Why: every new event and property is a reviewed code change, so nobody ships an email as a property by accident.
4. Register the port type, not the adapter. `registerLazySingleton<AnalyticsPort>(...)`. Why: nothing can depend on the concrete vendor class, even by mistake.
5. Constructors take ports; only composition roots call `sl<...>()`. Why: a cubit that resolves its own analytics cannot be tested with a fake without global setup.
6. Every port has a no-op implementation and a recording fake. Why: no-op is the disabled build and the failed-init fallback; the fake is how tests assert.
7. **Port calls never throw into the caller.** Adapters catch vendor errors. Why: an analytics outage must not fail a checkout.
8. SDK init failure means no-op, not a crash. Why: the app works without analytics; it does not work if `main` throws.
9. **Nothing personal or secret leaves through a port.** Opaque ids only, low-cardinality properties, free text through `redact`. Why: analytics vendors are third parties, and their dashboards are widely shared.

## The recipe

Take analytics as the model; every other SDK follows the same steps.

1. Write the port in `lib/core/<area>/`: an `abstract interface class` with the few operations the app needs (`AnalyticsPort`: `track`, `identify`, `reset`).
2. Define the vocabulary: a sealed `AnalyticsEvent` with `name` and `properties`, one subclass per event (`ScreenViewed`, `SignInCompleted`, `OrderPlaced`, `UserActionFailed`). Properties are enums, booleans, counts and buckets.
3. Write the adapter, the only file importing the SDK. It translates the vocabulary into the vendor's call, handles vendor quirks, and swallows vendor errors.
4. Add a no-op, `NoopAnalytics`, for when analytics is disabled or init failed.
5. Add a recording fake, `RecordingAnalytics`, for tests.
6. Register it in `lib/core/di/` as the port type, chosen by config (`registerCorePorts` in the asset).
7. Add an `--dart-define` switch per flavor (`PortConfig.fromEnvironment()`), so dev builds do not pollute production dashboards.
8. Init before `runApp` only if the first frame needs it, always with a timeout, and fall back to the no-op on failure.

A vendor adapter looks like this (needs the `firebase_analytics` package, which is why it is not an asset):

```dart
// lib/core/analytics/firebase_analytics_adapter.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

final class FirebaseAnalyticsAdapter implements AnalyticsPort {
  FirebaseAnalyticsAdapter(this._sdk);

  final FirebaseAnalytics _sdk;

  @override
  void track(AnalyticsEvent event) => _sdk
      .logEvent(name: event.name, parameters: _params(event.properties))
      .ignore();

  @override
  void identify(String userId, {Map<String, Object?> traits = const {}}) {
    _sdk.setUserId(id: userId).ignore();
    for (final MapEntry(:key, :value) in traits.entries) {
      _sdk.setUserProperty(name: key, value: value?.toString()).ignore();
    }
  }

  @override
  void reset() => _sdk.resetAnalyticsData().ignore();

  // This vendor rejects null and bool values; that quirk stays here.
  static Map<String, Object> _params(Map<String, Object?> properties) => {
    for (final MapEntry(:key, :value) in properties.entries)
      if (value != null) key: value is bool ? value.toString() : value,
  };
}
```

## Several vendors: FanOutAnalytics

When product wants two analytics tools, do not call both from features. Register one `FanOutAnalytics([vendorA, vendorB])` as the `AnalyticsPort`.
It forwards each call to every target and isolates them: one vendor throwing does not stop the others or reach the caller.
Removing a vendor later is a one-line change in the registration.

## Startup and registration

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = PortConfig.fromEnvironment();

  final vendors = <AnalyticsPort>[];
  if (config.analyticsEnabled) {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 3));
      vendors.add(FirebaseAnalyticsAdapter(FirebaseAnalytics.instance));
    } catch (e) {
      debugPrint('analytics unavailable, using no-op: $e');
    }
  }

  registerCorePorts(sl, config: config, analyticsVendors: vendors);
  sl.registerLazySingleton<ApiClient>(() => DioApiClient(Dio(dioOptions)));
  runApp(const App());
}
```

Global error hooks also go through the port, after it is registered:

```dart
final crash = sl<CrashReporterPort>();
FlutterError.onError = (details) =>
    crash.recordError(details.exception, details.stack, fatal: true);
PlatformDispatcher.instance.onError = (error, stack) {
  crash.recordError(error, stack, fatal: true);
  return true;
};
```

## Worked example: the HTTP port

HTTP is the SDK every feature touches, so it shows the payoff best.

- The port is `ApiClient`, with `get`, `post`, `put`, `delete`, returning `ApiResponse` and throwing only `ApiException`. No `Dio`, `Response` or `DioException` type appears in it.
- The adapter, `DioApiClient`, is the only file importing `package:dio`. It converts `DioException` into `ApiException`, including which timeouts prove the request never left the device.
- Registration is `sl.registerLazySingleton<ApiClient>(() => DioApiClient(dio))`. Configure interceptors (auth header, logging) on the `Dio` instance in the same composition root.
- Repositories take an `ApiClient` and wrap calls in `RequestGuard`.

Tests then fake one four-method interface instead of an HTTP stack:

```dart
final class FakeApiClient implements ApiClient {
  FakeApiClient(this.responses);

  final Map<String, ApiResponse> responses;
  final List<String> calls = [];

  @override
  Future<ApiResponse> get(String path, {Map<String, Object?>? query}) =>
      _answer('GET $path');

  @override
  Future<ApiResponse> post(String path, {Object? body}) =>
      _answer('POST $path');

  @override
  Future<ApiResponse> put(String path, {Object? body}) => _answer('PUT $path');

  @override
  Future<ApiResponse> delete(String path) => _answer('DELETE $path');

  Future<ApiResponse> _answer(String call) async {
    calls.add(call);
    return responses[call] ?? (throw const ApiException(statusCode: 404));
  }
}
```

For error mapping and the money-path rules on top of this port, see `bloc-failures-and-results`.

## Testing with the recording fake

```dart
final analytics = RecordingAnalytics();

blocTest<CheckoutCubit, CheckoutState>(
  'tracks one order_placed on success',
  build: () => CheckoutCubit(repository, analytics: analytics),
  act: (cubit) => cubit.placeOrder(),
  verify: (_) => expect(analytics.eventsOfType<OrderPlaced>(), [
    const OrderPlaced(orderId: 'o-1', itemCount: 2, currency: 'EUR'),
  ]),
);
```

Events are `Equatable`, so assertions compare whole events. Widget tests that build pages resolving from get_it register fakes in `setUp` after `await sl.reset()`.

## Privacy rules

- Ids are opaque. `identify` takes your internal user id or a hash, never an email, phone number or national id.
- Properties are low-cardinality. Route names, not paths with ids. Enum names, not free text. Counts and buckets, not exact amounts. High-cardinality values also break vendor dashboards and cost money.
- Server text never becomes a property. `UserActionFailed.reason` is a failure type key such as `network`, not an error message.
- Free text goes through `redact` before a crash breadcrumb, a log line or a property. It masks `key=value` and JSON pairs for sensitive keys (token, password, pin, otp, email, phone...), bearer tokens, JWTs, emails and long digit runs. `redactMap` does the same for a property map.
- Release builds log nothing to the console. Route debug logging through a logger that is silent in release; device logs are readable by other tools.
- URLs are allowlisted. `UrlLauncherAdapter` refuses schemes outside `https`, `mailto`, `tel` (configurable), and can pin hosts. URLs from push payloads, deep links and servers are untrusted input; `javascript:`, `file:` and `intent:` stop here.

## Proving it in CI

Layer rules are checked by `bloc-feature-architecture/scripts/check_layers.sh`. Add an SDK-import rule next to it; adjust the package and adapter lists to your app:

```bash
sdks='package:(dio|firebase_analytics|firebase_crashlytics|url_launcher|share_plus)/'
adapters='^lib/core/(network/dio_api_client|analytics/[a-z_]+_adapter|crash/[a-z_]+_adapter|platform/(url_launcher|share)_port)\.dart:'
if grep -rnE "^import '${sdks}" lib | grep -vE "$adapters"; then
  echo 'SDK imported outside its adapter' >&2
  exit 1
fi
```

Also grep for static singletons outside adapters: `grep -rnE '(FirebaseCrashlytics|FirebaseAnalytics)\.instance' lib`.

## Other ports worth having

| Port | Operations | Why it pays |
|---|---|---|
| `KeyValueStorePort` | `read`, `write`, `remove` of strings | preferences without a plugin in tests; one place to version keys |
| `SecureStorePort` | same, for secrets | keeps tokens out of plain storage; an in-memory fake in tests |
| `PushPort` | `requestPermission`, `token`, `onMessage` stream | push SDKs are the hardest to test and the most often swapped |
| `ClockPort` / `Clock` | `now()` | deterministic tests for expiry and countdowns |

## Gotchas

- **Static singletons reached from widgets.** `FirebaseCrashlytics.instance.log(...)` in an `onPressed` bypasses the port, crashes widget tests with `MissingPluginException`, and survives a vendor swap as dead code. The grep above catches it.
- **Init before `runApp` blocking startup.** Awaiting four SDKs sequentially before the first frame adds seconds on a cold start, and one that hangs on a bad network hangs the app on the splash. Init only what the first frame needs, in parallel, with a timeout; the rest after the first frame.
- **Platform-channel calls in tests.** A test that "needs" `TestDefaultBinaryMessengerBinding` mocks is a test touching an SDK directly. Inject the port and use the fake.
- **Awaiting analytics in business logic.** `await analytics.track(...)` before navigating makes a slow vendor slow your UI. The port's methods return `void` on purpose.
- **Vendor errors escaping.** An unawaited vendor future that fails becomes an uncaught async error, reported as a crash. Adapters call `.ignore()` or catch.
- **Free-form escape hatches.** A `trackCustom(String, Map)` method "just for this one case" undoes the closed vocabulary within a month. Add an event subclass instead.
- **iPad share sheets.** `share_plus` needs a `sharePositionOrigin` on iPad or the call fails there. Pass `shareOriginOf(context)` from the button's context.
- **Disabled builds still initialising.** Registering `NoopAnalytics` is not enough if `main` still calls the vendor's init. Gate the init on the same config flag.

## Review checklist

- [ ] Each SDK is imported by exactly one adapter file; the CI grep passes.
- [ ] No `<Sdk>.instance` outside adapters and the composition root.
- [ ] Ports are registered as the port type; cubits receive them through constructors.
- [ ] Every port has a no-op and a test fake; tests use the fake, not platform-channel mocks.
- [ ] New analytics events are subclasses of `AnalyticsEvent` with low-cardinality properties.
- [ ] No email, phone, token, full URL with query or server message in any event, trait or breadcrumb; free text passes through `redact`.
- [ ] Adapters never throw into callers; vendor futures are ignored or caught.
- [ ] SDK init has a timeout, falls back to no-op, and does not block the first frame unless it must.
- [ ] Disabled flavors skip vendor init, not just vendor calls.
- [ ] URLs from outside the app go through `UrlLauncherPort` with its scheme allowlist.
