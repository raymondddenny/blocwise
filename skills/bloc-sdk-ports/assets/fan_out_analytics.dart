// Target: lib/core/analytics/fan_out_analytics.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:flutter/foundation.dart';

/// Sends every call to several vendors. One vendor throwing does not stop the
/// others, and never reaches the caller.
final class FanOutAnalytics implements AnalyticsPort {
  FanOutAnalytics(List<AnalyticsPort> targets)
    : _targets = List.unmodifiable(targets);

  final List<AnalyticsPort> _targets;

  @override
  void track(AnalyticsEvent event) => _each((t) => t.track(event));

  @override
  void identify(String userId, {Map<String, Object?> traits = const {}}) =>
      _each((t) => t.identify(userId, traits: traits));

  @override
  void reset() => _each((t) => t.reset());

  void _each(void Function(AnalyticsPort target) call) {
    for (final target in _targets) {
      try {
        call(target);
      } catch (e) {
        debugPrint('analytics target ${target.runtimeType} failed: $e');
      }
    }
  }
}
