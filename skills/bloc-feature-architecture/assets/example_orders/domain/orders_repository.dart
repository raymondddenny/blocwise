// Target: lib/features/orders/domain/orders_repository.dart
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/domain/order.dart';

abstract interface class OrdersRepository {
  /// One page of orders, newest first. [page] starts at 1; an empty list
  /// means there are no more pages.
  FutureResult<List<Order>> fetchOrders({required int page});

  /// Returns the new order's id. An `OutcomeUnknownFailure` means the order
  /// may exist: reconcile by reading [fetchOrders], never by placing again.
  FutureResult<String> placeOrder(OrderDraft draft);
}
