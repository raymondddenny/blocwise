---
name: bloc-ui-effects
description: Use when a flutter_bloc screen must navigate, show a snackbar, toast, dialog or bottom sheet, fire analytics or haptics in response to state; when wiring BlocListener/MultiBlocListener, listenWhen, go_router navigation after a submit, double-tap guards, loading buttons, or failure messages; or when fixing effects that fire twice, never fire, navigate from the wrong context, or run after the widget is unmounted.
---

# Bloc UI effects

## Why

State is what the screen looks like; an effect is something that happens once: push a route, show a snackbar, open a sheet, log an event, buzz the phone. Effects placed in `build` repeat on every rebuild. Effects placed after an `await` in `onPressed` run against a context that may be gone and react to what the code assumed, not to what the server said. Listeners fix both.

## Rules

### One-shot effects live in listeners

Navigation, snackbars, dialogs, analytics and haptics go in a `BlocListener`, never in `build` and never after an `await` in a button callback.

```dart
// BUG: navigates even when the request failed silently, and uses a context
// that may be unmounted by the time the await returns.
onPressed: () async {
  await context.read<PlaceOrderCubit>().place(draft);
  context.go('/orders');
},

// FIX: the button only asks; the listener reacts to the real outcome.
onPressed: () => context.read<PlaceOrderCubit>().place(draft),
```

Why: a listener runs exactly once per state change, with a context that is mounted by definition.

### One effects widget per feature

Collect a screen's effects in `<Feature>EffectsListener`, a `MultiBlocListener` with a `child`. The page composes providers, then effects, then the view:

```dart
class CheckoutPage extends StatelessWidget {
  const CheckoutPage({required this.draft, super.key});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PlaceOrderCubit>(),
      child: OrdersEffectsListener(child: CheckoutView(draft: draft)),
    );
  }
}
```

Why: reviewers find every side effect of a screen in one file, and the view stays a pure function of state. See `assets/orders_effects_listener.dart`.

### listenWhen describes a transition, not a state

Write `listenWhen` in terms of `previous -> next`:

```dart
listenWhen: (previous, next) =>
    previous is! ActionSucceeded<String> && next is ActionSucceeded<String>,
```

For a screen state with a failure field: `previous.failure != next.failure && next.failure != null`. Why: a listener keyed only on `next` fires again whenever an unrelated field changes while the condition still holds, which shows the same snackbar twice or pushes the same route twice.

### One ActionCubit per user action

Each action (place order, cancel, delete) gets its own `ActionCubit<T>` subclass from the bloc-state-management skill. The listener reacts to `ActionSucceeded` and `ActionFailed`; the button reads `ActionRunning` for its spinner. Why: a shared `isSubmitting` flag on the screen state cannot tell which action failed, and a second action's success can trigger the first one's navigation.

Use a subclass per action, not `ActionCubit<Unit>` directly: two `BlocProvider<ActionCubit<Unit>>` on one page shadow each other.

### Failure text comes from FailureCopy

Show failures through `showFailure(context, failure)` (`assets/show_failure.dart`), which reads `FailureCopy` and never `failure.message`. Why: `message` is developer text and can contain URLs, status codes or server internals.

An `OutcomeUnknownFailure` after a mutation is not a plain error: the server may have done it. Do not offer "Try again". Show the "checking status" copy and send the user somewhere that reads the real state (the order list, a status screen that polls).

### Check context.mounted after every await in UI code

When UI code must await (a dialog result, a permission prompt), check before touching the context again:

```dart
Future<void> _confirmAndDelete(BuildContext context, String orderId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete order?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  context.read<DeleteOrderCubit>().submit(orderId);
}
```

Why: the user can pop the page while the dialog is open; using the dead context throws or acts on the wrong route.

### Sheets and dialogs return results; the caller decides

A sheet returns a value with `Navigator.pop(context, value)`; the caller awaits it and calls the cubit. The sheet does not call the page's cubit itself or navigate past its own route. If the sheet needs page state, hand it the instance with `BlocProvider.value(value: context.read<OrdersCubit>(), child: ...)`, because a modal route sits above the page's providers.

Why: a sheet that pops itself and then pushes another route races the pop animation and can pop the wrong route.

### Navigation rules (go_router)

- Never navigate from a cubit. The cubit emits; the listener calls `context.go` / `context.push` / `context.pop`.
- `pop` to return to where the user came from; `go` to replace the stack (after a completed checkout, back should not return to the payment form). `go` from a pushed page drops the pages underneath, which also kills the iOS back swipe to them.
- Pass ids and plain arguments in the path or `extra`, never a state snapshot or a closure over one. The destination loads or reads live state. Why: an `extra` object is frozen at push time and a callback in it acts on old data.
- One navigation per outcome. If two listeners can navigate for the same transition, merge them.

