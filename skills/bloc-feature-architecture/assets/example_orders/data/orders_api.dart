// Target: lib/features/orders/data/orders_api.dart
import 'package:app/core/network/api_client.dart';
import 'package:app/features/orders/data/order_model.dart';
import 'package:app/features/orders/domain/order.dart';

/// Endpoint paths and request bodies for orders. Throws [ApiException] or a
/// parsing error; the repository turns both into failures.
final class OrdersApi {
  const OrdersApi(this._client);

  final ApiClient _client;

  static const _orders = '/orders';

  Future<List<OrderModel>> fetchOrders({required int page}) async {
    final response = await _client.get(_orders, query: {'page': page});
    return [
      for (final item in response.jsonList)
        OrderModel.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Returns the created order's id.
  Future<String> placeOrder(OrderDraft draft) async {
    final response = await _client.post(
      _orders,
      body: {'product_id': draft.productId, 'quantity': draft.quantity},
    );
    return response.json['id'] as String;
  }
}
