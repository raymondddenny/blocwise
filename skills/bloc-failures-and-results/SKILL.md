---
name: bloc-failures-and-results
description: Use when handling errors in a flutter_bloc app: adding a repository call, mapping Dio or HTTP errors, writing try/catch in data code, returning Result/Ok/Err, showing an error message or toast, handling backend error codes, or building a payment, transfer, order or any request that changes server state (timeouts, retries, "did it go through?", status polling). Also for reviewing code that shows an unknown status as success or retries a POST.
---

# Typed failures and Result

Exceptions are invisible in a Dart signature. A repository that throws forces every cubit to guess which errors exist, and the guess is usually `catch (e)` plus a generic toast.
This pack makes failure part of the return type: data code returns `Result<T>`, which is `Ok<T>` or `Err<T>` carrying a sealed `AppFailure`. The compiler then checks that every caller handled both branches, and an exhaustive `switch` over `AppFailure` turns "we forgot timeouts" into a compile error.

Assets (copy into the app, imports use `package:app/...`): `result.dart` to `lib/core/result/`, `app_failure.dart` and `failure_copy.dart` to `lib/core/failures/`, `api_client.dart`, `dio_api_client.dart` and `request_guard.dart` to `lib/core/network/`, `transaction_status.dart` to `lib/core/money/`.

## Rules

1. No exception crosses a layer boundary. Repositories return `FutureResult<T>`; cubits never write `try`. Why: one translation point means one place to get it right.
2. `RequestGuard` is the only try/catch in data code. Repository impls mix it in and wrap each call in `guardRead` or `guardWrite`. Why: a hand-written `catch` in a repository is where `catch (e) => NetworkFailure()` creeps in and swallows bugs.
3. Reads use `guardRead`, anything that changes server state uses `guardWrite`. Why: the same timeout means "try again" for a read and "you may already have paid" for a write.
4. **An unknown outcome is never retried automatically.** It is reconciled by reading status. Why: retrying a request that the server already applied is a double charge.
5. **Only allowlisted statuses are success.** Classify raw status strings with `TransactionStatusClassifier`; anything unrecognised is `unknown`, rendered like pending. Why: a backend that adds `"partially_settled"` must not show a green tick.
6. Users never see `failure.message`. Text comes from `FailureCopy`, keyed by failure type and known backend code. Why: `message` holds server text, stack traces and sometimes personal data.
7. Void operations return `Result<Unit>`, not `Result<void>`. Why: `Ok(unit)` is a real value you can compare in tests.
8. Feature code depends on `ApiClient`, never on Dio. `DioApiClient` is the only file importing `package:dio`. Why: tests fake one small interface, and the HTTP library can change without touching features.

## The taxonomy

`AppFailure` is sealed, `Equatable`, and carries `message` (developer text) and `code` (backend error code, when sent).

| Failure | Raised when | Safe to retry? |
|---|---|---|
| `NetworkFailure` | no connection on a read, or a write that provably never left | yes |
| `TimeoutFailure` | a read timed out, or a write timed out while connecting | yes |
| `UnauthorizedFailure` | 401 | after re-auth |
| `ForbiddenFailure` | 403 | no |
| `NotFoundFailure` | 404 | no |
| `ValidationFailure` | 400 / 422, with `fieldErrors` (field -> code) | after the user edits |
| `ConflictFailure` | 409 | after refresh |
| `RateLimitedFailure` | 429, with `retryAfter` | after the delay |
| `ServerFailure` | 5xx on a read, or an unlisted 4xx | reads only |
| `OutcomeUnknownFailure` | a write dropped, timed out after sending, got a 5xx, or a 2xx body failed to parse | **never automatically** |
| `CancelledFailure` | the caller cancelled a read | n/a |
| `UnexpectedFailure` | a bug: `TypeError`, `StateError`, unmapped exception | report it |

