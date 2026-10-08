---
name: bloc-leak-guard
description: Use when writing or reviewing a cubit, bloc or StatefulWidget that owns a Timer, StreamSubscription, StreamController, AnimationController, TextEditingController, FocusNode, ScrollController or addListener call; when memory grows after navigating back and forth; when "setState() called after dispose" or "Cannot emit new states after calling close" shows up; or when auditing a flutter_bloc app for leaks with DevTools or a grep pass.
---

# Bloc leak guard

## Why

A Flutter leak is usually a small object that something long-lived still points at: a periodic timer that keeps a closed cubit alive, a subscription to a repository stream that outlives its page, a listener on an app-wide notifier that pins a whole widget subtree. Each one is cheap, so nobody notices until a user opens the same screen thirty times, memory climbs, a ticker fires against a dead page and the logs fill with "setState() called after dispose()". The fix is always the same rule applied without exceptions: whoever creates a resource releases it, in the same class, in `close()` or `dispose()`.

## What leaks

| Resource | Created by | Released by | What it pins if forgotten |
| --- | --- | --- | --- |
| `Timer` / `Timer.periodic` | cubit, State | `cancel()` | the callback closure, so the cubit or State and everything it references |
| `StreamSubscription` | `stream.listen(...)` | `cancel()` | the listener closure; the source stream keeps delivering to a dead object |
| `StreamController` | cubit, service | `close()` | every subscriber's listener |
| `AnimationController` | State with a ticker mixin | `dispose()` | the Ticker; also logs a "Ticker was not disposed" error in debug |
| `TextEditingController`, `FocusNode`, `ScrollController`, `PageController`, `TabController` | State | `dispose()` | listeners registered by the widgets that used them |
| `addListener` on a long-lived `ChangeNotifier` / `ValueNotifier` | State, cubit | `removeListener` with the same function reference | the listener closure, and through it the State or cubit |
| Cubit created with `XCubit(...)` outside `BlocProvider(create:)` | widget code, another cubit | `close()` | its own timers and subscriptions, plus the stream controller inside the cubit |
| Closure capturing `BuildContext` | `then`, `listen`, timer callbacks | not capturing it | the Element, so the whole subtree |
| get_it singleton holding page state | `registerSingleton` / `registerLazySingleton` | `resetLazySingleton` or not doing it | everything ever stored in it, for the life of the app |

## Rules

1. **The class that creates a resource releases it.** Why: ownership split across classes is how resources get released twice or never.
2. Keep every handle in a field. `stream.listen(...)` with the return value thrown away is a leak by construction. Why: you cannot cancel what you did not keep.
3. Release in `close()` / `dispose()` before calling `super`. Why: `super.close()` closes the state stream; a timer tick between the two then emits into a closed cubit.
4. Let `BlocProvider(create:)` own cubits. Use `BlocProvider.value` only for a cubit something else already owns and closes. Why: `create:` closes the cubit when the provider leaves the tree; `.value` never does.
5. One periodic ticker per screen, owned by one cubit. Pause it while a modal (confirmation sheet, dialog) is open and resume on dismiss. Why: two tickers driving the same value race each other, and a ticker under a modal burns battery and network for a screen nobody sees.
6. Pass a method tear-off or a stored closure to `addListener`, never an inline lambda. Why: `removeListener(() => ...)` builds a new function that is not equal to the one you added, so nothing is removed.
7. Never capture `BuildContext` in something that outlives the frame. Read what you need (a cubit, a navigator, a localized string) before the `await`, and check `context.mounted` after it. Why: the closure keeps the Element alive and using it later throws.
8. Page state never goes in a get_it singleton. Register cubits with `registerFactory`; keep singletons for stateless services and repositories. Why: a singleton lives as long as the app, so whatever it holds does too.
9. Emit after an await through `SafeEmit` (`lib/core/bloc/safe_emit.dart`). Why: it turns "page popped mid-request" from a crash into a no-op; it does not fix a leak, so still cancel the work.

## Worked example: a quote ticker cubit

```dart
import 'dart:async';

import 'package:app/core/bloc/safe_emit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

abstract interface class QuoteSource {
  Stream<double> watchRate(String pair);
  Future<double> fetchRate(String pair);
}

class QuoteCubit extends Cubit<double?> with SafeEmit<double?> {
  QuoteCubit(this._source, this._pair) : super(null);

  final QuoteSource _source;
  final String _pair;
  StreamSubscription<double>? _live;
  Timer? _refresh;

  void start() {
    _live ??= _source.watchRate(_pair).listen(safeEmit);
    _refresh ??= Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  /// Called while a confirmation sheet is on top of the page.
  void pause() {
    _refresh?.cancel();
    _refresh = null;
  }

  Future<void> _poll() async => safeEmit(await _source.fetchRate(_pair));

  @override
  Future<void> close() async {
    _refresh?.cancel();
    await _live?.cancel();
    return super.close();
  }
}
```

And the State side, with a listener on an app-wide notifier:

