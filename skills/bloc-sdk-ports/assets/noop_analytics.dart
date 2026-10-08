// Target: lib/core/analytics/noop_analytics.dart
import 'package:app/core/analytics/analytics_port.dart';

/// Used when analytics is disabled, unconfigured, or its SDK failed to start.
final class NoopAnalytics implements AnalyticsPort {
  const NoopAnalytics();

  @override
  void track(AnalyticsEvent event) {}

  @override
  void identify(String userId, {Map<String, Object?> traits = const {}}) {}

  @override
  void reset() {}
}
