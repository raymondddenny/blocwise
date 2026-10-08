// Target: lib/features/orders/presentation/cubit/place_order_cubit.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:app/core/bloc/action_status.dart';
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/domain/orders_repository.dart';

/// One user action: place an order. Emits `ActionSucceeded<String>` with the
/// new order id; `OrdersEffectsListener` turns outcomes into navigation.
class PlaceOrderCubit extends ActionCubit<String> {
  PlaceOrderCubit(this._repository, this._analytics);

  final OrdersRepository _repository;
  final AnalyticsPort _analytics;

  /// A call while one is in flight is ignored (see `ActionCubit.run`).
  Future<void> place(OrderDraft draft) async {
    final result = await run(() => _repository.placeOrder(draft));
    // Track the confirmed outcome, not the tap: an unknown outcome is not a
    // conversion.
    if (result case Ok(:final value)) {
      _analytics.track(OrderPlaced(orderId: value, itemCount: draft.quantity));
    }
  }
}