### Keep the CTA enabled when the tap explains the problem

If validation runs on tap (min, max, balance), the button stays enabled for those rules so the tap can produce the message. Disable only while the action is running or when the form is structurally incomplete. Why: a disabled button with no explanation is a dead end.

### Guard double taps in two places

The button disables itself while `ActionRunning` and checks the live state at tap time; `ActionCubit.run` ignores a call while one is in flight. See `assets/checkout_button.dart`. Why: two taps can land in the same frame before the rebuild disables the button, and keyboard submit or tests bypass the button entirely.

### Analytics and haptics are effects too

Track the confirmed outcome through `AnalyticsPort`, never from the button's `onPressed`. Business events with a result (an order id) belong in the action cubit right after `run` succeeds, as `PlaceOrderCubit` does, where a unit test with `RecordingAnalytics` proves them; UI-only events and haptics go in a listener reacting to the success state:

```dart
BlocListener<PlaceOrderCubit, ActionStatus>(
  listenWhen: (previous, next) =>
      previous is! ActionSucceeded<String> && next is ActionSucceeded<String>,
  listener: (context, status) {
    // Haptics or a UI-only event. Never track OrderPlaced here as well: the
    // cubit already did, and doing both counts every order twice.
    HapticFeedback.mediumImpact();
  },
),
```

Why: tracking the tap counts attempts as conversions; tracking the success state counts what actually happened. Never put tokens, emails or phone numbers in event properties.

## Gotchas

- **Listener above the router has no navigator.** A `BlocListener` wrapped around `MaterialApp.router` is above the `Navigator`, so `context.go` and `showDialog` fail with "no Navigator" or "no GoRouter". Put app-wide listeners in the router's `builder` (or a shell route) so they sit below it, and reach the router through it.
- **Listeners do not fire for the initial state.** A `BlocListener` only sees changes after it subscribes. If the cubit is already in `ActionFailed` when the listener mounts, nothing happens. Handle the initial state in `initState` or emit after the listener is built.
- **Two listeners racing to navigate.** One listener does `go('/orders/$id')` and another, reacting to the same refresh, does `go('/orders')`. The last one wins, nondeterministically from the user's view. Keep one navigation per outcome, in one listener.
- **BlocListener on a cubit that is recreated.** If the provider above uses `create` inside a widget that rebuilds with a new key, or `BlocProvider.value` is given a new instance, the listener silently resubscribes to a fresh cubit and misses the transition that mattered. Keep the provider stable at the page.
- **Equal states do not re-emit.** Two identical failures in a row are one emission, so the second snackbar never shows. `ActionCubit` avoids this because `ActionRunning` sits between attempts.
- **Snackbar after navigation.** A snackbar shown just before `go` lives on the root `ScaffoldMessenger` and survives the route change; one shown on a nested messenger disappears with the page. Show it on the messenger that outlives the navigation.
- **`listenWhen` that reads only `next`.** Fires on every unrelated emission while the condition holds; see the transition rule above.

## Review checklist

- [ ] No navigation, snackbar, dialog, analytics or haptics in `build` or in the cubit.
- [ ] No context use after an `await` without `context.mounted`.
- [ ] Effects for the screen are in one `<Feature>EffectsListener` between providers and view.
- [ ] Every `listenWhen` compares `previous` and `next`.
- [ ] Each user action has its own `ActionCubit` subclass; effects react to `ActionSucceeded` / `ActionFailed`.
- [ ] Failure text comes from `FailureCopy`, never `failure.message`.
- [ ] `OutcomeUnknownFailure` leads to a status check, never a blind retry.
- [ ] Route extras carry ids, not snapshots or closures; one navigation per outcome.
- [ ] Sheets and dialogs return results; the caller drives the cubit.
- [ ] CTAs stay enabled for rules that are explained on tap; disabled only while running.
- [ ] Double-submit guarded in the button (live state) and in `ActionCubit.run`.
- [ ] Analytics fires on the success state through `AnalyticsPort`, with no personal data.
- [ ] App-wide listeners sit below the router.

## Assets

- `assets/orders_effects_listener.dart`: `OrdersEffectsListener`, where success navigates with an id, failure shows copy and an unknown outcome routes to a status read.
- `assets/checkout_button.dart`: `CheckoutButton` for `PlaceOrderCubit`, with a spinner and a double-submit guard that reads live state.
- `assets/show_failure.dart`: `showFailure(context, failure)` SnackBar helper using `FailureCopy`.

Copy each asset to the path on its `// Target:` first line. The widgets belong to the shared orders example (`bloc-feature-architecture/assets/example_orders/`), which provides `PlaceOrderCubit` and `OrderDraft`; `bloc-testing/assets/orders_effects_listener_test.dart` tests the listener.
