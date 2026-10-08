// Target: lib/core/analytics/analytics_port.dart
import 'package:equatable/equatable.dart';

/// The app's analytics port. Features depend on this, never on a vendor SDK.
///
/// Calls are fire-and-forget: implementations must not throw and business
/// logic never awaits analytics.
abstract interface class AnalyticsPort {
  void track(AnalyticsEvent event);

  /// [userId] is an opaque internal id, never an email or phone number.
  void identify(String userId, {Map<String, Object?> traits = const {}});

  /// Call on logout so the next user is not merged into this one.
  void reset();
}

/// The closed vocabulary of events. Adding an event is a code change that a
/// reviewer sees, which is the point: no free-form names, no free-form
/// properties.
sealed class AnalyticsEvent extends Equatable {
  const AnalyticsEvent();

  /// snake_case, stable across releases: dashboards key on it.
  String get name;

  /// Low-cardinality values only: enums, booleans, small counts, buckets.
  Map<String, Object?> get properties;

  @override
  List<Object?> get props => [name, properties];
}

final class ScreenViewed extends AnalyticsEvent {
  const ScreenViewed(this.screen);

  /// A route name such as `order_detail`, not a path with ids in it.
  final String screen;

  @override
  String get name => 'screen_viewed';

  @override
  Map<String, Object?> get properties => {'screen': screen};
}

enum SignInMethod { password, google, apple, passkey }

final class SignInCompleted extends AnalyticsEvent {
  const SignInCompleted(this.method);

  final SignInMethod method;

  @override
  String get name => 'sign_in_completed';

  @override
  Map<String, Object?> get properties => {'method': method.name};
}

final class OrderPlaced extends AnalyticsEvent {
  const OrderPlaced({required this.orderId, this.itemCount, this.currency});

  /// Opaque server id, the one id-valued property: vendors de-duplicate
  /// purchase events on it and it joins analytics to backend records. Never
  /// use it as a chart dimension.
  final String orderId;

  final int? itemCount;

  /// ISO 4217 code. The amount itself stays out of analytics.
  final String? currency;

  @override
  String get name => 'order_placed';

  @override
  Map<String, Object?> get properties => {
    'order_id': orderId,
    'item_count': ?itemCount,
    'currency': ?currency,
  };
}

final class UserActionFailed extends AnalyticsEvent {
  const UserActionFailed({required this.action, required this.reason});

  /// e.g. `place_order`.
  final String action;

  /// A failure type key such as `network`, never server text.
  final String reason;

  @override
  String get name => 'action_failed';

  @override
  Map<String, Object?> get properties => {'action': action, 'reason': reason};
}