How `RequestGuard` decides, once `DioApiClient` has turned a `DioException` into an `ApiException`: a 2xx is `Ok`; a 4xx means the server refused and nothing was applied, mapped by status for reads and writes alike.
Anything else on a read is `TimeoutFailure`, `NetworkFailure`, `ServerFailure` or `CancelledFailure`.
Anything else on a write, including a non-`ApiException` throw (in practice a 2xx whose JSON did not match the model), is `OutcomeUnknownFailure`, unless `ApiException.requestSent` is false: only a Dio `connectionTimeout`, where the socket never connected.

## Mapping backend error codes

The guard copies the backend `code` onto every failure, so most codes need no mapping at all: `FailureCopy` looks up `failure.code.<code>` first.
Map a code to a different failure only when the app must *behave* differently. Pass `onApiError`; it is only consulted for 4xx, so it can never turn an unknown outcome into a refusal.

```dart
FutureResult<Recipient> findRecipient(String handle) => guardRead(
  () async => Recipient.fromJson((await _client.get('/recipients/$handle')).json),
  onApiError: (e) => switch (e.code) {
    'recipient_not_found' => ValidationFailure(
      fieldErrors: const {'handle': 'not_found'},
      code: e.code,
    ),
    _ => null, // default mapping by status
  },
);
```

## Worked example: a transfer that survives a dropped connection

The user taps "Send", the request leaves, the socket dies. Did the money move? The app cannot know, so it must not say "failed" (the user retries and pays twice) or "sent" (it may not have). It says "checking", reads the status, then decides.

Data layer: classify the raw status once, at the edge, so the domain never sees strings.

```dart
const _statuses = TransactionStatusClassifier(
  succeeded: {'completed'},
  failed: {'rejected', 'expired'},
  pending: {'created', 'processing'},
);

final class TransferRepositoryImpl
    with RequestGuard
    implements TransferRepository {
  TransferRepositoryImpl(this._client);

  final ApiClient _client;

  @override
  FutureResult<Transfer> submit(TransferDraft draft, {required String key}) =>
      guardWrite(() async {
        final res = await _client.post(
          '/transfers',
          body: {...draft.toJson(), 'idempotency_key': key},
        );
        return _toTransfer(res.json);
      });

  @override
  FutureResult<Transfer?> findByKey(String key) => guardRead(() async {
    final list = (await _client.get(
      '/transfers',
      query: {'idempotency_key': key},
    )).jsonList;
    return list.isEmpty ? null : _toTransfer(list.first as Map<String, dynamic>);
  });

  Transfer _toTransfer(Map<String, dynamic> json) => Transfer(
    id: json['id'] as String,
    outcome: _statuses.classify(json['status'] as String?),
  );
}
```

Cubit: fold the `Result` with a `switch`. The unknown branch reads, never re-submits.

```dart
enum TransferPhase { editing, submitting, checking, succeeded, failed, unconfirmed }

final class TransferCubit extends Cubit<TransferState>
    with SafeEmit<TransferState> {
  TransferCubit(
    this._repository, {
    required this.newKey,
    this.pollEvery = const Duration(seconds: 2),
    this.maxPolls = 10,
  }) : super(const TransferState());

  final TransferRepository _repository;
  final String Function() newKey;
  final Duration pollEvery;
  final int maxPolls;
  String? _key;

  Future<void> submit(TransferDraft draft) async {
    if (state.phase case TransferPhase.submitting || TransferPhase.checking) {
      return; // double tap
    }
    // Kept across a manual retry after an unknown outcome, so the server
    // dedupes it. Cleared only once the server has definitely answered.
    final key = _key ??= newKey();
    safeEmit(const TransferState(phase: TransferPhase.submitting));

    switch (await _repository.submit(draft, key: key)) {
      case Ok(:final value) when value.outcome.isTerminal:
        _settle(value);
      case Ok():
        await _reconcile(key); // accepted, still processing
      case Err(failure: OutcomeUnknownFailure()):
        await _reconcile(key);
      case Err(:final failure):
        _key = null; // refused: nothing was applied
        safeEmit(TransferState(phase: TransferPhase.failed, failure: failure));
    }
  }

  Future<void> _reconcile(String key) async {
    safeEmit(const TransferState(phase: TransferPhase.checking));
    for (var i = 0; i < maxPolls && !isClosed; i++) {
      await Future<void>.delayed(pollEvery);
      final found = (await _repository.findByKey(key)).valueOrNull;
      if (found != null && found.outcome.isTerminal) return _settle(found);
    }
    // Not "failed": it may still complete. The UI says "check your history
    // before trying again".
    safeEmit(const TransferState(phase: TransferPhase.unconfirmed));
  }

  void _settle(Transfer transfer) {
    _key = null;
    safeEmit(
      TransferState(
        phase: transfer.outcome == TransactionOutcome.succeeded
            ? TransferPhase.succeeded
            : TransferPhase.failed,
        transfer: transfer,
      ),
    );
  }
}
```

