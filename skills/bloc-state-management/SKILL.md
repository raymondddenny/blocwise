---
name: bloc-state-management
description: Use when writing or reviewing a Cubit or Bloc, designing its state (Equatable, copyWith, sealed vs status enum), choosing Cubit vs Bloc, handling async races, stale responses, debounce, pagination or refresh, cancelling timers and subscriptions in close(), placing BlocProvider, using BlocBuilder/BlocSelector/buildWhen or context.read/watch/select, validating on submit, or fixing "Cannot emit new states after calling close" and stale-state bugs in flutter_bloc.
---

# Bloc state management

## Why

Most flutter_bloc bugs have little to do with the library itself: a response that lands after the user moved on, a state class that cannot clear a field, a builder that hands a stale value to a callback, or a timer that outlives its page. The rules below close those holes by default.

## Rules

### Cubit by default, Bloc when events need shaping

Start with a Cubit: methods in, states out, one less layer to read. Switch to a Bloc when:

- you need event transformers to debounce a search box, drop taps while busy (`droppable`), or cancel the previous request when a new one arrives (`restartable`);
- you want an audit trail of what was asked, not only what changed, from `onEvent` and `onTransition`;
- you need concurrency control per event type: `sequential` for writes that must not overlap, `concurrent` for independent reads.

Why: a Bloc's extra ceremony pays only when the event stream itself needs shaping.

### State is immutable, Equatable, and can clear its fields

Every field `final`, every state `Equatable` (or a record) so `BlocBuilder` skips identical emissions. `copyWith` takes nullable fields as `ValueGetter<T?>?` so callers can say "set to null":

```dart
state.copyWith(failure: () => null);       // clears
state.copyWith(nextPage: () => page);      // sets, possibly to null
state.copyWith(isLoadingMore: true);       // leaves failure untouched
```

Why: with a plain `AppFailure? failure` parameter, `copyWith(failure: null)` means "keep the old one" and the error never goes away.

Lists in state are replaced, never mutated (`[...state.orders, ...value]`). Mutating a list in place keeps the same reference, Equatable sees no change, and the UI does not rebuild.

### Sealed states or one state with a status enum

| Use sealed states (`Initial`, `Loading`, `Loaded`, `Failed`) when | Use one class with a `status` enum when |
|---|---|
| each phase carries different data | data must survive phase changes |
| the screen swaps wholesale between phases | refresh or load-more keeps the list visible |
| you want `switch` exhaustiveness in the view | several flags combine (refreshing + loaded + failed toast) |

```dart
sealed class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => const [];
}
final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}
final class ProfileLoaded extends ProfileState {
  const ProfileLoaded(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}
final class ProfileFailed extends ProfileState {
  const ProfileFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

// view
return switch (state) {
  ProfileLoading() => const CircularProgressIndicator(),
  ProfileLoaded(:final name) => Text(name),
  ProfileFailed(:final failure) => FailureView(failure),
};
```

Why: sealed states make impossible combinations unrepresentable; a status enum avoids copying the list into every phase. Pick per screen, not per app. For a single user action (submit, pay, delete) use `ActionCubit<T>` from `assets/action_status.dart` instead of adding a `submitting` flag to the screen state.

### The cubit owns the flow; the widget owns the BuildContext

The cubit decides: validation, ordering of calls, retries, what counts as success. It never touches `BuildContext`, `Navigator`, `GoRouter`, `ScaffoldMessenger` or widgets. It emits a state; a `BlocListener` turns that into navigation or a toast (see the bloc-ui-effects skill).

Why: a cubit that navigates cannot be tested without a widget tree, and breaks the moment the page is shown in a different route.

### Never emit after close

Any `emit` after an `await` can run after the page was popped and the cubit closed, which throws `StateError: Cannot emit new states after calling close`. Mix in `SafeEmit` (`assets/safe_emit.dart`) and call `safeEmit` everywhere after an await.

