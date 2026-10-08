// Target: lib/core/network/dio_api_client.dart
import 'package:app/core/network/api_client.dart';
import 'package:dio/dio.dart';

/// Reads the backend's error envelope. Replace it to match your API.
typedef ErrorBodyParser =
    ({String? code, String? message, Map<String, String> fieldErrors}) Function(
      Object? body,
    );

/// The only file in the app that imports Dio.
final class DioApiClient implements ApiClient {
  DioApiClient(this._dio, {ErrorBodyParser? parseErrorBody})
    : _parseErrorBody = parseErrorBody ?? defaultErrorBody;

  final Dio _dio;
  final ErrorBodyParser _parseErrorBody;

  @override
  Future<ApiResponse> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query));

  @override
  Future<ApiResponse> post(String path, {Object? body}) =>
      _send(() => _dio.post<Object?>(path, data: body));

  @override
  Future<ApiResponse> put(String path, {Object? body}) =>
      _send(() => _dio.put<Object?>(path, data: body));

  @override
  Future<ApiResponse> delete(String path) =>
      _send(() => _dio.delete<Object?>(path));

  Future<ApiResponse> _send(Future<Response<Object?>> Function() call) async {
    try {
      final response = await call();
      return ApiResponse(
        statusCode: response.statusCode ?? 200,
        data: response.data,
      );
    } on DioException catch (e, stack) {
      Error.throwWithStackTrace(_toApiException(e), stack);
    }
  }

  ApiException _toApiException(DioException e) {
    final message = '${e.type.name}: ${e.message ?? e.error ?? ''}';
    switch (e.type) {
      // The connect phase never completed, so no request bytes were written.
      case DioExceptionType.connectionTimeout:
        return ApiException(
          message: message,
          isTimeout: true,
          requestSent: false,
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(message: message, isTimeout: true);
      case DioExceptionType.cancel:
        return ApiException(message: message, isCancelled: true);
      case DioExceptionType.badResponse:
        final response = e.response;
        final body = _parseErrorBody(response?.data);
        return ApiException(
          statusCode: response?.statusCode,
          code: body.code,
          message: body.message ?? message,
          fieldErrors: body.fieldErrors,
          retryAfter: _retryAfter(response?.headers.value('retry-after')),
        );
      // connectionError fires both before sending and after ("connection
      // closed before full header"), and certificates are checked after the
      // response, so none of the rest proves the request was not sent.
      default:
        return ApiException(message: message, isConnection: true);
    }
  }

  static Duration? _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

/// Accepts `{"code": ..., "message": ..., "errors": {"field": "code"}}`, also
/// nested under `"error"`.
({String? code, String? message, Map<String, String> fieldErrors})
defaultErrorBody(Object? body) {
  final map = switch (body) {
    {'error': final Map<String, dynamic> inner} => inner,
    final Map<String, dynamic> map => map,
    _ => const <String, dynamic>{},
  };
  final errors = map['errors'];
  return (
    code: map['code']?.toString(),
    message: map['message']?.toString(),
    fieldErrors: errors is Map
        ? {for (final e in errors.entries) '${e.key}': '${e.value}'}
        : const {},
  );
}