```dart
class _AmountFieldState extends State<AmountField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.currency.addListener(_onCurrencyChanged); // tear-off, removable
  }

  void _onCurrencyChanged() => setState(() {});

  @override
  void didUpdateWidget(AmountField old) {
    super.didUpdateWidget(old);
    if (old.currency != widget.currency) {
      old.currency.removeListener(_onCurrencyChanged);
      widget.currency.addListener(_onCurrencyChanged);
    }
  }

  @override
  void dispose() {
    widget.currency.removeListener(_onCurrencyChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }
  // build() omitted
}
```

`didUpdateWidget` is the part most often missed: when the parent swaps the notifier, the old one keeps a listener to a State that no longer reads it.

## Verifying with DevTools

A code read finds candidates; the heap proves a leak. Use a profile build on a device (debug mode keeps extra references and inflates counts).

1. Open DevTools > Memory, start on the screen before the suspect one, press GC, take snapshot A.
2. Navigate into the suspect screen and back out. Repeat N times (10 is enough).
3. Press GC, take snapshot B, open the Diff view between A and B.
4. Filter by your package and look at instance counts of the page's State, its cubit, and the cubit's state class. After popping the page all three should be at or near 0 extra. A count that grows with N (10 visits, about 10 extra instances) is a leak.
5. Select a leaked instance and read its retaining path. The first frame that belongs to your code (a `_Timer`, a `_StreamSubscription`, a listener list inside a notifier, a get_it registration) is the owner that forgot to release.

Leak tracking in tests is a complement for widget-owned objects: the `leak_tracker_flutter_testing` package can fail a widget test when a disposable object is not disposed. It covers `ChangeNotifier`s and controllers, not timers or subscriptions inside cubits, so the heap diff stays the source of truth.

### An addListener count alone is not a leak

`ChangeNotifier` keeps a listener list, and seeing it at 3 or 5 is not a finding by itself. Many framework widgets (`TextField`, `Scrollable`, `AnimatedBuilder`, `ListenableBuilder`) add and remove their own listeners as they rebuild. What matters is whether the count returns to its baseline after the page is gone, and whether the instances that registered those listeners are still on the heap. Check the snapshot diff before "fixing" a listener count.

## Grep audit

`scripts/leak_audit.sh` is a fast first pass for reviews and CI. From the package root:

```bash
bash skills/bloc-leak-guard/scripts/leak_audit.sh            # report over lib/, exit 0
bash skills/bloc-leak-guard/scripts/leak_audit.sh --strict   # exit 1 when anything is found
bash skills/bloc-leak-guard/scripts/leak_audit.sh packages/orders_repository/lib
```

It lists files that create a `Timer`, `.listen(`, `StreamController`, controllers, `FocusNode`, `addListener` or a cubit outside `create:` with no matching `cancel` / `close` / `dispose` / `removeListener` anywhere in the same file. It skips comment lines and generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`). Silence a deliberate case on its line with `// leak-audit:ignore <reason>`, for example a one-shot `Timer` whose callback cannot outlive its owner.

It is a heuristic in both directions: one `cancel()` in the file satisfies every timer and subscription in it, and a resource released by a different class (rule 1 says it should not be) shows up as a finding. Read each hit; confirm the ones that matter with the heap diff.

## Gotchas

- **`close()` that forgets to await.** `_sub?.cancel()` returns a Future; if the stream's `onCancel` does work (closing a socket, a platform channel), not awaiting it races the next screen's `listen`.
- **Cancel, then null.** `pause()` that cancels a timer but leaves the field set makes `start()` with `??=` think the timer is still running. Null the field after cancelling.
- **Listening in `build()`.** A `listen` or `addListener` inside `build` registers again on every rebuild. Register in `initState` (or the cubit constructor) and use `BlocListener` for UI reactions.
- **`BlocProvider.value(value: XCubit())`.** Looks like a provider, behaves like a leak: `.value` never closes. Use `create:`.
- **Cubit-to-cubit subscriptions.** A cubit that listens to another cubit's `stream` must cancel in its own `close()`. Prefer `BlocListener` in the widget tree or a shared repository stream so the dependency is visible.
- **`then` on a page Future.** `repository.load().then((r) => Navigator.of(context).push(...))` holds the context until the Future completes, and pushes onto a dead navigator if the user left. Do it in the cubit and react with a listener.
- **`registerLazySingleton` for a cubit.** The second visit to the page gets the first visit's closed cubit and throws on emit. Cubits are `registerFactory`.

## Review checklist

- [ ] Every `Timer`, `listen`, `StreamController`, controller and `FocusNode` is stored in a field of the class that created it.
- [ ] Every such field is released in that class's `close()` / `dispose()`, before `super`.
- [ ] Every `addListener` has a `removeListener` with the same tear-off, including in `didUpdateWidget` when the notifier can change.
- [ ] Cubits come from `BlocProvider(create:)` or a `registerFactory`; `BlocProvider.value` only wraps a cubit someone else closes.
- [ ] No `BuildContext` captured in timers, `then`, or stream callbacks; `context.mounted` checked after every await in widgets.
- [ ] One periodic ticker per screen, paused while a modal is open.
- [ ] No page state in get_it singletons.
- [ ] `leak_audit.sh` run on the diff; every remaining hit is either fixed or carries a `leak-audit:ignore` reason.
- [ ] For a suspected leak: a DevTools heap diff after N visits, with the retaining path named in the fix.
