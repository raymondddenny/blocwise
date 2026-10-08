---
name: bloc-testing
description: Use when writing or reviewing tests in a flutter_bloc app (cubit/bloc tests with bloc_test, mocktail mocks for repositories, recording fakes for analytics or crash ports, repository tests against a fake ApiClient, widget tests with a pumpApp helper and get_it reset, effect listener tests, golden tests, fake_async timers), or when fixing a bug (start with a failing regression test), chasing a flaky or hanging test, or deciding what is worth testing.
---

# Bloc testing

## Why

In a bloc app the logic that can lose a user money or data lives in two places: the cubit (what happens on tap, in what order, how often) and the repository (what a failure means). Both are plain Dart behind ports, so they test fast and deterministically if the test never touches a platform channel, a real clock or a real network. Widget tests then only need to prove wiring: the right state renders the right thing, and an effect fires once.

## The pyramid

| Layer | Tool | Double for dependencies | Proves |
| --- | --- | --- | --- |
| Repository | `test` + `FakeApiClient` | scripted HTTP replies | every failure branch of `RequestGuard` maps to the right `AppFailure` |
| Cubit | `blocTest` | mocktail mock of the repository contract, `RecordingAnalytics` | state sequence, call counts, double-submit, no auto-retry |
| Widget | `testWidgets` + `pumpApp` | `MockCubit` / real cubit over a mock repo | state renders, taps call the cubit, effects fire once |
| Golden | `matchesGoldenFile`, tag `golden` | fixed data | pixels, on one pinned CI image only |
| Integration | `integration_test` | real build, staging backend | a few critical journeys end to end |

Most tests sit in the first two rows. A widget test that re-checks business rules is a slow duplicate of a cubit test.

## Rules

1. **A bug fix starts with a failing test that reproduces the user-visible symptom.** Write it at the lowest layer that can show the symptom, watch it fail, then fix. Why: a test written after the fix tends to assert the fix, not the bug, and passes on the broken code too.
2. Mock contracts, fake ports. Repositories (`abstract interface class`) get mocktail mocks; SDK ports get hand-written recording fakes (`RecordingAnalytics`). Why: a mock checks a call happened; a recorder lets you assert the exact vocabulary sent, and never needs a platform channel.
3. Never mock `ApiClient` with mocktail in repository tests; use `FakeApiClient`. Why: you want to script "a 503 came back" once, the same way the real adapter throws it, not stub internals per test.
4. **Every `RequestGuard` branch has a test, including `OutcomeUnknownFailure` on writes.** Why: a connection drop after a POST that maps to "network error, try again" is how payments get sent twice.
5. No real timers. Inject durations, drive time with `fake_async` in unit tests and `tester.pump(duration)` in widget tests. Why: real waits make suites slow and flaky under CI load.
6. Reset get_it in `tearDown`. Why: a singleton registered in one test leaks its state into the next and makes order-dependent failures.
7. Tests own what they create. Cubits passed in with `BlocProvider<T>.value` are closed with `addTearDown(cubit.close)`. Why: unclosed cubits keep timers alive past the test and trip "pending timers" assertions.
8. Goldens run on one pinned image. Never commit a golden regenerated on a laptop. Why: font antialiasing differs between machines and OS versions, so a local rebaseline breaks CI for everyone else.

## Cubit tests with bloc_test

The asset `assets/orders_cubit_test.dart` is complete. It targets the shared orders example (`bloc-feature-architecture/assets/example_orders/`); the parts it exercises:

