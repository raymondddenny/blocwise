// Target: lib/core/network/api_client.dart

/// The app's HTTP port. Feature code depends on this, never on Dio.
///
/// Implementations return 2xx responses and throw [ApiException] for
/// everything else.
abstract interface class ApiClient {
  Future<ApiResponse> get(String path, {Map<String, Object?>? query});

  Future<ApiResponse> post(String path, {Object? body});

  Future<ApiResponse> put(String path, {Object? body});

  Future<ApiResponse> delete(String path);
}

final class ApiResponse {
  const ApiResponse({required this.statusCode, this.data});

  final int statusCode;

  /// Decoded JSON: a `Map<String, dynamic>`, a `List`, a primitive or null.
  final Object? data;

  /// [data] as a JSON object. Throws [FormatException] for any other shape.
  Map<String, dynamic> get json => switch (data) {
    final Map<String, dynamic> map => map,
    _ => throw FormatException('Expected a JSON object, got $data'),
  };

  /// [data] as a JSON array. Throws [FormatException] for any other shape.
  List<dynamic> get jsonList => switch (data) {
    final List<dynamic> list => list,
    _ => throw FormatException('Expected a JSON array, got $data'),
  };
}

/// A transport or HTTP failure, independent of the HTTP library.
final class ApiException implements Exception {
  const ApiException({
    this.statusCode,
    this.code,
    this.message = '',
    this.isTimeout = false,
    this.isConnection = false,
    this.isCancelled = false,
    this.requestSent = true,
    this.fieldErrors = const {},
    this.retryAfter,
  });

  /// Null when no response arrived.
  final int? statusCode;

  /// Backend error code from the error body.
  final String? code;

  /// Developer text. May contain server text: redact before logging.
  final String message;
  final bool isTimeout;
  final bool isConnection;
  final bool isCancelled;

  /// False only when the request provably never left the device. Defaults to
  /// true because "maybe sent" is the safe assumption for writes.
  final bool requestSent;
  final Map<String, String> fieldErrors;
  final Duration? retryAfter;

  /// The server answered and refused: nothing was applied.
  bool get isRefused =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  String toString() =>
      'ApiException(status: $statusCode, code: $code, timeout: $isTimeout, '
      'connection: $isConnection, cancelled: $isCancelled, '
      'sent: $requestSent)';
}
