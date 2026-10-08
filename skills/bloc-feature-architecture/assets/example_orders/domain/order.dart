// Target: lib/features/orders/domain/order.dart
import 'package:equatable/equatable.dart';

/// Where an order stands. An unrecognised backend status parses to [unknown],
/// which the view renders like [pending], never like [paid].
enum OrderStatus { pending, paid, cancelled, unknown }

final class Order extends Equatable {
  const Order({
    required this.id,
    required this.totalCents,
    required this.status,
  });

  final String id;

  /// Minor units of the order currency. The view formats it.
  final int totalCents;
  final OrderStatus status;

  @override
  List<Object?> get props => [id, totalCents, status];
}

/// What the user asks for. The server prices it and assigns the id.
final class OrderDraft extends Equatable {
  const OrderDraft({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  @override
  List<Object?> get props => [productId, quantity];
}
