// Target: test/features/orders/presentation/widgets/orders_effects_listener_test.dart
import 'package:app/core/bloc/action_status.dart';
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/failures/failure_copy.dart';
import 'package:app/features/orders/presentation/cubit/place_order_cubit.dart';
import 'package:app/features/orders/presentation/widgets/orders_effects_listener.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MockPlaceOrderCubit extends MockCubit<ActionStatus>
    implements PlaceOrderCubit {}

class _FixedCopy implements FailureCopy {
  @override
  String of(AppFailure failure) => switch (failure) {
    OutcomeUnknownFailure() => 'Checking the order status',
    _ => 'Could not place the order',
  };
}

/// Pumps the listener on `/` with real go_router routes, so navigation is
/// asserted by what ends up on screen.
Future<void> _pump(WidgetTester tester, List<ActionStatus> states) async {
  final cubit = _MockPlaceOrderCubit();
  whenListen(
    cubit,
    Stream<ActionStatus>.fromIterable(states),
    initialState: const ActionIdle(),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: OrdersEffectsListener(child: Text('checkout')),
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const Scaffold(body: Text('orders list')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) =>
            Scaffold(body: Text('order ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    RepositoryProvider<FailureCopy>.value(
      value: _FixedCopy(),
      child: BlocProvider<PlaceOrderCubit>.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('success navigates to the new order by id', (tester) async {
    await _pump(tester, const [ActionRunning(), ActionSucceeded('o-3')]);

    expect(find.text('order o-3'), findsOneWidget);
  });

  testWidgets('unknown outcome shows the status copy once and opens the list', (
    tester,
  ) async {
    await _pump(tester, const [
      ActionRunning(),
      ActionFailed(OutcomeUnknownFailure()),
    ]);

    expect(find.text('Checking the order status'), findsOneWidget);
    expect(find.text('orders list'), findsOneWidget);
  });

  testWidgets('a refusal shows copy and stays on the screen', (tester) async {
    await _pump(tester, const [
      ActionRunning(),
      ActionFailed(ValidationFailure(code: 'out_of_stock')),
    ]);

    expect(find.text('Could not place the order'), findsOneWidget);
    expect(find.text('checkout'), findsOneWidget);
  });
}
