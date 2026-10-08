// Target: lib/features/orders/data/orders_repository_impl.dart
import 'package:app/core/network/request_guard.dart';
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/data/orders_api.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/domain/orders_repository.dart';

final class OrdersRepositoryImpl with RequestGuard implements OrdersRepository {
  OrdersRepositoryImpl(this._api);

  final OrdersApi _api;

  @override
  FutureResult<List<Order>> fetchOrders({required int page}) =>
      guardRead(() async {
        final models = await _api.fetchOrders(page: page);
        return [for (final model in models) model.toDomain()];
      });

  @override
  FutureResult<String> placeOrder(OrderDraft draft) =>
      guardWrite(() => _api.placeOrder(draft));
}
