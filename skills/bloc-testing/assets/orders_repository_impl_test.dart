// Target: test/features/orders/data/orders_repository_impl_test.dart
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/data/orders_api.dart';
import 'package:app/features/orders/data/orders_repository_impl.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_api_client.dart';

const _draft = OrderDraft(productId: 'p-9', quantity: 2);

void main() {
  late FakeApiClient api;
  late OrdersRepositoryImpl repository;

  setUp(() {
    api = FakeApiClient();
    repository = OrdersRepositoryImpl(OrdersApi(api));
  });

  test(
    'fetchOrders parses a page; an unknown status never reads as paid',
    () async {
      api.enqueue(
        'GET',
        '/orders',
        FakeReply.ok([
          {'id': 'o-1', 'total_cents': 1250, 'status': 'paid'},
          {'id': 'o-2', 'total_cents': 990, 'status': 'settled_v2'},
        ]),
      );

      final result = await repository.fetchOrders(page: 3);

      expect(result.valueOrNull, const [
        Order(id: 'o-1', totalCents: 1250, status: OrderStatus.paid),
        Order(id: 'o-2', totalCents: 990, status: OrderStatus.unknown),
      ]);
      expect(api.calls.single.query, {'page': 3});
    },
  );

  test('placeOrder sends the draft and returns the new id', () async {
    api.enqueue('POST', '/orders', FakeReply.ok({'id': 'o-3'}, 201));

    final result = await repository.placeOrder(_draft);

    expect(result, const Ok('o-3'));
    expect(api.calls.single.body, {'product_id': 'p-9', 'quantity': 2});
  });

  test(
    'placeOrder: a dropped connection is an unknown outcome, sent once',
    () async {
      api.enqueue('POST', '/orders', FakeReply.connectionDrop());

      final result = await repository.placeOrder(_draft);

      expect(result.failureOrNull, isA<OutcomeUnknownFailure>());
      expect(api.callCount('POST', '/orders'), 1);
    },
  );

  test('placeOrder: a 422 is a refusal that keeps the backend code', () async {
    api.enqueue('POST', '/orders', FakeReply.status(422, code: 'out_of_stock'));

    final result = await repository.placeOrder(_draft);

    expect(
      result.failureOrNull,
      isA<ValidationFailure>().having((f) => f.code, 'code', 'out_of_stock'),
    );
  });
}
