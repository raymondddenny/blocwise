---
name: bloc-feature-architecture
description: Use when creating or extending a feature module in a Flutter app built on flutter_bloc, adding a repository, model, API class, use case, cubit or DI module, wiring a backend endpoint, deciding where validation, limits, flag reads or formatting belong, splitting domain and data into a local package, reviewing imports across layers or features, or migrating a legacy module (widgets calling dio, cubits parsing JSON) to feature-first layers.
---
# Bloc feature architecture

Feature-first folders, three layers per feature, one direction for imports.

## Why

Bloc codebases rot when a widget calls the HTTP client, a cubit parses JSON, and a model from one feature leaks into five others.
After that every change touches every layer and nothing can be tested without a platform channel.
A fixed layout plus a grep-able import rule keeps each piece small enough to replace and cheap to test.

## Layout

```
lib/
  core/                       result, failures, network port, bloc helpers, di
  features/<feature>/
    domain/                   entities (Equatable), repository contracts, optional use cases
    data/                     models (fromJson/toDomain), <feature>_api.dart, repository impl
    di/<feature>_module.dart  void register<Feature>Module(GetIt sl)
    presentation/
      cubit/                  <x>_cubit.dart + <x>_state.dart
      view/                   <x>_page.dart (providers) + <x>_view.dart (UI)
      widgets/                widgets only this feature uses
```

When a feature is shared by several apps, or you want the compiler instead of a script to enforce the boundary, use a local package: move `domain/` and `data/` into `packages/<feature>_repository/` and keep `presentation/` and `di/` in the app.
The package's `pubspec.yaml` depends on `equatable` and your core package, never on `flutter` or `flutter_bloc`, so a widget import simply does not resolve.
Export only the domain from the package's public library (`lib/<feature>_repository.dart`) and the impl from a second entry point (`lib/data.dart`) that only `di/` imports.

## Dependency direction

```
presentation ──► domain ◄── data
                   ▲
di ────────────────┴──── wires data impls to domain contracts
```

- `presentation` imports `domain` and `core`. Never `data`.
- `data` imports `domain` and `core`. Never `presentation`, `flutter`, `flutter_bloc`.
- `domain` imports `core/result`, `core/failures` and `equatable`. Nothing from Flutter, no SDKs, no `get_it`.
- `di` is the only folder allowed to see both sides. It registers `<Feature>RepositoryImpl` as `<Feature>Repository`.

Why: a cubit that only knows the contract can be tested with a mocktail mock, and the data layer can be rewritten (REST to GraphQL, cache added) without a cubit diff.

## Rules per layer

### domain

- Entities extend `Equatable`, hold typed values (`DateTime`, `int` minor units, enums), and have no `fromJson`. *Why: JSON shape is a backend detail; parsing belongs where the backend is known.*
- Repository contracts are `abstract interface class` returning `FutureResult<T>` (or `Stream<T>` for live data). *Why: every caller gets a typed failure and has to handle it; nothing throws across the boundary.*
- Pure rules live here as functions or methods on entities: `canCancel`, `isWithinLimit(amount)`. *Why: the same rule then holds in every cubit that uses the entity, and tests need no widgets.*
- No `BuildContext`, no `Color`, no `Locale`, no `dart:ui`. *Why: those pull Flutter into code that should run in a plain `dart test`.*

### data

- `<Feature>Api` owns the endpoint paths and calls `ApiClient` (the core port), returning models. *Why: one file to read when the backend changes a path; no feature imports `dio`.*
- Models are plain classes with `fromJson` and `toDomain()`. They never escape `data/`. *Why: a renamed JSON key is a one-file fix instead of a search across widgets.*
- `<Feature>RepositoryImpl` mixes in `RequestGuard`; reads use `guardRead`, mutations use `guardWrite`. *Why: `RequestGuard` is the only try/catch in data code, and `guardWrite` turns a dropped connection or 5xx into `OutcomeUnknownFailure` instead of a fake "failed".*
- Parsing is tolerant at the edge: unknown enum strings map to an explicit `unknown` value, never to the success case. *Why: a new backend status must never render as success.*

### presentation

- The page creates providers (`BlocProvider(create: (_) => sl<OrdersCubit>()..load())`); the view only builds UI. *Why: the view is testable by pumping it under a `BlocProvider.value` with a mock cubit.*
- Cubits depend on repository contracts or use cases, injected through the constructor. *Why: `sl` lookups inside a cubit hide dependencies from tests.*
- Cubits mix in `SafeEmit` and use `safeEmit` after every `await`. *Why: the user can pop the page mid-request; a plain `emit` then throws.*
- Widgets never call repositories, `ApiClient` or SDKs. *Why: a widget that fetches cannot be reused or tested without the network.*

### di

- One `register<Feature>Module(GetIt sl)` per feature, called from `lib/core/di/injector.dart`. *Why: the app's whole object graph is readable in one list of calls.*
- Repositories are `registerLazySingleton<Contract>`, cubits `registerFactory`. *Why: a singleton cubit survives its page and replays stale state on the next visit.*

