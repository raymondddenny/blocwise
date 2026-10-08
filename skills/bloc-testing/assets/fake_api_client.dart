// Target: test/helpers/fake_api_client.dart
import 'package:app/core/network/api_client.dart';

/// One scripted answer for a request: a response or a thrown [ApiException].
final class FakeReply {
  const FakeReply._({this.response, this.error});

  /// A 2xx response carrying [data] (decoded JSON: Map, List, String, num).
  factory FakeReply.ok([Object? data, int statusCode = 200]) => FakeReply._(
    response: ApiResponse(statusCode: statusCode, data: data),
  );

  /// A non-2xx answer, thrown the way the real adapter throws it.
  factory FakeReply.status(int statusCode, {String? code}) => FakeReply._(
    error: ApiException(
      statusCode: statusCode,
      code: code,
      message: 'HTTP $statusCode',
    ),
  );

  /// The request never reached the server, or the reply never came back.
  factory FakeReply.connectionDrop() => FakeReply._(
    error: ApiException(message: 'connection dropped', isConnection: true),
  );

  /// Sent, then no answer in time: the server may have acted on it.
  factory FakeReply.timeout() =>
      FakeReply._(error: ApiException(message: 'timed out', isTimeout: true));

  /// The connection never opened, so nothing was sent (Dio's
  /// `connectionTimeout`). The only failure that proves a write did not land.
  factory FakeReply.connectTimeout() => FakeReply._(
    error: ApiException(
      message: 'connect timed out',
      isTimeout: true,
      requestSent: false,
    ),
  );

  /// Anything that is not an [ApiException], e.g. a parsing bug.
  factory FakeReply.crash(Object error) => FakeReply._(error: error);

  final ApiResponse? response;
  final Object? error;
}

typedef RecordedCall = ({
  String method,
  String path,
  Object? body,
  Map<String, Object?>? query,
});

/// Scriptable [ApiClient] for repository tests. No Dio, no HTTP, no mocks.
///
/// Replies are queued per `METHOD path` and consumed in order; the last one
/// repeats. An unscripted request throws [StateError] so a test never
/// passes by accident.
class FakeApiClient implements ApiClient {
  final _replies = <String, List<FakeReply>>{};

  /// Every request made, in order, for asserting what was sent.
  final List<RecordedCall> calls = [];

  void enqueue(String method, String path, FakeReply reply) =>
      _replies.putIfAbsent(_key(method, path), () => []).add(reply);

  int callCount(String method, String path) =>
      calls.where((c) => c.method == method && c.path == path).length;

  @override
  Future<ApiResponse> get(String path, {Map<String, Object?>? query}) =>
      _answer('GET', path, query: query);

  @override
  Future<ApiResponse> post(String path, {Object? body}) =>
      _answer('POST', path, body: body);

  @override
  Future<ApiResponse> put(String path, {Object? body}) =>
      _answer('PUT', path, body: body);

  @override
  Future<ApiResponse> delete(String path) => _answer('DELETE', path);

  Future<ApiResponse> _answer(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
  }) async {
    calls.add((method: method, path: path, body: body, query: query));
    final queue = _replies[_key(method, path)];
    if (queue == null || queue.isEmpty) {
      throw StateError('FakeApiClient: no reply scripted for $method $path');
    }
    final reply = queue.length > 1 ? queue.removeAt(0) : queue.first;
    final error = reply.error;
    if (error != null) throw error;
    return reply.response!;
  }

  static String _key(String method, String path) => '$method $path';
}