```dart
class OrdersCubit extends Cubit<OrdersState> with SafeEmit<OrdersState> {
  OrdersCubit(this._repository) : super(const OrdersState());

  final OrdersRepository _repository;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    safeEmit(state.copyWith(status: OrdersStatus.loading, failure: () => null));
    final result = await _repository.fetchOrders(page: 1);
    if (generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        safeEmit(_firstPage(value));
      case Err(:final failure):
        _report(failure); // UnexpectedFailure -> addError
        safeEmit(state.copyWith(status: OrdersStatus.failure, failure: () => failure));
    }
  }
  // refresh() keeps the list on screen; loadMore() appends page 2, 3, ...
}

class PlaceOrderCubit extends ActionCubit<String> {
  PlaceOrderCubit(this._repository, this._analytics);

  final OrdersRepository _repository;
  final AnalyticsPort _analytics;

  Future<void> place(OrderDraft draft) async {
    final result = await run(() => _repository.placeOrder(draft));
    if (result case Ok(:final value)) {
      _analytics.track(OrderPlaced(orderId: value, itemCount: draft.quantity));
    }
  }
}
```

What each `blocTest` parameter is for:

- `setUp` stubs the mock; `build` creates a fresh cubit per test.
- `seed` starts from a mid-flow state (a list already on screen) without replaying the steps to get there.
- `act` performs the user action. Return its Future so bloc_test awaits it.
- `expect` lists emitted states. Use values when states are `Equatable`, `isA<T>().having(...)` when they are not or when only one field matters.
- `errors` asserts what the cubit reported through `addError` (which a `BlocObserver` forwards to the crash port).
- `verify` checks interactions after the run: `verify(() => repo.placeOrder(any())).called(1)` is the "never retried" proof.
- `wait` holds before asserting, for debounces. Prefer injecting the debounce `Duration` and passing `Duration.zero` in tests; reach for `wait` only for third-party timing you cannot inject.

mocktail essentials:

```dart
setUpAll(() => registerFallbackValue(const OrderDraft(productId: '', quantity: 0)));

when(() => repository.fetchOrders(page: any(named: 'page')))
    .thenAnswer((_) async => const Ok([]));
when(() => repository.placeOrder(any())).thenAnswer((_) async => const Ok('o-1'));
```

`any()` for a custom type needs `registerFallbackValue` once per file. Named parameters need `any(named: 'page')`; a bare `any()` there is a compile error or a silent non-match. Async methods use `thenAnswer`, never `thenReturn` with a Future.

## Repository tests with FakeApiClient

`assets/fake_api_client.dart` scripts replies per `METHOD path`, records every call, and throws `StateError` on an unscripted request. `assets/request_guard_test.dart` pins the shared mapping table, including the one transport error that proves a write was not sent (a connect timeout, `FakeReply.connectTimeout()`). A feature repository test repeats the same idea per method (complete in `assets/orders_repository_impl_test.dart`):

```dart
test('placeOrder: dropped connection is an unknown outcome, sent once', () async {
  api.enqueue('POST', '/orders', FakeReply.connectionDrop());

  final result = await OrdersRepositoryImpl(OrdersApi(api)).placeOrder(draft);

  expect(result, isA<Err<String>>().having((r) => r.failure, 'failure',
      isA<OutcomeUnknownFailure>()));
  expect(api.callCount('POST', '/orders'), 1);
});
```

Cover per method: the success parse, each 4xx the backend documents (with its `code`), connection drop, timeout, 5xx, and a malformed body (`UnexpectedFailure` on reads). For writes, the drop, timeout, 5xx and malformed-2xx cases must be `OutcomeUnknownFailure`; only a connect timeout, which proves nothing was sent, stays a plain `TimeoutFailure`.

## Widget and effect tests

`assets/pump_app.dart` wraps a widget in `MaterialApp` with your localization delegates and puts providers above the app. `assets/get_it_test_setup.dart` resets the locator and registers fakes under their port types.

`assets/orders_effects_listener_test.dart` is complete; it pumps the listener under a real `GoRouter` so navigation shows up as the destination on screen:

```dart
class _MockPlaceOrderCubit extends MockCubit<ActionStatus> implements PlaceOrderCubit {}

testWidgets('unknown outcome shows the status copy once and opens the list', (tester) async {
  final cubit = _MockPlaceOrderCubit();
  whenListen(
    cubit,
    Stream<ActionStatus>.fromIterable(
        const [ActionRunning(), ActionFailed(OutcomeUnknownFailure())]),
    initialState: const ActionIdle(),
  );

  await tester.pumpWidget(
    RepositoryProvider<FailureCopy>.value(
      value: _FixedCopy(),
      child: BlocProvider<PlaceOrderCubit>.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router), // '/' wraps OrdersEffectsListener
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Checking the order status'), findsOneWidget);
  expect(find.text('orders list'), findsOneWidget);
});
```