If you use `injectable`, annotate the impl with `@LazySingleton(as: OrdersRepository)` and keep the same folder rules; the generated config replaces the module function, nothing else changes.

## When a use case earns its place

Default to cubit -> repository. Add `domain/usecases/<verb>_<noun>.dart` with a single `call()` only when one of these is true:

- Two or more cubits need the same orchestration (fetch quote, check limit, then submit).
- The logic combines several repositories or applies a non-trivial domain rule that deserves its own tests.

A use case that only forwards `repository.fetchAll()` is a file that has to be renamed, injected and mocked for no gain. Delete it.

```dart
class SubmitPayment {
  const SubmitPayment(this._payments, this._limits);

  final PaymentsRepository _payments;
  final LimitsRepository _limits;

  FutureResult<Receipt> call(PaymentDraft draft) async {
    final limits = await _limits.current();
    return switch (limits) {
      Err(:final failure) => Err(failure),
      Ok(:final value) when !value.allows(draft.amount) => Err(
        ValidationFailure(
          message: 'amount outside limits',
          fieldErrors: const {'amount': 'out_of_range'},
        ),
      ),
      Ok() => _payments.submit(draft),
    };
  }
}
```

## Cross-feature rule

- A feature may import another feature's `domain/` only. Never its `data/` or `presentation/`.
- A model or entity used by three or more features moves to `lib/core/<topic>/` (for example `core/money/money.dart`). *Why: otherwise one feature becomes everyone's dependency and cannot change.*
- Navigation to another feature goes through route names or paths (go_router or your router), not by importing that feature's page into your view.
- Cross-feature reactions (orders list refreshes after a payment) go through a domain-level stream or event bus in `core`, not by one cubit holding another.

## Where logic lives

| Concern | Lives in | Not in |
|---|---|---|
| Field format rules (email shape, amount > 0) | domain function or entity method | view `validator:` closures copied per screen |
| When to validate and which message order (tap, min then max then balance) | cubit | widget `onChanged` |
| Limits and fees | data fetches them, domain entity holds them, cubit compares | hardcoded constants in the view |
| Feature flag reads | entry point: route guard, page, or cubit via an injected flags reader | domain, data, shared widgets |
| Money and date formatting | view (or a presentation formatter) with the current locale | cubit state strings, domain, data |
| User-facing failure text | `FailureCopy.of(failure)` in presentation | `failure.message`, data layer |
| Endpoint paths and JSON keys | `<feature>_api.dart` and models | repository impl, cubit |

Cubit state holds raw values (an `int` of minor units, a `DateTime`), never preformatted strings. *Why: a locale change or a reformat then needs no cubit change, and tests compare numbers, not text.*
If a domain rule depends on a flag, the cubit reads the flag and passes a plain `bool` into the domain call. *Why: domain stays pure and the flag stays at the edge where it can be removed in one diff.*

## Build order for a new feature

1. Entity and repository contract in `domain/`. Agree on the shape before any JSON exists.
2. Model plus `fromJson`/`toDomain`, with a unit test against a captured real payload.
3. `<Feature>Api` and `<Feature>RepositoryImpl` with `RequestGuard`. Test with a fake `ApiClient`.
4. `di/<feature>_module.dart` and one line in `injector.dart`.
5. State and cubit; `bloc_test` against a mocktail mock of the contract.
6. Page and view; a widget test with a mock cubit, then the route.
7. Run `scripts/check_layers.sh` before opening the PR.

`scripts/new_feature.sh orders` creates steps 1 to 6 as compilable stubs (entity `Order`, `OrdersRepository`, `OrderModel`, `OrdersApi`, `OrdersRepositoryImpl`, `registerOrdersModule`, `OrdersCubit`/`OrdersState`, `OrdersPage`/`OrdersView`):

```bash
bash skills/bloc-feature-architecture/scripts/new_feature.sh orders
bash skills/bloc-feature-architecture/scripts/new_feature.sh wallet_transfer --entity Transfer
bash skills/bloc-feature-architecture/scripts/new_feature.sh audit_logs --root lib/src/features --package my_app
```

Run it from the app root. It reads `name:` from `pubspec.yaml`, never overwrites a file (prints `skip`), and expects the core files from `bloc-failures-and-results` and `bloc-state-management` (`Result`, `AppFailure`, `ApiClient`, `RequestGuard`, `SafeEmit`, `lib/core/di/injector.dart`).

## Worked example: orders

