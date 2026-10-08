// Target: lib/core/failures/app_failure.dart
import 'package:equatable/equatable.dart';

/// Every way an operation can fail, as a closed set.
///
/// [message] is developer text for logs; users see `FailureCopy.of`, never
/// this. [code] is the backend error code, when the server sent one.
sealed class AppFailure extends Equatable {
  const AppFailure({this.message = '', this.code});

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];
}

/// The device could not reach the server. Nothing was applied.
final class NetworkFailure extends AppFailure {
  const NetworkFailure({super.message, super.code});
}

/// A read timed out, or a write timed out before it left the device.
final class TimeoutFailure extends AppFailure {
  const TimeoutFailure({super.message, super.code});
}

/// 401: the session is missing or expired.
final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure({super.message, super.code});
}

/// 403: authenticated, but not allowed to do this.
final class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure({super.message, super.code});
}

/// 404.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({super.message, super.code});
}

/// 400/422: the server refused the input. [fieldErrors] maps field -> code.
final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    this.fieldErrors = const {},
    super.message,
    super.code,
  });

  final Map<String, String> fieldErrors;

  @override
  List<Object?> get props => [...super.props, fieldErrors];
}

/// 409: the request conflicts with current server state.
final class ConflictFailure extends AppFailure {
  const ConflictFailure({super.message, super.code});
}

/// 429. [retryAfter] comes from the Retry-After header when present.
final class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure({this.retryAfter, super.message, super.code});

  final Duration? retryAfter;

  @override
  List<Object?> get props => [...super.props, retryAfter];
}

/// A definitive error status with no more specific type: 5xx on a read, or an
/// unlisted 4xx.
final class ServerFailure extends AppFailure {
  const ServerFailure({required this.statusCode, super.message, super.code});

  final int statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

/// A mutating request may have been applied: the connection dropped, it timed
/// out after sending, the server answered 5xx, or a 2xx body was unreadable.
/// Never retry automatically; reconcile by reading the resource's status.
final class OutcomeUnknownFailure extends AppFailure {
  const OutcomeUnknownFailure({this.cause, super.message, super.code});

  final Object? cause;

  @override
  List<Object?> get props => [...super.props, cause];
}

/// The caller cancelled before the request was sent.
final class CancelledFailure extends AppFailure {
  const CancelledFailure({super.message, super.code});
}

/// A bug or an unmapped error. Report it; it should not happen.
final class UnexpectedFailure extends AppFailure {
  UnexpectedFailure(this.error, [this.stackTrace])
    : super(message: error.toString());

  final Object error;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [...super.props, error];
}
