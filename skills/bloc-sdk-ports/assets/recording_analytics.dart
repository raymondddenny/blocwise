// Target: lib/core/analytics/recording_analytics.dart
import 'package:app/core/analytics/analytics_port.dart';

/// Test fake that keeps every call, so tests assert on events directly.
final class RecordingAnalytics implements AnalyticsPort {
  final List<AnalyticsEvent> events = [];
  final List<String> identifiedUserIds = [];
  int resetCount = 0;

  List<E> eventsOfType<E extends AnalyticsEvent>() =>
      events.whereType<E>().toList();

  @override
  void track(AnalyticsEvent event) => events.add(event);

  @override
  void identify(String userId, {Map<String, Object?> traits = const {}}) =>
      identifiedUserIds.add(userId);

  @override
  void reset() => resetCount++;
}
