// Target: test/core/flags/flag_defaults_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/flags/flag_defaults.dart';
import 'package:app/core/flags/flag_keys.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements FlagsSourcePort {
  Map<String, Object?> values = {};
  Object? error;
  int fetches = 0;

  @override
  Future<Map<String, Object?>> fetch(Iterable<String> keys) async {
    fetches++;
    if (error case final e?) throw e;
    return {
      for (final k in keys)
        if (values.containsKey(k)) k: values[k],
    };
  }
}

void main() {
  group('registry', () {
    test('every key declared in FlagKeys is listed in FlagKeys.all', () {
      // Reads the source so a key added as a constant but not to `all`
      // (and therefore never fetched) fails here instead of in production.
      final source = File('lib/core/flags/flag_keys.dart').readAsStringSync();
      final declared = RegExp(r"static const \w+ = '([^']+)'")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(declared, isNotEmpty);
      expect(FlagKeys.all.toSet(), declared);
    });

    test('every key has exactly one default, and no orphan defaults', () {
      expect(FlagKeys.all.toSet(), hasLength(FlagKeys.all.length));
      expect(flagDefaults.keys.toSet(), FlagKeys.all.toSet());
    });

    test('keys follow the naming grammar', () {
      final snake = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');
      for (final key in FlagKeys.all) {
        expect(key, matches(snake), reason: '$key is not snake_case');
        expect(
          key,
          isNot(
            anyOf(startsWith('is_'), startsWith('enable_'), endsWith('_flag')),
          ),
          reason: '$key: booleans end in _enabled, nothing else',
        );
      }
    });

    test('defaults have the shape their name promises', () {
      for (final MapEntry(:key, :value) in flagDefaults.entries) {
        if (key.endsWith('_enabled')) {
          expect(value, isA<bool>(), reason: key);
        } else if (key.endsWith('_variant')) {
          expect(value, 'control', reason: key);
        } else if (value is String && value.startsWith('{')) {
          expect(jsonDecode(value), isA<Map<String, Object?>>(), reason: key);
        }
      }
    });
  });

  group('FeatureFlags', () {
    late _FakeSource source;
    late FeatureFlags flags;

    setUp(() {
      source = _FakeSource();
      flags = FeatureFlags(source);
    });
    tearDown(() => flags.dispose());

    test('before the first fetch every read is the default', () {
      expect(flags.getBool(FlagKeys.newCheckoutEnabled), isFalse);
      expect(flags.getBool(FlagKeys.cardPaymentsEnabled), isTrue);
      expect(flags.getList(FlagKeys.hiddenPaymentMethods), isEmpty);
      expect(flags.getJson(FlagKeys.appUpdate)['min_build'], 0);
    });

    test('remote values win once fetched', () async {
      source.values = {
        FlagKeys.newCheckoutEnabled: true,
        FlagKeys.hiddenPaymentMethods: 'wallet, bank_transfer,',
        FlagKeys.appUpdate: {'min_build': 42, 'store_url': 'x'},
      };

      await flags.reload();

      expect(flags.getBool(FlagKeys.newCheckoutEnabled), isTrue);
      expect(flags.getList(FlagKeys.hiddenPaymentMethods), [
        'wallet',
        'bank_transfer',
      ]);
      expect(flags.getJson(FlagKeys.appUpdate)['min_build'], 42);
    });

    test(
      'a kill switch missing from the vendor reopens (why: 0%, not delete)',
      () async {
        source.values = {FlagKeys.cardPaymentsEnabled: false};
        await flags.reload();
        expect(flags.getBool(FlagKeys.cardPaymentsEnabled), isFalse);

        source.values = {}; // flag deleted or deactivated in the console
        await flags.reload();

        expect(flags.getBool(FlagKeys.cardPaymentsEnabled), isTrue);
      },
    );

    test('wrong types and malformed JSON fall back to the default', () async {
      source.values = {
        FlagKeys.newCheckoutEnabled: 'yes',
        FlagKeys.appUpdate: '{not json',
      };

      await flags.reload();

      expect(flags.getBool(FlagKeys.newCheckoutEnabled), isFalse);
      expect(flags.getJson(FlagKeys.appUpdate)['min_build'], 0);
    });

    test('a failed fetch keeps the previous snapshot', () async {
      source.values = {FlagKeys.newCheckoutEnabled: true};
      await flags.reload();

      source.error = const SocketException('offline');
      await flags.reload();

      expect(flags.getBool(FlagKeys.newCheckoutEnabled), isTrue);
    });

    test('unknown variant is control', () async {
      source.values = {FlagKeys.onboardingVariant: 'short_copy_v2'};
      await flags.reload();

      expect(
        flags.getVariant(FlagKeys.onboardingVariant, const {'short_copy'}),
        'control',
      );
    });

    test(
      'overlapping reloads share one fetch and notify on change only',
      () async {
        var notified = 0;
        flags.addListener(() => notified++);
        source.values = {FlagKeys.newCheckoutEnabled: true};

        await Future.wait([flags.reload(), flags.reload()]);
        await flags.reload(); // same values

        expect(source.fetches, 2);
        expect(notified, 1);
      },
    );
  });
}
