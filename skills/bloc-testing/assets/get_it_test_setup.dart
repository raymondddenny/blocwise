// Target: test/helpers/get_it_test_setup.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:app/core/analytics/recording_analytics.dart';
import 'package:app/core/di/injector.dart';
import 'package:app/core/network/api_client.dart';

import 'fake_api_client.dart';

typedef TestDoubles = ({RecordingAnalytics analytics, FakeApiClient api});

/// Resets the locator and registers a fake for every port, under the PORT
/// type, so code that resolves `sl<AnalyticsPort>()` gets the recorder.
///
/// Call from `setUp`; pair with [tearDownLocator] in `tearDown`. Register a
/// mocktail mock for the one repository under test after this call.
Future<TestDoubles> setUpLocator() async {
  await sl.reset();
  final doubles = (analytics: RecordingAnalytics(), api: FakeApiClient());
  sl
    ..registerSingleton<AnalyticsPort>(doubles.analytics)
    ..registerSingleton<ApiClient>(doubles.api);
  return doubles;
}

/// Drops every registration so the next test starts empty. Without this a
/// singleton from one test (and the state it holds) leaks into the next.
Future<void> tearDownLocator() => sl.reset();