Effect listener tests assert the effect fired exactly once (one toast, one navigation) for one transition, and not at all for states that should not trigger it. Use a `NavigatorObserver` passed through `pumpApp(navigatorObservers:)` or a fake router port to assert navigation.

## Time and async

- Unit tests with timers: `fakeAsync((async) { cubit.start(); async.elapse(const Duration(seconds: 15)); ... })`. Every `Timer` the code creates runs on the fake clock.
- Widget tests already run in a fake zone: advance with `await tester.pump(const Duration(seconds: 1))`. `pumpAndSettle` never returns while an infinite animation (a spinner) is on screen; pump a fixed duration instead.
- Inside `testWidgets`, a Future that depends on real I/O (a `File` read, a real `HttpClient`, a platform plugin that resolves on another isolate) never completes, because the fake clock does not advance real async work. The test deadlocks and hangs until timeout. Either fake that service behind its port (preferred), or wrap the real call in `await tester.runAsync(() => service.load())`.

## Goldens

Use `assets/golden_test_template.dart`. Policy:

- Tag every golden test `golden` and declare the tag in `dart_test.yaml`; run them in a separate CI step.
- Run them only on the pinned host (the template skips everywhere else). Regenerate with `flutter test --tags golden --update-goldens` inside that same CI image or container, and commit only those files.
- A golden diff on a laptop is not a bug report. A golden diff on CI is.
- Keep fixtures fixed: no `DateTime.now()`, no network images, set `tester.view.physicalSize` and `devicePixelRatio`.

## What not to test

- That `emit` emits, that `Equatable` compares, that a getter returns its field.
- Generated code (`*.g.dart`, `*.freezed.dart`) and the DI wiring line by line.
- Business rules again in widget tests once the cubit test covers them.
- Vendor SDKs. Their port adapters are thin; test the code that uses the port with a fake.
- Private methods directly. Test them through the public action that uses them.

## Gotchas

- **`BlocProvider.value` in a typed list.** `providers: [BlocProvider.value(value: cubit)]` infers the base type, and `context.read<OrdersCubit>()` throws `ProviderNotFoundException`. Write `BlocProvider<OrdersCubit>.value(...)`.
- **Shared mocks across tests.** A mock created once in `main()` keeps stubs and call counts between tests. Create it in `setUp`.
- **Closing mid-request.** A cubit that emits after an await without `SafeEmit` throws when the page pops. Keep a test that closes the cubit while the repository future is pending (see the asset).
- **Testing the double-submit guard only in the widget.** Disabling the button is not enough; two calls to the cubit must produce one repository call.
- **Locale-dependent assertions.** Formatted amounts and dates differ by locale; pump with a fixed `locale` and assert the formatted string your users see.

## Review checklist

- [ ] Bug fixes include a regression test that failed before the fix and reproduces the user-visible symptom.
- [ ] Cubit tests cover success, each failure the UI treats differently, refresh-from-loaded via `seed`, and close-mid-request.
- [ ] Mutating actions have a double-submit test (one repository call) and an unknown-outcome test (no retry, no success analytics).
- [ ] Repository tests use `FakeApiClient` and cover every `RequestGuard` branch, with `OutcomeUnknownFailure` for write drops, timeouts and 5xx.
- [ ] Analytics and crash assertions use recording fakes; no platform channels in unit or widget tests.
- [ ] get_it is reset in `tearDown`; cubits created by the test are closed.
- [ ] No real `Future.delayed` or wall-clock waits; timers driven by `fake_async` or `tester.pump(duration)`.
- [ ] No `testWidgets` awaiting real I/O outside `tester.runAsync`.
- [ ] Golden tests are tagged, run on the pinned image only, and no locally regenerated `.png` is in the diff.