`SafeEmit` comes from `bloc-state-management`; a page popped mid-poll must not crash on emit. Note the `Ok()` branch: a 2xx is not a success. A `processing` or unrecognised status keeps polling, and `unknown` can only ever end in `unconfirmed`, never `succeeded`.

The regression test that keeps this honest:

```dart
blocTest<TransferCubit, TransferState>(
  'an unknown outcome is reconciled by reading, never re-submitted',
  setUp: () {
    when(() => repo.submit(draft, key: 'k1'))
        .thenAnswer((_) async => const Err(OutcomeUnknownFailure()));
    when(() => repo.findByKey('k1')).thenAnswer(
      (_) async => const Ok(
        Transfer(id: 't1', outcome: TransactionOutcome.succeeded),
      ),
    );
  },
  build: () => TransferCubit(repo, newKey: () => 'k1', pollEvery: Duration.zero),
  act: (cubit) => cubit.submit(draft),
  expect: () => [
    const TransferState(phase: TransferPhase.submitting),
    const TransferState(phase: TransferPhase.checking),
    isA<TransferState>().having((s) => s.phase, 'phase', TransferPhase.succeeded),
  ],
  verify: (_) => verify(() => repo.submit(draft, key: 'k1')).called(1),
);
```

If the backend supports an idempotency key, send it on every mutation, as above. It turns the user's manual "try again" after `unconfirmed` from a risk into a no-op.

## Folding a Result in a cubit

Use a `switch` with patterns. `fold` and `map` exist for one-liners, but a `switch` reads better once there are guards.

```dart
Future<void> load() async {
  safeEmit(state.copyWith(loading: true));
  switch (await _repository.fetchOrders(page: 1)) {
    case Ok(:final value):
      safeEmit(state.copyWith(loading: false, orders: value));
    case Err(failure: UnauthorizedFailure()):
      safeEmit(state.copyWith(loading: false, sessionExpired: true));
    case Err(:final failure):
      safeEmit(state.copyWith(loading: false, failure: failure));
  }
}
```

Keep the `AppFailure` itself in state, not a string. The view turns it into text, so copy changes and language switches never touch the cubit. For single actions with no other state, `ActionCubit<T>` from `bloc-state-management` already does this.

## User text: FailureCopy

`KeyedFailureCopy` takes a lookup function, so it works with gen-l10n, slang, easy_localization or a plain map, and has no l10n dependency of its own.

```dart
final copy = KeyedFailureCopy(
  lookup: (key) => switch (key) {
    'failure.network' => l10n.errorNoConnection,
    'failure.outcome_unknown' => l10n.errorCheckingStatus,
    'failure.code.card_expired' => l10n.errorCardExpired,
    _ => null,
  },
  fallback: l10n.errorGeneric,
);
Text(copy.of(state.failure!));
```