`assets/example_orders/` is the complete orders feature the other skills in this pack refer to, laid out exactly as above: `Order`, `OrderDraft` and `OrdersRepository` (`fetchOrders({required int page})`, `placeOrder(OrderDraft)`) in `domain/`; `OrderModel`, `OrdersApi` and `OrdersRepositoryImpl` in `data/`; `registerOrdersModule` in `di/`; `OrdersCubit`/`OrdersState` (load, refresh, paginate), `PlaceOrderCubit` and `OrdersPage`/`OrdersView` in `presentation/`.
Copy each file to the path on its `// Target:` first line. `assets/injector.dart` is the composition root (`lib/core/di/injector.dart`) that exposes `sl` and calls `registerOrdersModule`.
Its tests live in `bloc-testing/assets/`, its effects widgets in `bloc-ui-effects/assets/`.

## Checking layers in CI

```bash
bash skills/bloc-feature-architecture/scripts/check_layers.sh            # lib/features
bash skills/bloc-feature-architecture/scripts/check_layers.sh lib/src/features
BLOCWISE_VENDOR_SDKS="dio firebase_* sentry* amplitude*" bash .../check_layers.sh
```

It greps `import` and `export` lines (relative and `package:` forms) and fails with `file:line: rule (uri)` for:

- presentation importing any `data/`;
- domain importing `flutter`, `dart:ui`, `flutter_bloc`, `bloc`, `dio`, `get_it`, `injectable`, any vendor SDK, or any `data/`, `presentation/` or `di/` path;
- data importing `presentation/`, `flutter`, `flutter_bloc` or `bloc`;
- any feature importing another feature's `data/` or `presentation/`;
- any feature file importing a vendor SDK directly (default list: `dio firebase_* sentry* posthog* url_launcher share_plus shared_preferences flutter_secure_storage`). Wrap those behind ports from `bloc-sdk-ports`.

`core/` is outside the default root on purpose: the adapters that are allowed to import vendors live there.

## Migrating a legacy module

Do it in slices that each ship, never as one rewrite branch.

1. Fence it. Move the module under `lib/features/<feature>/` as is, with everything in `presentation/`. Run `check_layers.sh` and record the violations; that list is the backlog.
2. Contract first. Write the domain entity and repository contract for the one call you are touching. Implement it by moving the existing HTTP code into `data/`, unchanged except for `RequestGuard`.
3. Swap the caller. Point the cubit (or the widget, if there is no cubit yet) at the contract. Behaviour stays identical; the diff is imports plus a `switch` on `Result`.
4. Pull JSON out of presentation. Replace `Map<String, dynamic>` in cubit state with entities. Characterization tests first if the module has none: pin today's output, then refactor.
5. Repeat per call until the violation list is empty, then add the checker to CI so it stays that way.

Keep old and new paths side by side for one release when the call moves money or auth, and delete the old path in a follow-up rather than leaving both.

## Gotchas

- **Models leaking into state.** `final List<OrderModel> orders;` in `OrdersState` compiles fine and then every backend rename breaks a widget. The checker catches the import; review catches the type.
- **Cubit registered as singleton.** The second visit to a page shows the first visit's data and an old `ActionFailed`. Use `registerFactory`.
- **`sl<...>()` inside a cubit or widget build.** Works until a test forgets to register it. Inject through the constructor; the page is the one place that calls `sl`.
- **Barrel files that re-export `data/`.** One `export 'data/orders_repository_impl.dart';` in `orders.dart` lets every importer reach the impl. Barrels export domain only.
- **Use case per endpoint.** Ten forwarding use cases add ten mocks to every test. Add one when it holds logic.
- **"Shared" folder inside a feature that other features import.** It is a core module pretending to be a feature. Promote it.
- **Formatting in the cubit.** `state.totalText = '$20.00'` makes the cubit locale-dependent and turns equality checks into string checks.
- **Generated stubs left as stubs.** `new_feature.sh` writes `id`-only entities and a `Retry` text button. Replace them before review; they are scaffolding, not defaults.

## Review checklist

- [ ] Every new file sits in `domain/`, `data/`, `di/` or `presentation/` of exactly one feature, or in `core/`.
- [ ] `check_layers.sh` prints OK.
- [ ] Domain has no Flutter, SDK, `get_it` or JSON code; entities are `Equatable`.
- [ ] Repository contract returns `FutureResult<T>`; the impl uses `guardRead` for reads and `guardWrite` for mutations.
- [ ] Models stay in `data/`; cubit state and widgets only see entities.
- [ ] Endpoint paths live in `<feature>_api.dart` and go through `ApiClient`, not `dio`.
- [ ] Unknown backend statuses map to an explicit unknown or pending value, never success.
- [ ] Repository registered as its contract type; cubit registered with `registerFactory`.
- [ ] Cubit dependencies arrive through the constructor; only the page calls `sl`.
- [ ] Cubit uses `safeEmit` after every `await`.
- [ ] Each use case holds shared or non-trivial logic; no pure forwarders.
- [ ] No import of another feature's `data/` or `presentation/`; widely shared types promoted to `core/`.
- [ ] Validation rules in domain, validation timing in the cubit, formatting in the view, flag reads at the entry point.
- [ ] Tests: model `fromJson` against a real payload, repository impl with a fake `ApiClient`, cubit with `bloc_test` and a mocked contract.
