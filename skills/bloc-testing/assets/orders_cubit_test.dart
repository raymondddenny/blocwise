// Target: test/features/orders/presentation/cubit/orders_cubit_test.dart
//
// Targets the orders example feature from bloc-feature-architecture
// (assets/example_orders/).
import 'dart:async';

import 'package:app/core/analytics/analytics_port.dart';
import 'package:app/core/analytics/recording_analytics.dart';
import 'package:app/core/bloc/action_status.dart';
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/domain/orders_repository.dart';
import 'package:app/features/orders/presentation/cubit/orders_cubit.dart';
import 'package:app/features/orders/presentation/cubit/orders_state.dart';
import 'package:app/features/orders/presentation/cubit/place_order_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockOrdersRepository extends Mock implements OrdersRepository {}

const _paid = Order(id: 'o-1', totalCents: 1250, status: OrderStatus.paid);
const _pending = Order(id: 'o-2', totalCents: 990, status: OrderStatus.pending);
const _draft = OrderDraft(productId: 'p-9', quantity: 2);

const _loaded = OrdersState(
  status: OrdersStatus.success,
  orders: [_paid],
  nextPage: 2,
);

void main() {
  late _MockOrdersRepository repository;

  setUpAll(() {
    // any() on a custom type needs a fallback instance, once per file.
    registerFallbackValue(const OrderDraft(productId: '', quantity: 0));
  });

  setUp(() => repository = _MockOrdersRepository());

  group('OrdersCubit.load', () {
    blocTest<OrdersCubit, OrdersState>(
      'emits loading then the first page',
      setUp: () =>
          when(() => repository.fetchOrders(page: any(named: 'page')))
              .thenAnswer((_) async => const Ok([_paid, _pending])),
      build: () => OrdersCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => const [
        OrdersState(status: OrdersStatus.loading),
        OrdersState(
          status: OrdersStatus.success,
          orders: [_paid, _pending],
          nextPage: 2,
        ),
      ],
      verify: (_) => verify(() => repository.fetchOrders(page: 1)).called(1),
    );

    blocTest<OrdersCubit, OrdersState>(
      'emits failure when the first load fails',
      setUp: () =>
          when(() => repository.fetchOrders(page: any(named: 'page')))
              .thenAnswer((_) async => const Err(NetworkFailure())),
      build: () => OrdersCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => const [
        OrdersState(status: OrdersStatus.loading),
        OrdersState(status: OrdersStatus.failure, failure: NetworkFailure()),
      ],
    );

    final bug = StateError('bad json');
    blocTest<OrdersCubit, OrdersState>(
      'reports an unexpected failure through addError',
      setUp: () =>
          when(() => repository.fetchOrders(page: any(named: 'page')))
              .thenAnswer((_) async => Err(UnexpectedFailure(bug))),
      build: () => OrdersCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OrdersState(status: OrdersStatus.loading),
        isA<OrdersState>().having(
          (s) => s.status,
          'status',
          OrdersStatus.failure,
        ),
      ],
      errors: () => [bug],
    );

    test('does not throw when closed mid-request', () async {
      when(() => repository.fetchOrders(page: any(named: 'page')))
          .thenAnswer((_) async => const Ok([_paid]));
      final cubit = OrdersCubit(repository);

      final pending = cubit.load();
      await cubit.close();

      await expectLater(pending, completes);
    });
  });

  group('OrdersCubit.refresh and loadMore', () {
    blocTest<OrdersCubit, OrdersState>(
      'a failed refresh keeps the list on screen and flags the failure',
      setUp: () =>
          when(() => repository.fetchOrders(page: any(named: 'page')))
              .thenAnswer((_) async => const Err(TimeoutFailure())),
      build: () => OrdersCubit(repository),
      seed: () => _loaded,
      act: (cubit) => cubit.refresh(),
      expect: () => [
        _loaded.copyWith(isRefreshing: true),
        _loaded.copyWith(failure: () => const TimeoutFailure()),
      ],
    );

    blocTest<OrdersCubit, OrdersState>(
      'an empty page ends pagination',
      setUp: () =>
          when(() => repository.fetchOrders(page: 2))
              .thenAnswer((_) async => const Ok([])),
      build: () => OrdersCubit(repository),
      seed: () => _loaded,
      act: (cubit) async {
        await cubit.loadMore();
        await cubit.loadMore(); // no next page: must not fetch again
      },
      expect: () => [
        _loaded.copyWith(isLoadingMore: true),
        _loaded.copyWith(nextPage: () => null),
      ],
      verify: (_) => verify(() => repository.fetchOrders(page: 2)).called(1),
    );

    // Regression for the race in the bloc-state-management gotchas: page 2 of
    // the old list must not be appended to the refreshed one.
    test(
      'a load-more response that lands after a refresh is dropped',
      () async {
        final page2 = Completer<Result<List<Order>>>();
        when(() => repository.fetchOrders(page: 2))
            .thenAnswer((_) => page2.future);
        when(() => repository.fetchOrders(page: 1))
            .thenAnswer((_) async => const Ok([_pending]));
        final cubit = OrdersCubit(repository)..emit(_loaded);
        addTearDown(cubit.close);

        final more = cubit.loadMore();
        await cubit.refresh();
        page2.complete(const Ok([_paid]));
        await more;

        expect(cubit.state.orders, [_pending]);
      },
    );
  });

  group('PlaceOrderCubit', () {
    late RecordingAnalytics analytics;

    setUp(() => analytics = RecordingAnalytics());

    blocTest<PlaceOrderCubit, ActionStatus>(
      'succeeds once and records order_placed',
      setUp: () =>
          when(() => repository.placeOrder(any()))
              .thenAnswer((_) async => const Ok('o-3')),
      build: () => PlaceOrderCubit(repository, analytics),
      act: (cubit) => cubit.place(_draft),
      expect: () => [
        isA<ActionRunning>(),
        isA<ActionSucceeded<String>>().having((s) => s.value, 'value', 'o-3'),
      ],
      verify: (_) {
        verify(() => repository.placeOrder(_draft)).called(1);
        expect(analytics.eventsOfType<OrderPlaced>(), const [
          OrderPlaced(orderId: 'o-3', itemCount: 2),
        ]);
      },
    );

    blocTest<PlaceOrderCubit, ActionStatus>(
      'a second tap while the first is in flight is ignored',
      setUp: () =>
          when(() => repository.placeOrder(any()))
              .thenAnswer((_) async => const Ok('o-3')),
      build: () => PlaceOrderCubit(repository, analytics),
      act: (cubit) => Future.wait([cubit.place(_draft), cubit.place(_draft)]),
      expect: () => [isA<ActionRunning>(), isA<ActionSucceeded<String>>()],
      verify: (_) => verify(() => repository.placeOrder(any())).called(1),
    );

    blocTest<PlaceOrderCubit, ActionStatus>(
      'an unknown outcome surfaces as such, is not retried, is not tracked',
      setUp: () =>
          when(() => repository.placeOrder(any()))
              .thenAnswer((_) async => const Err(OutcomeUnknownFailure())),
      build: () => PlaceOrderCubit(repository, analytics),
      act: (cubit) => cubit.place(_draft),
      expect: () => [
        isA<ActionRunning>(),
        isA<ActionFailed>().having(
          (s) => s.failure,
          'failure',
          isA<OutcomeUnknownFailure>(),
        ),
      ],
      verify: (_) {
        verify(() => repository.placeOrder(any())).called(1);
        expect(analytics.events, isEmpty);
      },
    );
  });
}
