// Target: test/core/network/request_guard_test.dart
//
// Pins the failure mapping every repository inherits. A feature repository
// test repeats the same table against its own methods: one test per branch.
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/request_guard.dart';
import 'package:app/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api_client.dart';

/// Smallest repository shape: one read, one write, both through the guard.
class _ProbeRepository with RequestGuard {
  _ProbeRepository(this._api);

  final ApiClient _api;

  FutureResult<int> count() => guardRead(() async {
    final res = await _api.get('/items/count');
    return (res.data! as Map<String, Object?>)['count']! as int;
  });

  FutureResult<String> create() => guardWrite(() async {
    final res = await _api.post('/items', body: {'name': 'a'});
    return (res.data! as Map<String, Object?>)['id']! as String;
  });
}

AppFailure? _failureOf(Result<Object?> r) => switch (r) {
  Ok() => null,
  Err(:final failure) => failure,
};

void main() {
  late FakeApiClient api;
  late _ProbeRepository repository;

  setUp(() {
    api = FakeApiClient();
    repository = _ProbeRepository(api);
  });

  group('guardRead', () {
    test('2xx becomes Ok with the parsed value', () async {
      api.enqueue('GET', '/items/count', FakeReply.ok({'count': 3}));

      final result = await repository.count();

      expect(result, isA<Ok<int>>().having((r) => r.value, 'value', 3));
    });

    final cases = <String, (FakeReply, Matcher)>{
      'connection drop': (FakeReply.connectionDrop(), isA<NetworkFailure>()),
      'timeout': (FakeReply.timeout(), isA<TimeoutFailure>()),
      'connect timeout': (FakeReply.connectTimeout(), isA<TimeoutFailure>()),
      '401': (FakeReply.status(401), isA<UnauthorizedFailure>()),
      '403': (FakeReply.status(403), isA<ForbiddenFailure>()),
      '404': (FakeReply.status(404), isA<NotFoundFailure>()),
      '409': (FakeReply.status(409), isA<ConflictFailure>()),
      '422': (FakeReply.status(422), isA<ValidationFailure>()),
      '429': (FakeReply.status(429), isA<RateLimitedFailure>()),
      '503': (
        FakeReply.status(503),
        isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 503),
      ),
      'non-API error (parsing bug)': (
        FakeReply.ok({'count': 'three'}),
        isA<UnexpectedFailure>(),
      ),
    };

    for (final MapEntry(key: name, value: (reply, matcher)) in cases.entries) {
      test('$name maps to the expected failure', () async {
        api.enqueue('GET', '/items/count', reply);

        expect(_failureOf(await repository.count()), matcher);
      });
    }
  });

  group('guardWrite', () {
    // The request may have been applied: never a plain network/server error,
    // so the UI reconciles by reading state instead of offering "try again".
    final unknownOutcome = <String, FakeReply>{
      'connection drop': FakeReply.connectionDrop(),
      'timeout': FakeReply.timeout(),
      '500': FakeReply.status(500),
      '502': FakeReply.status(502),
      // A 2xx arrived, so the write happened; only its body is unreadable.
      'unreadable 2xx body': FakeReply.ok({'id': 42}),
    };

    for (final MapEntry(key: name, value: reply) in unknownOutcome.entries) {
      test('$name maps to OutcomeUnknownFailure', () async {
        api.enqueue('POST', '/items', reply);

        expect(
          _failureOf(await repository.create()),
          isA<OutcomeUnknownFailure>(),
        );
      });
    }

    test('a connect timeout proves nothing was sent: plain timeout', () async {
      // Only Dio's connectionTimeout sets requestSent: false. Every other
      // transport error may have reached the server.
      api.enqueue('POST', '/items', FakeReply.connectTimeout());

      expect(_failureOf(await repository.create()), isA<TimeoutFailure>());
    });

    test('4xx is a definite refusal, not an unknown outcome', () async {
      api.enqueue('POST', '/items', FakeReply.status(409, code: 'DUPLICATE'));

      final failure = _failureOf(await repository.create());

      expect(
        failure,
        isA<ConflictFailure>().having((f) => f.code, 'code', 'DUPLICATE'),
      );
    });

    test('the guard never retries a write', () async {
      api.enqueue('POST', '/items', FakeReply.status(503));

      await repository.create();

      expect(api.callCount('POST', '/items'), 1);
    });
  });
}
