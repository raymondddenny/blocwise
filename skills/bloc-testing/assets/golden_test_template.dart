// Target: test/goldens/order_tile_golden_test.dart
//
// Copy per widget as test/goldens/<widget>_golden_test.dart and add to
// dart_test.yaml:
//
//   tags:
//     golden:
//
// Goldens run only on the pinned CI image (font antialiasing differs between
// machines). Update them there: `flutter test --tags golden --update-goldens`
// in the same container, and commit only images produced by that run.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// The pinned golden host. Change to match your CI image.
final _isGoldenHost = Platform.isLinux;

const _boundary = Key('golden');

/// Replace with the widget under test, built from fixed data.
Widget _subject({required bool dense}) => Card(
  child: ListTile(
    dense: dense,
    title: const Text('Order o-1'),
    subtitle: const Text('Paid'),
    trailing: const Text('12.50'),
  ),
);

void main() {
  for (final dense in [false, true]) {
    testWidgets('order tile, dense: $dense', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        RepaintBoundary(
          key: _boundary,
          child: _subject(dense: dense),
        ),
        theme: ThemeData(useMaterial3: true),
      );

      await expectLater(
        find.byKey(_boundary),
        matchesGoldenFile('goldens/order_tile_dense_$dense.png'),
      );
    }, skip: !_isGoldenHost);
  }
}