Why: the user backing out mid-request is normal, not exceptional. In a `Bloc`, emit through the handler's `Emitter`; it already stops after close.

### Drop stale responses

Two requests in flight can resolve in either order. Pick one guard:

- In a Cubit, keep a generation counter: bump an `int` on every load, capture it before the await, return if it changed. See `OrdersCubit` in the shared orders example (`bloc-feature-architecture/assets/example_orders/presentation/cubit/orders_cubit.dart`).
- In a Bloc, use `restartable()` from `bloc_concurrency`: it cancels the previous handler when a new event arrives and ignores that handler's emits.
- For search boxes, where the input itself is the token, keep it in the state and compare `state.query == query` after the await.

Why: without a guard, a slow response for "ap" overwrites the fast one for "apple".

Debounce with `assets/debounce_transformer.dart` (no extra package). Combine it with `restartable()` when an in-flight request should be cancelled, not queued.

### close() cancels everything the cubit started

Every `Timer`, `StreamSubscription`, `StreamController`, ticker or listener created in the cubit is cancelled in `close()`:

```dart
class QuoteCubit extends Cubit<QuoteState> with SafeEmit<QuoteState> {
  QuoteCubit(this._repository) : super(const QuoteState());

  final QuoteRepository _repository;
  Timer? _ticker;

  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    _refresh();
  }

  void pause() => _ticker?.cancel();

  Future<void> _refresh() async {
    final result = await _repository.latestQuote();
    if (result case Ok(:final value)) safeEmit(state.copyWith(quote: value));
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}
```

Why: a periodic timer keeps firing requests after the page is gone. Keep one ticker per screen as the single source of truth; sheets and child widgets read the cubit's state instead of starting their own timers. Pause it while a confirmation sheet is open so the number the user is confirming does not change under their thumb.

### Provide the cubit where it lives

- `BlocProvider(create: ...)` at the page (route) level. The provider closes the cubit when the page leaves.
- App-wide providers only for state that is truly app-wide (session, theme, connectivity).
- `BlocProvider.value(value: cubit)` to hand an existing instance to a pushed sheet or dialog. It does not close the cubit, which is correct: the owner does.
- Never create a cubit inside `build` or pass `create: (_) => existingCubit`. The first rebuilds state on every frame; the second closes a cubit someone else owns.

Why: lifecycle bugs (double close, leaked timers, lost state) come from the provider being in the wrong place.

### get_it builds dependencies, BlocProvider owns the lifecycle

get_it constructs repositories and services. BlocProvider constructs and disposes the cubit:

```dart
// lib/features/orders/presentation/view/orders_page.dart
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrdersCubit(sl<OrdersRepository>())..load(),
      child: const OrdersView(),
    );
  }
}
```

If you register cubits in get_it (common with injectable), use `registerFactory`, never `registerSingleton` or `registerLazySingleton`. Why: a singleton cubit is closed by the first page that leaves and then throws on the second visit.

### Rebuild correctly: buildWhen, BlocSelector, and live reads

- `BlocSelector` or `context.select` for a single derived value; the widget rebuilds only when that value changes.
- `buildWhen` must include every field the builder reads. If the builder shows `amount`, `buildWhen` must compare `amount`.
- `context.watch` / `context.select` inside `build` only. `context.read` inside callbacks only.

**The stale snapshot gotcha.** A builder parameter is the state from the last rebuild, not the current one. With a narrow `buildWhen`, the two drift apart:

```dart
// BUG: buildWhen only tracks validity. Typing "20." then "20.5" keeps it valid,
// so no rebuild happens and onPressed submits 20, the value captured earlier.
BlocBuilder<AmountCubit, AmountState>(
  buildWhen: (p, n) => p.isValid != n.isValid,
  builder: (context, state) => FilledButton(
    onPressed: state.isValid ? () => submit(state.amount) : null,
    child: const Text('Continue'),
  ),
);

// FIX: decide enabled-ness from the snapshot, read values live at tap time.
BlocBuilder<AmountCubit, AmountState>(
  buildWhen: (p, n) => p.isValid != n.isValid,
  builder: (context, state) => FilledButton(
    onPressed: state.isValid
        ? () => submit(context.read<AmountCubit>().state.amount)
        : null,
    child: const Text('Continue'),
  ),
);
```

