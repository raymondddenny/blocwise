// Target: lib/core/failures/failure_copy.dart
import 'package:app/core/failures/app_failure.dart';

/// User-facing text for a failure. Never shows `failure.message`.
abstract interface class FailureCopy {
  String of(AppFailure failure);
}

/// Resolves text through a key lookup, so it works with any l10n setup.
///
/// A known backend code (`failure.code.<code>`) wins over the type key
/// (`failure.network`, ...). Unknown codes fall back to the type key, so a
/// new server code can never leak raw text to the screen.
final class KeyedFailureCopy implements FailureCopy {
  const KeyedFailureCopy({required this.lookup, required this.fallback});

  /// Returns the localized string for a key, or null when there is none.
  final String? Function(String key) lookup;

  /// Shown when neither the code nor the type has a string.
  final String fallback;

  @override
  String of(AppFailure failure) {
    final code = failure.code;
    final byCode = code == null ? null : lookup('failure.code.$code');
    return byCode ?? lookup(typeKey(failure)) ?? fallback;
  }

  /// Exhaustive on purpose: a new failure type will not compile until it has
  /// a key.
  static String typeKey(AppFailure failure) => switch (failure) {
    NetworkFailure() => 'failure.network',
    TimeoutFailure() => 'failure.timeout',
    UnauthorizedFailure() => 'failure.unauthorized',
    ForbiddenFailure() => 'failure.forbidden',
    NotFoundFailure() => 'failure.not_found',
    ValidationFailure() => 'failure.validation',
    ConflictFailure() => 'failure.conflict',
    RateLimitedFailure() => 'failure.rate_limited',
    ServerFailure() => 'failure.server',
    OutcomeUnknownFailure() => 'failure.outcome_unknown',
    CancelledFailure() => 'failure.cancelled',
    UnexpectedFailure() => 'failure.unexpected',
  };
}
