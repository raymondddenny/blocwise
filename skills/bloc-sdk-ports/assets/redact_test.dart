// Target: test/core/logging/redact_test.dart
import 'package:app/core/logging/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redact', () {
    test('masks a token in a URL query string', () {
      expect(
        redact('open https://kyc.example/s?token=abc123&lang=en'),
        'open https://kyc.example/s?token=***&lang=en',
      );
    });

    test('masks compound secret names', () {
      expect(
        redact('cb?session_id=s1&X-Amz-Credential=c2&page=3'),
        'cb?session_id=***&X-Amz-Credential=***&page=3',
      );
    });

    test('masks a JWE whose second part is empty', () {
      expect(
        redact('link /s/eyJhbGciOiJkaXIifQ..iv.cipher.tag end'),
        'link /s/<jwt> end',
      );
    });

    test('masks emails and leaves ordinary text alone', () {
      expect(redact('mail a.b@example.com now'), 'mail <email> now');
      expect(redact('order 42 shipped'), 'order 42 shipped');
    });
  });
}
