// Target: lib/features/orders/data/order_model.dart
import 'package:app/features/orders/domain/order.dart';

/// The JSON shape of an order. Never leaves `data/`.
final class OrderModel {
  const OrderModel({
    required this.id,
    required this.totalCents,
    required this.status,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
    id: json['id'] as String,
    totalCents: json['total_cents'] as int,
    status: json['status'] as String?,
  );

  final String id;
  final int totalCents;
  final String? status;

  Order toDomain() =>
      Order(id: id, totalCents: totalCents, status: _parseStatus(status));

  /// Explicit list: a new or misspelled status becomes `unknown`, so it can
  /// never render as paid.
  static OrderStatus _parseStatus(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'pending' => OrderStatus.pending,
        'paid' => OrderStatus.paid,
        'cancelled' || 'canceled' => OrderStatus.cancelled,
        _ => OrderStatus.unknown,
      };
}
