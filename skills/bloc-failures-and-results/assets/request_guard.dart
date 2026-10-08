// Target: lib/core/network/request_guard.dart
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/result/result.dart';

/// Maps a refused (4xx) response to a more specific failure, or null to keep
/// the default mapping.
typedef ApiErrorMapper = AppFailure? Function(ApiException e);

/// The only try/catch in data code. Mix into repository implementations.
mixin RequestGuard {
  /// For requests with no side effect. Failures are safe to retry.
  FutureResult<T> guardRead<T>(
    Future<T> Function() call, {
    ApiErrorMapper? onApiError,
  }) async {
    try {
      return Ok(await call());
    } on ApiException catch (e) {
      if (e.isRefused) return Err(onApiError?.call(e) ?? _refused(e));
      return Err(_unreachable(e));
    } catch (e, stack) {
      return Err(UnexpectedFailure(e, stack));
    }
  }

  /// For requests that change server state. Anything other than a 2xx with a
  /// readable body or a 4xx refusal becomes [OutcomeUnknownFailure], unless the
  /// request provably never left the device.
  FutureResult<T> guardWrite<T>(
    Future<T> Function() call, {
    ApiErrorMapper? onApiError,
  }) async {
    try {
      return Ok(await call());
    } on ApiException catch (e) {
      if (e.isRefused) return Err(onApiError?.call(e) ?? _refused(e));
      if (!e.requestSent) return Err(_unreachable(e));
      return Err(
        OutcomeUnknownFailure(message: e.message, code: e.code, cause: e),
      );
    } catch (e) {
      // Usually a 2xx whose body failed to parse: the write happened.
      return Err(
        OutcomeUnknownFailure(message: 'Unreadable write result: $e', cause: e),
      );
    }
  }
}

AppFailure _unreachable(ApiException e) {
  if (e.isCancelled) return CancelledFailure(message: e.message);
  if (e.isTimeout) return TimeoutFailure(message: e.message);
  final status = e.statusCode;
  if (status != null) {
    return ServerFailure(statusCode: status, message: e.message, code: e.code);
  }
  return NetworkFailure(message: e.message);
}

AppFailure _refused(ApiException e) => switch (e.statusCode!) {
  400 || 422 => ValidationFailure(
    fieldErrors: e.fieldErrors,
    message: e.message,
    code: e.code,
  ),
  401 => UnauthorizedFailure(message: e.message, code: e.code),
  403 => ForbiddenFailure(message: e.message, code: e.code),
  404 => NotFoundFailure(message: e.message, code: e.code),
  409 => ConflictFailure(message: e.message, code: e.code),
  429 => RateLimitedFailure(
    retryAfter: e.retryAfter,
    message: e.message,
    code: e.code,
  ),
  final status => ServerFailure(
    statusCode: status,
    message: e.message,
    code: e.code,
  ),
};