A known code wins, then the type key, then `fallback`, so a new backend code can never put raw server text on screen. `typeKey` is an exhaustive `switch`: a new failure type will not compile until it has copy. Treat `ValidationFailure.fieldErrors` values as codes too, and look them up the same way.

## Logging failures

Most failures are expected and need no report. Two are worth one:

```dart
void reportFailure(AppFailure failure, CrashReporterPort crash) {
  if (failure case UnexpectedFailure(:final error, :final stackTrace)) {
    crash.recordError(error, stackTrace, reason: 'unexpected_failure');
  } else if (failure case OutcomeUnknownFailure(:final code)) {
    crash.log(redact('outcome_unknown code=$code'));
  }
}
```

`message` and `ApiException.message` can contain server text with emails, phone numbers or tokens. Pass anything free-form through `redact` (from `bloc-sdk-ports`) before it reaches a log, and never log request bodies of money or auth calls.

## Extending the taxonomy

Sealed classes must be declared in the same library, so new failures go in `app_failure.dart` (or a `part` of it). Add a subclass only when the app must *behave* differently, for example showing a top-up button:

```dart
/// 409 with code `insufficient_funds`. The UI offers a top-up.
final class InsufficientFundsFailure extends AppFailure {
  const InsufficientFundsFailure({super.message, super.code});
}
```

Then map it with `onApiError` and add its key to `KeyedFailureCopy.typeKey`. Every exhaustive `switch` now fails to compile until it decides what to do, which is the point. If only the text differs, do not add a type: use the backend `code` and a `failure.code.<code>` string.

## Gotchas

- **Retry interceptors on POST.** A Dio retry interceptor that retries on timeout will happily resend a payment. Restrict automatic retry to GET, or to requests carrying an idempotency key the server honours.
- **`connectionError` is not "never sent".** Dio raises it for "connection closed before full header was received", after the body went out. `badCertificate` is checked after the response arrives. Only `connectionTimeout` proves nothing left the device; `DioApiClient` encodes this.
- **A 2xx that fails to parse.** A model change on the server makes `fromJson` throw after the transfer succeeded. `guardWrite` maps that to `OutcomeUnknownFailure`, not `UnexpectedFailure`, so the UI checks status instead of saying "failed".
- **Cancelling a mutation.** Wiring a `CancelToken` to page dispose on a POST cancels the client, not the server. Do not cancel writes; let them finish into a cubit that outlives the page, or reconcile later.
- **Inverted status checks.** `status == 'failed' ? failed : succeeded` renders every new status as success. Always test for the success allowlist, never against the failure list.
- **Equal failures do not re-emit.** Two identical `NetworkFailure()` states in a row are `==`, so a `BlocListener` toast fires once. Pass through a running state between attempts (as `submit` does), or include an attempt counter in state.
- **`catch (e) => NetworkFailure()`.** Turns a `TypeError` in your parser into "check your connection" forever. Unknown errors are `UnexpectedFailure`, and they get reported.

## Review checklist

- [ ] Every repository method returns `FutureResult<T>`; no `throw` escapes data code.
- [ ] Repository impls mix in `RequestGuard`; no other `try`/`catch` in `data/`.
- [ ] Every request that changes server state uses `guardWrite`, including "harmless" ones like marking read.
- [ ] `OutcomeUnknownFailure` is handled explicitly in money flows: reconcile by reading, never re-submit, never show "failed".
- [ ] Raw status strings are classified with an allowlist; `unknown` never renders as success; a test covers an unrecognised status.
- [ ] No retry interceptor or loop resends a non-idempotent request.
- [ ] Mutations send an idempotency key when the backend supports one.
- [ ] State stores `AppFailure`, the view renders `FailureCopy.of`, and `failure.message` appears in no widget.
- [ ] New backend codes have copy, or deliberately fall back to their type.
- [ ] Only `dio_api_client.dart` imports `package:dio`.
- [ ] `UnexpectedFailure` is reported; free-form text passes through `redact` first.
- [ ] Void operations return `Result<Unit>`.