Better still, give the cubit a `submit()` that reads its own `state`, so the widget passes nothing. The same applies to route extras: a closure or object pushed with a route freezes the data at push time. Pass an id and let the destination read live state.

### Validate on submit, in a fixed order

For forms where live errors while typing are noise (amounts, transfers), validate when the CTA is tapped, one message per rule, first failing rule wins:

```dart
AmountError? validate(int amount, {required Limits limits, required int balance, required int fee}) {
  if (amount < limits.min) return AmountError.belowMin;
  if (amount > limits.max) return AmountError.aboveMax;
  if (amount > balance) return AmountError.insufficientBalance;
  if (amount + fee > balance) return AmountError.insufficientForFee;
  return null;
}
```

The cubit runs this in `submit()` and emits the error for a listener to show. Keep the CTA enabled for min/max: if the button is disabled, the message that explains why can never appear.

## Gotchas

- A field left out of an Equatable's `props` never triggers a rebuild. Add every field, including lists and nullable fields.
- Emitting a state equal to the current one does nothing. If a toast must fire twice for the same failure, clear the failure in between or use `ActionCubit`, whose `ActionRunning` sits between two failures.
- **`BlocProvider.value` with a fresh instance.** `BlocProvider.value(value: OrdersCubit(...))` never closes it. Use `create`.
- **`context.read` in `build`.** The widget does not rebuild when the state changes. Use `watch` or `select` there.
- **Async work in the constructor.** `OrdersCubit(...)..load()` in `create` is fine; calling `load()` inside the constructor body makes the cubit untestable without the request firing.
- **Two loads racing with pagination.** A load-more response that returns after a refresh appends page 2 of the old list to the new one. Capture the generation before the await (see the example cubit).
- **Bloc `emit` after a cancelled handler.** With `restartable`, code after an `await` in the cancelled handler still runs; only its emits are ignored. Do not perform side effects there.

## Review checklist

- [ ] Cubit unless the feature needs transformers, traceability or concurrency control.
- [ ] State is immutable and Equatable; every field is in `props`.
- [ ] Nullable fields in `copyWith` use `ValueGetter<T?>?`.
- [ ] Sealed states vs status enum chosen for this screen's data shape.
- [ ] No `BuildContext`, navigation or widget code in the cubit.
- [ ] Every emit after an await is `safeEmit` (Cubit) or through the `Emitter` (Bloc).
- [ ] Concurrent requests have a stale-response guard (generation, `restartable`, or token).
- [ ] Every timer, subscription and controller is cancelled in `close()`.
- [ ] `BlocProvider(create:)` at the page; `.value` only for existing instances; nothing created in `build`.
- [ ] Cubits in get_it are factories, never singletons.
- [ ] `buildWhen` covers every field the builder reads; callbacks read live state with `context.read`.
- [ ] Route extras carry ids, not state snapshots or closures.
- [ ] Submit validation runs in the cubit in a fixed order; the CTA stays enabled for rules it must explain.
- [ ] One user action = one `ActionCubit`, with the double-submit guard in the cubit.

## Assets

- `assets/safe_emit.dart`: `SafeEmit` mixin, copy to `lib/core/bloc/`.
- `assets/action_status.dart`: `ActionStatus` and `ActionCubit<T>`, copy to `lib/core/bloc/`.
- `assets/debounce_transformer.dart`: `debounce<E>()` event transformer and `Stream.debounced()`.
- The shared orders example in `bloc-feature-architecture/assets/example_orders/` (`presentation/cubit/orders_state.dart`, `orders_cubit.dart`): load, refresh and paginate with `SafeEmit`, `Result` switching and a generation guard. Its tests are `bloc-testing/assets/orders_cubit_test.dart`.
